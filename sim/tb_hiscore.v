// Functional testbench for the generic per-variant hiscore controller.
// Models the u_rams port-B tap (altsyncram BIDIR: address registered + gated by
// enable_b, output unregistered -> 1 enabled-clock read latency; write commits on
// an enabled clock). Verifies the NVRAM model end to end, including the exact bugs
// that broke Pac-Man on device:
//   [1] valid save (marker present) -> inject regions raw
//   [2] FRESH card (no marker) -> do NOT inject (else "HIGH SCORE"->"HIG0", "000000")
//   [3] round-trip: fresh boot -> game writes a score -> snapshot -> reboot -> restore
//   [4] 4-region game (Ponpoko) -> gate/inject/snapshot terminate (no ri wrap wedge)
//   [5] per-mod offsets (Woodpecker)
`timescale 1ns/1ps
`default_nettype none

module tb_hiscore;
    localparam [7:0] MAGIC = 8'h5A;
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
        if (pause_run > 16'd8000) pause_stuck <= 1'b1;     // wedge detector (ri-wrap, etc.)
    end

    task chk(input [11:0] a, input [7:0] exp, input [255:0] name);
        if (mem[a] !== exp) begin
            $display("  FAIL %0s: mem[%03x]=%02x exp %02x", name, a, mem[a], exp); fails=fails+1;
        end
    endtask
    task chk_sh(input [7:0] a, input [7:0] exp, input [255:0] name);
        begin sv_rd_addr=a; #1;
            if (sv_rd_data !== exp) begin
                $display("  FAIL %0s: shadow[%0d]=%02x exp %02x", name, a, sv_rd_data, exp); fails=fails+1;
            end
        end
    endtask
    task run_frames(input integer n); integer f;
        for (f=0;f<n;f=f+1) begin vbl=0; repeat(1400)@(posedge clk); vbl=1; repeat(200)@(posedge clk); vbl=0; end
    endtask
    task loadshadow(input integer n, input [7:0] seed, input mark);
        begin
            @(negedge clk);
            for (i=0;i<n;i=i+1) begin sv_wr=1; sv_wr_addr=i[7:0]; sv_wr_data=seed+i[7:0]; @(negedge clk); end
            sv_wr=1; sv_wr_addr=8'd255; sv_wr_data=(mark?MAGIC:8'h00); @(negedge clk);   // (no) marker
            sv_wr=0; @(negedge clk);
        end
    endtask
    task pacman_default;       // RAM in the gate-default state (game booted, no high score)
        begin
            for (i=0;i<4096;i=i+1) mem[i]=8'h00;
            for (i=12'h3ED;i<=12'h3F2;i=i+1) mem[i]=8'h40;   // blank tiles
            mem[12'h3D1]=8'h48;                              // HIGH SCORE label
        end
    endtask

    initial begin
        // ===== [1] Pac-Man, valid save (marker) -> inject raw regions =====
        $display("[1] Pac-Man restore (valid save)");
        reset=1; loaded=0; mod_sel=5'd0; pacman_default;
        repeat(8)@(posedge clk); loadshadow(11, 8'h10, 1'b1); repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(14);
        chk(12'hE88,8'h10,"pm e88"); chk(12'hE8B,8'h13,"pm e8b");
        chk(12'h3ED,8'h14,"pm 3ed"); chk(12'h3F2,8'h19,"pm 3f2"); chk(12'h3D1,8'h1A,"pm 3d1");

        // ===== [2] Pac-Man FRESH (no marker) -> must NOT inject (the on-device bug) =====
        $display("[2] Pac-Man fresh card -> no inject (label/tiles preserved)");
        reset=1; loaded=0; mod_sel=5'd0; pacman_default;
        repeat(8)@(posedge clk); loadshadow(11, 8'h10, 1'b0); repeat(8)@(posedge clk);  // marker cleared
        reset=0; loaded=1; run_frames(14);
        chk(12'h3D1,8'h48,"fresh label intact (not HIG0)");
        chk(12'h3ED,8'h40,"fresh tiles blank (not 000000)");
        chk(12'hE88,8'h00,"fresh score untouched");
        chk_sh(8'd255, MAGIC, "fresh -> marker stamped after first snapshot");

        // ===== [3] round-trip: fresh -> game writes score -> snapshot -> reboot -> restore =====
        $display("[3] Pac-Man save round-trip");
        reset=1; loaded=0; mod_sel=5'd0; pacman_default;
        repeat(8)@(posedge clk); loadshadow(11, 8'h00, 1'b0); repeat(8)@(posedge clk);  // truly fresh
        reset=0; loaded=1; run_frames(10);   // gate passes on the default table during "attract"
        // game beats it: writes score 1500 (BCD 00 15 00 00) + draws its own tiles + label stays
        mem[12'hE88]=8'h00; mem[12'hE89]=8'h15; mem[12'hE8A]=8'h00; mem[12'hE8B]=8'h00;
        mem[12'h3ED]=8'h00; mem[12'h3EE]=8'h00; mem[12'h3EF]=8'h05; mem[12'h3F0]=8'h01;
        mem[12'h3F1]=8'h40; mem[12'h3F2]=8'h40;
        run_frames(6);
        chk_sh(8'd1,8'h15,"snapshot captured score"); chk_sh(8'd255,MAGIC,"marked valid");
        // reboot: shadow (.sav) persists in the DUT; RAM cleared to defaults; reload
        reset=1; loaded=0; pacman_default; repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(14);
        chk(12'hE89,8'h15,"reboot restored score hi byte");
        chk(12'h3EF,8'h05,"reboot restored tile"); chk(12'h3D1,8'h48,"reboot label intact");

        // ===== [4] Ponpoko (mod 11, FOUR regions) -> no ri-wrap wedge =====
        $display("[4] Ponpoko 4-region (no wedge)");
        reset=1; loaded=0; mod_sel=5'd11;
        for (i=0;i<4096;i=i+1) mem[i]=8'h00;
        mem[12'h06C]=8'h0f;            // region2 first byte sval=0f
        mem[12'hC53]=8'h02;            // region3 gate sval/eval=02
        repeat(8)@(posedge clk); loadshadow(29, 8'h30, 1'b1); repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(16);
        // region0 c40/3 <- sh0..2 ; verify first+last region injected (proves all 4 walked)
        chk(12'hC40,8'h30,"ponp r0 first"); chk(12'hC53,8'h30+8'd28,"ponp r3 (last region) injected");

        // ===== [5] Woodpecker (mod 8) per-mod offsets =====
        $display("[5] Woodpecker per-mod offsets");
        reset=1; loaded=0; mod_sel=5'd8;
        for (i=0;i<4096;i=i+1) mem[i]=8'h00;
        for (i=12'h3ED;i<=12'h3F2;i=i+1) mem[i]=8'h40;
        mem[12'hDDA]=8'h03;
        repeat(8)@(posedge clk); loadshadow(10, 8'h20, 1'b1); repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(14);
        chk(12'hE88,8'h20,"wp e88"); chk(12'hE8A,8'h22,"wp e8a");
        chk(12'h3ED,8'h23,"wp 3ed"); chk(12'hDDA,8'h29,"wp dda");
        chk(12'hE8B,8'h00,"wp e8b untouched (len 3)");

        if (pause_stuck) begin $display("  FAIL: pause wedged (CPU frozen / ri wrap)"); fails=fails+1; end
        if (fails==0) $display("==== ALL PASS ===="); else $display("==== %0d FAILS ====", fails);
        $finish;
    end

    initial begin #120000000; $display("TIMEOUT (likely a wedge)"); $finish; end
endmodule
`default_nettype wire
