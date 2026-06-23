// Functional testbench for the generic per-variant hiscore controller.
// Models the u_rams port-B tap (altsyncram BIDIR: address registered + gated by
// enable_b, output unregistered -> 1 enabled-clock read latency; write commits on
// an enabled clock). Verifies the NVRAM model: gate (each region first==sval,
// last==eval) -> inject the saved shadow raw into the region addresses -> snapshot
// RAM back into the shadow. Covers Pac-Man (mod 0) and Woodpecker (mod 8, different
// offsets/gate) plus a fresh (0xFF) card skipping inject.
`timescale 1ns/1ps
`default_nettype none

module tb_hiscore;
    reg clk = 0; always #5 clk = ~clk;
    reg [1:0] div = 0; reg ce = 0;
    always @(posedge clk) begin div <= div + 2'd1; ce <= (div == 2'd0); end

    reg reset = 1, loaded = 0, vbl = 0;
    reg [4:0] mod_sel = 0;
    wire [11:0] hs_address;  wire [7:0] hs_data_in;  reg [7:0] hs_data_out;
    wire hs_write_enable, hs_access_read, hs_access_write, pause;
    reg sv_wr = 0;  reg [7:0] sv_wr_addr = 0;  reg [7:0] sv_wr_data = 0;
    reg [7:0] sv_rd_addr = 0;  wire [7:0] sv_rd_data;

    hiscore #(.POLL_INTERVAL(16'd64)) dut (
        .clk(clk), .ce(ce), .reset(reset), .loaded(loaded), .mod_sel(mod_sel), .vbl(vbl),
        .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(hs_data_out),
        .hs_write_enable(hs_write_enable), .hs_access_read(hs_access_read),
        .hs_access_write(hs_access_write), .pause(pause),
        .sv_wr(sv_wr), .sv_wr_addr(sv_wr_addr), .sv_wr_data(sv_wr_data),
        .sv_rd_addr(sv_rd_addr), .sv_rd_data(sv_rd_data)
    );

    // ---- u_rams port B model (4 KB) ----
    reg [7:0]  mem [0:4095];
    reg [11:0] addr_reg = 0;
    wire       enable_b = hs_access_read | hs_access_write;
    always @(posedge clk) begin
        if (enable_b) begin
            addr_reg <= hs_address;
            if (hs_write_enable) mem[hs_address] <= hs_data_in;
        end
    end
    always @(*) hs_data_out = mem[addr_reg];

    integer i, fails = 0;
    reg [15:0] pause_run = 0; reg pause_stuck = 0;
    always @(posedge clk) begin
        if (pause) pause_run <= pause_run + 16'd1; else pause_run <= 16'd0;
        if (pause_run > 16'd6000) pause_stuck <= 1'b1;
    end

    task chk(input [11:0] a, input [7:0] exp, input [255:0] name);
        begin
            if (mem[a] !== exp) begin
                $display("  FAIL %0s: mem[%03x]=%02x exp %02x", name, a, mem[a], exp);
                fails = fails + 1;
            end
        end
    endtask

    task chk_sh(input [7:0] a, input [7:0] exp, input [255:0] name);
        begin
            sv_rd_addr = a; #1;
            if (sv_rd_data !== exp) begin
                $display("  FAIL %0s: shadow[%0d]=%02x exp %02x", name, a, sv_rd_data, exp);
                fails = fails + 1;
            end
        end
    endtask

    task run_frames(input integer n);
        integer f;
        begin
            for (f = 0; f < n; f = f + 1) begin
                vbl = 0; repeat (1200) @(posedge clk);
                vbl = 1; repeat (200)  @(posedge clk);
                vbl = 0;
            end
        end
    endtask

    task loadshadow(input integer n, input [7:0] seed);
        begin
            @(negedge clk);
            for (i = 0; i < n; i = i + 1) begin
                sv_wr = 1; sv_wr_addr = i[7:0]; sv_wr_data = seed + i[7:0]; @(negedge clk);
            end
            sv_wr = 0; @(negedge clk);
        end
    endtask

    initial begin
        // ============ Pac-Man (mod 0) : e88/4, 3ed/6, 3d1/1(gate=48) ============
        $display("[1] Pac-Man restore (raw region inject)");
        reset = 1; loaded = 0; mod_sel = 5'd0;
        for (i = 0; i < 4096; i = i + 1) mem[i] = 8'h00;
        // default table state so the gate passes
        for (i = 12'h3ED; i <= 12'h3F2; i = i + 1) mem[i] = 8'h40;   // blank tiles
        mem[12'h3D1] = 8'h48;                                        // HIGH SCORE label
        // saved shadow: 11 bytes, 0x10..0x1A
        repeat (10) @(posedge clk);
        loadshadow(11, 8'h10);
        repeat (10) @(posedge clk);
        reset = 0; loaded = 1;
        run_frames(12);
        // region0 e88/4 <- sh0..3 ; region1 3ed/6 <- sh4..9 ; region2 3d1/1 <- sh10
        chk(12'hE88,8'h10,"pm e88"); chk(12'hE89,8'h11,"pm e89");
        chk(12'hE8A,8'h12,"pm e8a"); chk(12'hE8B,8'h13,"pm e8b");
        chk(12'h3ED,8'h14,"pm 3ed"); chk(12'h3EE,8'h15,"pm 3ee"); chk(12'h3EF,8'h16,"pm 3ef");
        chk(12'h3F0,8'h17,"pm 3f0"); chk(12'h3F1,8'h18,"pm 3f1"); chk(12'h3F2,8'h19,"pm 3f2");
        chk(12'h3D1,8'h1A,"pm 3d1");

        // ---- snapshot: change RAM, expect shadow to follow ----
        $display("[2] Pac-Man snapshot (RAM -> shadow)");
        mem[12'hE88] = 8'h99; mem[12'h3F2] = 8'h77;
        run_frames(6);
        chk_sh(8'd0, 8'h99, "snap e88->sh0");
        chk_sh(8'd9, 8'h77, "snap 3f2->sh9");

        // ============ fresh card (0xFF) : must NOT inject ============
        $display("[3] Pac-Man fresh card skips inject");
        reset = 1; loaded = 0; mod_sel = 5'd0;
        for (i = 0; i < 4096; i = i + 1) mem[i] = 8'h00;
        for (i = 12'h3ED; i <= 12'h3F2; i = i + 1) mem[i] = 8'h40;
        mem[12'h3D1] = 8'h48;
        repeat (10) @(posedge clk);
        loadshadow(11, 8'hFF);          // 0xFF.. => fresh
        repeat (10) @(posedge clk);
        reset = 0; loaded = 1;
        run_frames(12);
        chk(12'hE88,8'h00,"fresh e88 untouched"); chk(12'h3ED,8'h40,"fresh 3ed untouched");

        // ============ Woodpecker (mod 8) : e88/3, 3ed/6, dda/1(gate=03) ============
        $display("[4] Woodpecker restore (per-mod offsets)");
        reset = 1; loaded = 0; mod_sel = 5'd8;
        for (i = 0; i < 4096; i = i + 1) mem[i] = 8'h00;
        for (i = 12'h3ED; i <= 12'h3F2; i = i + 1) mem[i] = 8'h40;
        mem[12'hDDA] = 8'h03;                                        // woodpecker gate byte
        repeat (10) @(posedge clk);
        loadshadow(10, 8'h20);          // 10 bytes 0x20..0x29
        repeat (10) @(posedge clk);
        reset = 0; loaded = 1;
        run_frames(12);
        chk(12'hE88,8'h20,"wp e88"); chk(12'hE89,8'h21,"wp e89"); chk(12'hE8A,8'h22,"wp e8a");
        chk(12'h3ED,8'h23,"wp 3ed"); chk(12'h3F2,8'h28,"wp 3f2");
        chk(12'hDDA,8'h29,"wp dda");
        chk(12'hE8B,8'h00,"wp e8b untouched (len 3)");   // outside the 3-byte region

        if (pause_stuck) begin $display("  FAIL: pause wedged (CPU frozen)"); fails = fails + 1; end
        if (fails==0) $display("==== ALL PASS ===="); else $display("==== %0d FAILS ====", fails);
        $finish;
    end

    initial begin #60000000; $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
