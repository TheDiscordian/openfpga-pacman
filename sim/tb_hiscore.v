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
    reg ss_busy = 0;
    wire [11:0] hs_address;  wire [7:0] hs_data_in;  reg [7:0] hs_data_out;
    wire hs_write_enable, hs_access_read, hs_access_write, pause;
    reg sv_wr = 0;  reg [7:0] sv_wr_addr = 0;  reg [7:0] sv_wr_data = 0;
    reg [7:0] sv_rd_addr = 0;  wire [7:0] sv_rd_data;

    hiscore #(.POLL_INTERVAL(16'd64)) dut (
        .clk(clk), .ce(ce), .reset(reset), .loaded(loaded), .mod_sel(mod_sel), .ss_busy(ss_busy), .vbl(vbl),
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
    task shwr(input [7:0] a, input [7:0] d);   // write one shadow (.sav) byte
        begin @(negedge clk); sv_wr=1; sv_wr_addr=a; sv_wr_data=d; @(negedge clk); sv_wr=0; @(negedge clk); end
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

        // ===== [5] Woodpecker (mod 8) value-only restore (0x43ed is value-redraw, not saved) =====
        $display("[5] Woodpecker value-only restore");
        reset=1; loaded=0; mod_sel=5'd8;
        for (i=0;i<4096;i=i+1) mem[i]=8'h00;
        repeat(8)@(posedge clk); loadshadow(3, 8'h20, 1'b1); repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(14);
        chk(12'hE88,8'h20,"wp value e88"); chk(12'hE8A,8'h22,"wp value e8a");
        chk(12'hE8B,8'h00,"wp e8b untouched (len 3)");

        // ===== [6] savestate interlock: ss_busy stalls snapshot (no tap collision) =====
        $display("[6] savestate interlock");
        reset=1; loaded=0; mod_sel=5'd0; pacman_default;
        repeat(8)@(posedge clk); loadshadow(11, 8'h10, 1'b1); repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(12);          // settled, snapshotting (shadow[0]=mem[e88]=10)
        ss_busy=1; mem[12'hE88]=8'hEE;              // a Memory op owns the tap + changes RAM
        run_frames(6);
        chk_sh(8'd0, 8'h10, "ss_busy: snapshot stalled (no garbage latched)");
        ss_busy=0; run_frames(6);
        chk_sh(8'd0, 8'hEE, "after ss_busy: snapshot resumes");

        // ===== [7] per-region: value restores at boot even when display tiles aren't ready (Birdiy) =====
        $display("[7] per-region early value restore (Birdiy)");
        reset=1; loaded=0; mod_sel=5'd4;
        for (i=0;i<4096;i=i+1) mem[i]=8'h00;            // value regions 4c29/4d03 default 0 -> gate matches
        for (i=12'h3ED;i<=12'h3F2;i=i+1) mem[i]=8'hFC;  // display tiles blanked -> gate (30/20) does NOT match
        repeat(8)@(posedge clk); loadshadow(39, 8'h40, 1'b1); repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(14);
        chk(12'hC29, 8'h40,        "birdiy value injected at boot (region0)");
        chk(12'hD03, 8'h40+8'd36,  "birdiy region2 injected at boot");
        chk(12'h3ED, 8'hFC,        "birdiy display NOT injected yet (tiles still blank)");
        chk_sh(8'd255, MAGIC,      "saves even though a display region is unrestorable yet (Ali Baba case)");
        mem[12'h3ED]=8'h30; mem[12'h3F2]=8'h20; run_frames(10);   // game draws the hiscore frame
        chk(12'h3ED, 8'h40+8'd30,  "birdiy display injected once its frame is drawn");

        // ===== [8] Ali Baba (mod 10): value wiped by the boot clear + no attract repaint =====
        // 0x4e88 is BOTH the on-screen high-score source AND gets zeroed by the game's boot
        // clear that runs AFTER our restore. The engine must (a) re-inject the saved value
        // whenever the cell reads fully-cold so it survives the clear, (b) tell 0000 (cold)
        // from a real 4200 score whose first+last bytes are also 0, (c) force the display
        // tiles each time, (d) never snapshot the cold zeros over the saved score.
        $display("[8] Ali Baba value re-inject past the boot clear");
        reset=1; loaded=0; mod_sel=5'd10;
        for (i=0;i<4096;i=i+1) mem[i]=8'h00;            // value 0x4e88-0x4e8b = 0 (cold)
        for (i=12'h3ED;i<=12'h3F2;i=i+1) mem[i]=8'h30;  // display already shows "0000" -> tile gate (40/40) FAILS
        mem[12'h3D1]=8'h48;
        // saved score 4200: value 00 42 00 00, tiles "4200" = 30 30 32 34 40 40, label 48
        shwr(8'd0,8'h00); shwr(8'd1,8'h42); shwr(8'd2,8'h00); shwr(8'd3,8'h00);
        shwr(8'd4,8'h30); shwr(8'd5,8'h30); shwr(8'd6,8'h32); shwr(8'd7,8'h34); shwr(8'd8,8'h40); shwr(8'd9,8'h40);
        shwr(8'd10,8'h48); shwr(8'd255,MAGIC);
        reset=0; loaded=1; run_frames(10);
        chk(12'hE89,8'h42,"alibaba value injected (4200)");
        chk(12'h3EF,8'h32,"alibaba tiles FORCED in despite gate mismatch (the fix)");
        chk(12'h3F0,8'h34,"alibaba tiles forced");
        chk(12'h3D1,8'h48,"alibaba label preserved");
        // the game's boot clear now runs AFTER our restore: zero the value, blank the tiles
        for (i=12'hE88;i<=12'hE8B;i=i+1) mem[i]=8'h00;
        for (i=12'h3ED;i<=12'h3F2;i=i+1) mem[i]=8'h40;
        run_frames(8);
        chk(12'hE89,8'h42,"alibaba value RE-injected past the clear (the fix)");
        chk(12'h3EF,8'h32,"alibaba tiles re-forced past the clear");
        chk_sh(8'd1,8'h42,"saved score preserved (cold zeros not snapshotted over it)");
        // player beats it to 9900 (00 99 00 00): engine must NOT re-inject, must save it
        mem[12'hE88]=8'h00; mem[12'hE89]=8'h99; mem[12'hE8A]=8'h00; mem[12'hE8B]=8'h00;
        run_frames(8);
        chk(12'hE89,8'h99,"beaten score not clobbered by re-inject");
        chk_sh(8'd1,8'h99,"beaten score snapshotted to the save");

        // ===== [9] Mr. TNT (mod 7): boot ldir's the default table then draws it =====
        // Region0 is the 60-byte table (gate 4c/01 = the ROM default), region1 the tiles.
        $display("[9] Mr. TNT value-redraw force-tiles");
        reset=1; loaded=0; mod_sel=5'd7;
        for (i=0;i<4096;i=i+1) mem[i]=8'h00;
        mem[12'hCB3]=8'h4c; mem[12'hCEE]=8'h01;         // table region gate (first 4c, last 01) matches default
        for (i=12'h3ED;i<=12'h3F2;i=i+1) mem[i]=8'h30;  // tiles show "0000" -> tile gate (00/40) FAILS
        repeat(8)@(posedge clk); loadshadow(66, 8'h80, 1'b1); repeat(8)@(posedge clk);
        reset=0; loaded=1; run_frames(16);
        chk(12'hCB3,8'h80,"mrtnt table injected");  chk(12'hCEE,8'hBB,"mrtnt table last byte");
        chk(12'h3ED,8'hBC,"mrtnt tiles FORCED in despite gate mismatch (the fix)");
        chk(12'h3F2,8'hC1,"mrtnt tiles last byte forced");

        // ===== [10] Woodpecker (mod 8): value re-inject past the boot clear (value-only) =====
        // 0x43ed is value-redraw (drawn only on beat), so it is NOT a saved region; only the
        // value 0x4e88 is, and it must survive the boot clear and never snapshot zeros over a
        // real score.
        $display("[10] Woodpecker value re-inject past the boot clear");
        reset=1; loaded=0; mod_sel=5'd8;
        for (i=0;i<4096;i=i+1) mem[i]=8'h00;            // value cold
        shwr(8'd0,8'h00); shwr(8'd1,8'h25); shwr(8'd2,8'h00); shwr(8'd255,MAGIC);  // value
        reset=0; loaded=1; run_frames(10);
        chk(12'hE89,8'h25,"woodp value injected");
        for (i=12'hE88;i<=12'hE8A;i=i+1) mem[i]=8'h00;          // boot clear runs after restore
        run_frames(8);
        chk(12'hE89,8'h25,"woodp value RE-injected past the clear (the fix)");
        chk_sh(8'd1,8'h25,"woodp saved value preserved (not zeroed)");
        mem[12'hE88]=8'h00; mem[12'hE89]=8'h99; mem[12'hE8A]=8'h00;  // player beats it
        run_frames(8);
        chk_sh(8'd1,8'h99,"woodp beaten score snapshotted");

        if (pause_stuck) begin $display("  FAIL: pause wedged (CPU frozen / ri wrap)"); fails=fails+1; end
        if (fails==0) $display("==== ALL PASS ===="); else $display("==== %0d FAILS ====", fails);
        $finish;
    end

    initial begin #120000000; $display("TIMEOUT (likely a wedge)"); $finish; end
endmodule
`default_nettype wire
