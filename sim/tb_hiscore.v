// Functional testbench for the hiscore controller.
// Models the u_rams port-B tap (altsyncram BIDIR: address registered + gated by
// enable_b, output unregistered -> 1 enabled-clock read latency; write commits
// on an enabled clock) plus the Pac-Man behaviour the FSM depends on:
//   * the save loader filling the 4-byte shadow,
//   * the boot RAM-clear (0x4E88=0) and blank tile field (0x43EC..0x43F2=0x40),
//   * the "HIGH SCORE" label tile appearing (0x43D1=0x48) after boot.
// NB 0x43ED is BOTH the gate byte (CHK0) and the LSD tile -- by design.
`timescale 1ns/1ps
`default_nettype none

module tb_hiscore;
    reg clk = 0; always #5 clk = ~clk;
    reg [1:0] div = 0; reg ce = 0;
    always @(posedge clk) begin div <= div + 2'd1; ce <= (div == 2'd0); end

    reg reset = 1, loaded = 0, vbl = 0;
    wire [11:0] hs_address;  wire [7:0] hs_data_in;  reg [7:0] hs_data_out;
    wire hs_write_enable, hs_access_read, hs_access_write, pause;
    reg sv_wr = 0;  reg [3:0] sv_wr_addr = 0;  reg [7:0] sv_wr_data = 0;
    reg [3:0] sv_rd_addr = 0;  wire [7:0] sv_rd_data;

    hiscore #(.RUN_INTERVAL(16'd64)) dut (
        .clk(clk), .ce(ce), .reset(reset), .loaded(loaded), .en_paint(1'b1), .vbl(vbl),
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
        if (pause_run > 16'd4000) pause_stuck <= 1'b1;
    end

    task chk(input [11:0] a, input [7:0] exp, input [255:0] name);
        begin
            if (mem[a] !== exp) begin
                $display("  FAIL %0s: mem[%03x]=%02x exp %02x", name, a, mem[a], exp);
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

    // boot + load a saved score, fire the gate, settle
    task restore(input [7:0] b0, input [7:0] b1, input [7:0] b2, input [7:0] b3);
        begin
            reset = 1; loaded = 0;
            for (i = 0; i < 4096; i = i + 1) mem[i] = 8'h00;
            mem[12'h3EC]=8'h40; mem[12'h3ED]=8'h40; mem[12'h3EE]=8'h40; mem[12'h3EF]=8'h40;
            mem[12'h3F0]=8'h40; mem[12'h3F1]=8'h40; mem[12'h3F2]=8'h40;   // blank field
            mem[12'h3D1]=8'h00;                                          // label not drawn
            repeat (20) @(posedge clk);
            @(negedge clk); sv_wr=1; sv_wr_addr=0; sv_wr_data=b0; @(negedge clk);
                            sv_wr_addr=1; sv_wr_data=b1; @(negedge clk);
                            sv_wr_addr=2; sv_wr_data=b2; @(negedge clk);
                            sv_wr_addr=3; sv_wr_data=b3; @(negedge clk); sv_wr=0;
            repeat (10) @(posedge clk);
            reset = 0; loaded = 1;
            run_frames(4);
            mem[12'h3D1]=8'h48;                                          // draw label -> gate
            run_frames(8);
        end
    endtask

    initial begin
        // ---- scenario 1: 150 (50 01 00 00) -> "   150", full behaviour.
        // The 6 digit tiles ARE the whole value (no x10 / no trailing zero), so
        // 0x43EC must NOT be touched (else 150 reads as "1500"). ----
        $display("[1] restore 150");
        restore(8'h50,8'h01,8'h00,8'h00);
        chk(12'hE88,8'h50,"seed lo"); chk(12'hE8B,8'h00,"seed hi");
        chk(12'h3F2,8'h40,"150 d5"); chk(12'h3F1,8'h40,"150 d4"); chk(12'h3F0,8'h40,"150 d3");
        chk(12'h3EF,8'h01,"150 d2"); chk(12'h3EE,8'h05,"150 d1"); chk(12'h3ED,8'h00,"150 d0");
        chk(12'h3EC,8'h40,"150 0x43EC untouched (no trailing zero)");
        // screen-clear blanks the field -> must repaint
        mem[12'h3EF]=8'h40; mem[12'h3EE]=8'h40; run_frames(4);
        chk(12'h3EF,8'h01,"repaint d2"); chk(12'h3EE,8'h05,"repaint d1");
        // player beats it: ROM writes 200 (00 02 00) + draws its own tiles
        mem[12'hE88]=8'h00; mem[12'hE89]=8'h02; mem[12'hE8A]=8'h00; mem[12'hE8B]=8'h00;
        mem[12'h3EE]=8'h02; mem[12'h3EF]=8'h40; mem[12'h3ED]=8'h00; run_frames(4);
        sv_rd_addr=1; #1; if (sv_rd_data!==8'h02) begin $display("  FAIL: shadow not captured 200 (%02x)",sv_rd_data); fails=fails+1; end
        mem[12'h3EE]=8'hAA; run_frames(4);            // handed off -> must NOT repaint
        if (mem[12'h3EE]!==8'hAA) begin $display("  FAIL: still painting after handoff"); fails=fails+1; end

        // ---- scenario 2: zero / no high score -> field all blank (0x40), no "00" ----
        $display("[2] restore 0 (no high score)");
        restore(8'h00,8'h00,8'h00,8'h00);
        chk(12'h3F2,8'h40,"0 d5"); chk(12'h3F1,8'h40,"0 d4"); chk(12'h3F0,8'h40,"0 d3");
        chk(12'h3EF,8'h40,"0 d2"); chk(12'h3EE,8'h40,"0 d1"); chk(12'h3ED,8'h40,"0 d0");
        chk(12'h3EC,8'h40,"0 trail");

        // ---- scenario 3: 654320 (stored 65 43 20) -> all 6 digits, no leading blank ----
        $display("[3] restore 654320");
        restore(8'h20,8'h43,8'h65,8'h00);
        chk(12'h3F2,8'h06,"654320 d5=6"); chk(12'h3F1,8'h05,"654320 d4=5");
        chk(12'h3F0,8'h04,"654320 d3=4"); chk(12'h3EF,8'h03,"654320 d2=3");
        chk(12'h3EE,8'h02,"654320 d1=2"); chk(12'h3ED,8'h00,"654320 d0=0");
        chk(12'h3EC,8'h40,"654320 0x43EC untouched");

        if (pause_stuck) begin $display("  FAIL: pause wedged (CPU frozen)"); fails=fails+1; end

        if (fails==0) $display("==== ALL PASS ===="); else $display("==== %0d FAILS ====", fails);
        $finish;
    end

    initial begin #40000000; $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
