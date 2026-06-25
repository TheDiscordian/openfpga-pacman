// MIT License
//
// Copyright (c) 2026 TheDiscordian and openFPGA Pac-Man contributors
//
// Generic per-variant high-score persistence for the openFPGA Pac-Man core.
//
// NVRAM model (MAME hiscore.dat semantics), not a glyph painter: each game's
// high-score lives in a set of work-RAM regions. We poll until the game has set
// up its default table (each region's first byte == its start value and last
// byte == its end value), inject the saved bytes ONCE, then snapshot the regions
// every poll so the .sav tracks the live high score. Restoring the raw bytes
// (score + the displayed tile RAM) is what makes the value show after a reboot --
// no per-game digit painting needed, so this works for every variant uniformly.
//
// The per-mod region table is sourced from MAME plugins/hiscore/hiscore.dat
// (cross-checked vs the MiSTer MRAs); addresses are resolved to 0x4000-region
// offsets (Birdiy's tiles are the 0x43ED mirror of the hiscore.dat 0xC3ED).
// Mods with no table (Eeekk!, Jump Shot) have no regions -> the engine stays idle.
//
// CRITICAL: pacman.vhd gates the CPU work-RAM write with `and not (hs_access_read
// or hs_access_write)`, so every tap access is wrapped in a CPU pause, in vblank.
// A never-written save carries no validity marker (shadow[255] != MAGIC) -> skip
// inject and leave the game's own default table (injecting an empty save would
// stamp zeros over the label/tile RAM, e.g. "HIGH SCORE" -> "HIG0 SCORE"). The
// first snapshot stamps the marker, so later boots restore. (Do NOT guess "fresh"
// from a byte value: a cleared Pocket slot reads back 0x00, not 0xFF.)

`default_nettype none
module hiscore #(
    parameter [15:0] POLL_INTERVAL = 16'hFFFF   // run-loop tick (~one 60Hz frame); shrink in sim
) (
    input  wire        clk,
    input  wire        ce,
    input  wire        reset,
    input  wire        loaded,
    input  wire        vbl,
    input  wire [4:0]  mod_sel,     // MiSTer mod number; selects the per-game region table
    input  wire        ss_busy,     // a Memory (savestate) op owns the shared work-RAM tap

    output reg  [11:0] hs_address,
    output reg  [7:0]  hs_data_in,
    input  wire [7:0]  hs_data_out,
    output reg         hs_write_enable,
    output reg         hs_access_read,
    output reg         hs_access_write,
    output reg         pause,

    input  wire        sv_wr,
    input  wire [7:0]  sv_wr_addr,
    input  wire [7:0]  sv_wr_data,
    input  wire [7:0]  sv_rd_addr,
    output wire [7:0]  sv_rd_data
);
    // ---- per-mod region table: packed {valid, off[11:0], len[7:0], sval[7:0], eval[7:0]} ----
    localparam CW = 37;
    function [CW-1:0] R; input [11:0] o; input [7:0] l; input [7:0] s; input [7:0] e;
        R = {1'b1, o, l, s, e};
    endfunction
    function [CW-1:0] cfg; input [4:0] m; input [2:0] i;
        begin
            cfg = {CW{1'b0}};
            case (m)
            5'd0, 5'd5, 5'd1: case (i)                       // Pac-Man / Ms. Pac-Man / Pac-Man Plus
                2'd0: cfg = R(12'he88, 8'd4,  8'h00, 8'h00);
                2'd1: cfg = R(12'h3ed, 8'd6,  8'h40, 8'h40);
                2'd2: cfg = R(12'h3d1, 8'd1,  8'h48, 8'h48);
                default: cfg = {CW{1'b0}}; endcase
            5'd2: case (i)                                   // Club
                2'd0: cfg = R(12'he88, 8'd4,  8'h00, 8'h00);
                2'd1: cfg = R(12'h3ed, 8'd6,  8'h40, 8'h40);
                2'd2: cfg = R(12'h3d1, 8'd1,  8'h59, 8'h59);
                2'd3: cfg = R(12'h3cb, 8'h0a, 8'h4f, 8'h4d); endcase
            5'd4: case (i)                                   // Birdiy (c3ed -> 43ed mirror)
                2'd0: cfg = R(12'hc29, 8'h1e, 8'h00, 8'h00);
                2'd1: cfg = R(12'h3ed, 8'd6,  8'h30, 8'h20);
                2'd2: cfg = R(12'hd03, 8'd3,  8'h00, 8'h00);
                default: cfg = {CW{1'b0}}; endcase
            5'd7: case (i)                                   // Mr. TNT
                2'd0: cfg = R(12'hcb3, 8'h3c, 8'h4c, 8'h01);
                2'd1: cfg = R(12'h3ed, 8'd6,  8'h00, 8'h40);
                default: cfg = {CW{1'b0}}; endcase
            5'd8: case (i)                                   // Woodpecker -- like MAME: save value + the drawn digit row. The row (0x43ed) is only valid when it holds digits; at boot it is uninitialised graphic tiles, so the snapshot is digit-guarded (guard_disp) to capture it ONLY when it is real digits, never the garbage.
                2'd0: cfg = R(12'he88, 8'd3,  8'h00, 8'h00);
                2'd1: cfg = R(12'h3ed, 8'd6,  8'h40, 8'h40);
                2'd2: cfg = R(12'hdda, 8'd1,  8'h03, 8'h03);
                default: cfg = {CW{1'b0}}; endcase
            5'd10: case (i)                                  // Ali Baba
                2'd0: cfg = R(12'he88, 8'd4,  8'h00, 8'h00);
                2'd1: cfg = R(12'h3ed, 8'd6,  8'h40, 8'h40);
                2'd2: cfg = R(12'h3d1, 8'd1,  8'h48, 8'h48);
                default: cfg = {CW{1'b0}}; endcase
            5'd11: case (i)                                  // Ponpoko
                2'd0: cfg = R(12'hc40, 8'd3,  8'h00, 8'h00);
                2'd1: cfg = R(12'he5a, 8'h13, 8'h00, 8'h00);
                2'd2: cfg = R(12'h06c, 8'd6,  8'h0f, 8'h00);
                2'd3: cfg = R(12'hc53, 8'd1,  8'h02, 8'h02); endcase
            5'd12: case (i)                                  // Van-Van Car
                2'd0: cfg = R(12'h809, 8'd6,  8'h00, 8'h00);
                2'd1: cfg = R(12'hc60, 8'hf0, 8'h00, 8'h00);
                default: cfg = {CW{1'b0}}; endcase
            5'd14: case (i)                                  // Dream Shopper
                2'd0: cfg = R(12'hc00, 8'hf0, 8'h00, 8'h01);
                2'd1: cfg = R(12'h808, 8'd6,  8'h00, 8'h00);
                2'd2: cfg = R(12'h809, 8'd1,  8'h03, 8'h03);
                default: cfg = {CW{1'b0}}; endcase
            default: cfg = {CW{1'b0}};
            endcase
        end
    endfunction

    // FSM state (declared before the cfg unpack below, which reads `ri`)
    reg [3:0]  state;
    reg [2:0]  ri;       // region index (reaches "past last" = up to 4)
    reg [7:0]  bi;       // byte index within region
    reg [7:0]  sp;       // shadow base of the current region
    reg [15:0] timer;
    reg        halt;
    reg        gate_ok;  // per-region: first byte matched its sval
    reg        fresh;    // .sav has no validity marker -> do not inject
    reg [3:0]  injected; // per-region one-shot: bit set once region ri has been restored
    reg        r0_now;   // value region (re)injected this walk -> force the display tiles
    reg [3:0]  cold;     // per-region: scanned fully-cold this poll -> re-inject + skip snapshot (preserve saved)
    reg        disp_ok;  // guarded display region scanned as all-valid digit/blank tiles this poll

    // current region (combinational unpack of cfg(mod_sel, ri))
    wire [CW-1:0] cw   = cfg(mod_sel, ri);
    wire          rv   = cw[36];          // region valid
    wire [11:0]   roff = cw[35:24];
    wire [7:0]    rlen = cw[23:16];
    wire [7:0]    rsv  = cw[15:8];
    wire [7:0]    rev  = cw[7:0];
    wire [11:0]   rlast = roff + {4'd0, rlen} - 12'd1;
    // Some games recompute the on-screen high-score digits from the value cell on
    // every screen build (incl. attract) -- Ali Baba redraws 0x43ed from 0x4e88 each
    // maze build; Mr. TNT ldir's the ROM-default table over 0x4cb3 at boot then draws
    // it. For those, restoring the value alone shows nothing until the game happens to
    // redraw; so the instant the value (region 0) is restored we ALSO force the display
    // tile region (region 1) in, bypassing its own gate, so the saved number shows now
    // and the restored value keeps later redraws correct. One-shot via injected[1].
    wire          vredraw    = (mod_sel == 5'd7) || (mod_sel == 5'd10) || (mod_sel == 5'd14);  // Dream Shopper redraws its row from the value every frame too
    // Ali Baba also WIPES the value cell with its boot clear and never repaints the score
    // in attract, so a one-shot restore loses the race; for it the value region re-injects
    // whenever it reads fully-cold (see S_ZS) and the tiles re-force each time (r0_now).
    wire          vr_ab      = (mod_sel == 5'd10);
    wire          force_disp = vredraw && (ri == 3'd1) && (vr_ab ? r0_now : injected[0]);
    // GENERAL boot-clear-wipe protection. The FPGA work RAM powers up to 0, which our
    // first/last gate can't tell from a game's own boot clear/blank -- and that clear runs
    // AFTER our one-shot restore, wiping it, then the snapshot saves the blank over the .sav
    // (this erased Ali Baba's and Woodpecker's scores). For every small uniform high-score
    // data region (BCD value cells, blank-tile display rows -- sval==eval), scan ALL bytes
    // each poll: re-inject the saved bytes whenever the region reads fully at its default
    // (surviving the wipe), and never snapshot that default over a real saved score. Large
    // tables and 1-byte flag/label cells keep the cheap first/last gate; value-redraw display
    // tiles (region 1 of Ali Baba / Mr. TNT) use force_disp instead.
    wire          scan_uni   = (rsv == rev) && (rlen >= 8'd2) && (rlen <= 8'd240) && !(vredraw && ri == 3'd1);
    // Woodpecker's digit row (region 1) is only painted by the ROM when the score is
    // beaten; at boot it holds uninitialised graphic tiles. The plain scan_uni snapshot
    // would capture that garbage (it isn't blank, so it isn't "cold"). So when snapshotting
    // THIS region, also require every byte to be a real digit tile (0x30-0x39) or blank
    // (0x40) -- otherwise skip and keep the last valid saved row. This is how MAME's clean
    // (at-exit) capture is matched without painting anything ourselves.
    // Any uniform display-tile row in VIDEO RAM (offset < 0x400) -- the on-screen digit
    // rows (0x43ed etc.) -- can hold uninitialised graphic tiles (0x3a-0x3f) at boot before
    // the game paints digits; the continuous snapshot would capture that garbage and restore
    // `?=?=?=`. So for any such region, only snapshot it when every byte is a digit
    // (0x30-0x39) or the region's own pad/blank tile (its sval/eval). Value/table regions
    // live in work RAM (offset >= 0x400) and are not affected.
    wire          guard_disp = scan_uni && (roff < 12'h400);
    wire          byte_digit = ((hs_data_out >= 8'h30) && (hs_data_out <= 8'h39)) || (hs_data_out == rsv) || (hs_data_out == rev);
    // ---- shadow (the .sav image), 256 bytes ----
    reg [7:0] shadow [0:255];
    assign sv_rd_data = shadow[sv_rd_addr];

    localparam [7:0] MAGIC = 8'h5A;   // .sav validity marker, stored at shadow[255]
    localparam S_IDLE=4'd0, S_ARM=4'd1,
               S_WALK=4'd2, S_G1=4'd3, S_G2=4'd4,   // per-region gate (first==sval && last==eval)
               S_RINJ=4'd5,                          // inject one region (shadow -> RAM)
               S_SN=4'd6,  S_SN_L=4'd7,              // snapshot all regions (RAM -> shadow)
               S_HOLD=4'd8,
               S_ZS=4'd9;                            // value region: scan all bytes for the fully-cold state

    always @(posedge clk) begin
        if (sv_wr) shadow[sv_wr_addr] <= sv_wr_data;

        if (reset) begin
            state <= S_IDLE; pause <= 1'b0;
            hs_access_read <= 1'b0; hs_access_write <= 1'b0; hs_write_enable <= 1'b0;
            ri <= 3'd0; bi <= 8'd0; sp <= 8'd0; timer <= 16'd0; halt <= 1'b0; injected <= 4'd0;
            r0_now <= 1'b0; cold <= 4'd0; disp_ok <= 1'b1;
        end else if (ce) begin
            hs_access_read  <= 1'b0;
            hs_access_write <= 1'b0;
            hs_write_enable <= 1'b0;

            if (ss_busy && state != S_IDLE && state != S_ARM && state != S_HOLD) begin
                // a Memory (savestate) op owns the shared work-RAM tap. Abort our in-flight
                // walk/inject without latching a read or committing a write (tap strobes are
                // already cleared above); re-walk once it is done. injected[] persists, so a
                // finished region is not redone (an aborted region is, since it was unmarked).
                ri <= 3'd0; sp <= 8'd0; bi <= 8'd0; timer <= 16'd2048; state <= S_ARM;
            end else
            case (state)
            S_IDLE: begin
                pause <= 1'b0;
                if (loaded && cfg(mod_sel, 3'd0) != {CW{1'b0}}) begin
                    fresh <= (shadow[8'd255] != MAGIC);   // no validity marker => never-saved
                    injected <= 4'd0;
                    timer <= 16'd2048; state <= S_ARM;
                end
            end

            // wait a beat (game boots / RAM clears), then (re)start a region walk
            S_ARM: begin
                pause <= 1'b0;
                if (timer != 0) timer <= timer - 16'd1;
                else if (vbl && !ss_busy) begin
                    ri <= 3'd0; sp <= 8'd0; bi <= 8'd0; halt <= 1'b0; r0_now <= 1'b0; state <= S_WALK;
                end
            end

            // Each poll: walk the regions, inject each ONE the moment its own gate holds (first
            // byte==sval && last byte==eval) -- the score VALUE region's default is 0 (true at
            // boot) so it restores immediately, display-tile regions restore once the game has
            // drawn their frame -- then ALWAYS snapshot. Snapshot does NOT wait for every region
            // to be restorable, so a remapped variant whose display tiles never hit the gate (e.g.
            // Ali Baba) still saves its score every poll.
            S_WALK: begin
                pause <= 1'b1;
                if (!halt) halt <= 1'b1;                              // settle after pause
                else if (!rv) begin                                  // walked all regions -> snapshot
                    halt <= 1'b0; ri <= 3'd0; sp <= 8'd0; bi <= 8'd0; state <= S_SN;
                end else if (scan_uni) begin                         // uniform data region: full-cold scan (re-inject past the boot wipe)
                    gate_ok <= 1'b1; disp_ok <= 1'b1; bi <= 8'd0; hs_address <= roff; hs_access_read <= 1'b1; state <= S_ZS;
                end else if (injected[ri[1:0]] && !(vr_ab && ri == 3'd1)) begin
                    sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1;         // already restored -> skip (Ali Baba tiles stay re-forceable)
                end else begin
                    gate_ok <= 1'b1; hs_address <= roff; hs_access_read <= 1'b1; state <= S_G1;
                end
            end
            S_G1: begin
                if (hs_data_out != rsv) gate_ok <= 1'b0;
                hs_address <= rlast; hs_access_read <= 1'b1; state <= S_G2;
            end
            S_G2: begin
                if (!fresh && (force_disp || (gate_ok && hs_data_out == rev))) begin bi <= 8'd0; state <= S_RINJ; end  // ready (or value-redraw force) + real save -> inject
                else begin sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1; halt <= 1'b1; state <= S_WALK; end
            end

            // Scan ALL bytes of a uniform region for the fully-cold state (every byte == sval).
            // The whole-region scan distinguishes the cleared/blank region from a live score
            // whose first+last bytes happen to match the default (e.g. 4200 = 00 42 00 00, both
            // ends 0), so re-injecting the saved bytes whenever the region reads cold restores
            // it past the game's boot clear/blank without ever clobbering a real score.
            S_ZS: begin
                pause <= 1'b1;
                if (hs_data_out != rsv) gate_ok <= 1'b0;
                if (guard_disp && !byte_digit) disp_ok <= 1'b0;   // any non-digit/blank byte -> this row is garbage, don't save it
                if (bi + 8'd1 == rlen) begin
                    if (!fresh && gate_ok && hs_data_out == rsv) begin cold[ri[1:0]] <= 1'b1; bi <= 8'd0; state <= S_RINJ; end
                    else begin cold[ri[1:0]] <= 1'b0; sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1; halt <= 1'b1; state <= S_WALK; end
                end else begin
                    bi <= bi + 8'd1; hs_address <= roff + {4'd0, bi} + 12'd1; hs_access_read <= 1'b1;
                end
            end

            // inject region ri: shadow[sp+bi] -> mem[roff+bi]
            S_RINJ: begin
                pause <= 1'b1;
                hs_address <= roff + {4'd0, bi};
                hs_data_in <= shadow[sp + bi];
                hs_access_write <= 1'b1; hs_write_enable <= 1'b1;
                if (bi + 8'd1 == rlen) begin
                    injected[ri[1:0]] <= 1'b1;
                    if (ri == 3'd0) r0_now <= 1'b1;                   // value (re)injected -> force the display tiles this walk
                    sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1; halt <= 1'b1; state <= S_WALK;
                end else bi <= bi + 8'd1;
            end

            // --- snapshot: RAM -> shadow across all regions, then hold (continuous save) ---
            S_SN: begin
                pause <= 1'b1;
                if (!rv) begin shadow[8'd255] <= MAGIC; timer <= POLL_INTERVAL; state <= S_HOLD; end
                else if (scan_uni && !fresh && cold[ri[1:0]]) begin sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1; end  // region sits at its cold default -> preserve the saved score, do not snapshot the blank/zeros over it
                else if (guard_disp && !fresh && !disp_ok) begin sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1; end  // display row holds non-digit garbage (boot/mid-paint) -> keep the last valid saved row
                else if (!fresh && !injected[ri[1:0]] && !scan_uni) begin sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1; end  // saved-but-not-yet-restored -> keep its loaded save; a fresh card snapshots all (nothing to preserve)
                else begin hs_address <= roff + {4'd0, bi}; hs_access_read <= 1'b1; state <= S_SN_L; end
            end
            S_SN_L: begin
                shadow[sp + bi] <= hs_data_out;
                if (bi + 8'd1 == rlen) begin bi <= 8'd0; sp <= sp + {1'b0, rlen}; ri <= ri + 3'd1; end
                else bi <= bi + 8'd1;
                state <= S_SN;
            end

            // --- hold between polls (CPU runs); next poll re-walks (inject newly-ready) + snapshots ---
            S_HOLD: begin
                pause <= 1'b0;
                if (timer != 0) timer <= timer - 16'd1;
                else if (vbl && !ss_busy) begin ri <= 3'd0; sp <= 8'd0; bi <= 8'd0; halt <= 1'b0; r0_now <= 1'b0; state <= S_WALK; end
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
