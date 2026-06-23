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
            5'd8: case (i)                                   // Woodpecker
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
    reg [2:0]  ri;       // region index (must reach "past last" = 4 for 4-region games)
    reg [7:0]  bi;       // byte index within region
    reg [7:0]  sp;       // flat shadow pointer
    reg [15:0] timer;
    reg        halt;
    reg        gate_ok;
    reg        fresh;    // .sav has no validity marker -> do not inject

    // current region (combinational unpack of cfg(mod_sel, ri))
    wire [CW-1:0] cw   = cfg(mod_sel, ri);
    wire          rv   = cw[36];          // region valid
    wire [11:0]   roff = cw[35:24];
    wire [7:0]    rlen = cw[23:16];
    wire [7:0]    rsv  = cw[15:8];
    wire [7:0]    rev  = cw[7:0];
    wire [11:0]   rlast = roff + {4'd0, rlen} - 12'd1;

    // ---- shadow (the .sav image), 256 bytes ----
    reg [7:0] shadow [0:255];
    assign sv_rd_data = shadow[sv_rd_addr];

    localparam [7:0] MAGIC = 8'h5A;   // .sav validity marker, stored at shadow[255]
    localparam S_IDLE=4'd0, S_ARM=4'd1,
               S_GA=4'd2,  S_GA_L=4'd3,  S_GB=4'd4, S_GB_L=4'd5,  // gate: first/last byte per region
               S_INJ=4'd6,                                        // write shadow -> RAM (one byte/cycle)
               S_SN=4'd7,  S_SN_L=4'd8,                           // read RAM -> shadow
               S_HOLD=4'd9;

    always @(posedge clk) begin
        if (sv_wr) shadow[sv_wr_addr] <= sv_wr_data;

        if (reset) begin
            state <= S_IDLE; pause <= 1'b0;
            hs_access_read <= 1'b0; hs_access_write <= 1'b0; hs_write_enable <= 1'b0;
            ri <= 2'd0; bi <= 8'd0; sp <= 8'd0; timer <= 16'd0; halt <= 1'b0;
        end else if (ce) begin
            hs_access_read  <= 1'b0;
            hs_access_write <= 1'b0;
            hs_write_enable <= 1'b0;

            case (state)
            S_IDLE: begin
                pause <= 1'b0;
                if (loaded && cfg(mod_sel, 3'd0) != {CW{1'b0}}) begin
                    fresh <= (shadow[8'd255] != MAGIC);   // no validity marker => never-saved
                    timer <= 16'd2048; state <= S_ARM;
                end
            end

            // wait a beat (game boots / RAM clears), in vblank, paused
            S_ARM: begin
                pause <= 1'b0;
                if (timer != 0) timer <= timer - 16'd1;
                else if (vbl) begin halt <= 1'b0; gate_ok <= 1'b1; ri <= 2'd0; state <= S_GA; end
            end

            // --- gate: every valid region's first byte == sval AND last byte == eval ---
            S_GA: begin
                pause <= 1'b1;
                if (!halt) begin halt <= 1'b1; end          // 1-cycle settle after pause
                else if (!rv) begin                          // walked all regions
                    halt <= 1'b0;
                    if (gate_ok && !fresh) begin ri <= 2'd0; sp <= 8'd0; bi <= 8'd0; state <= S_INJ; end
                    else if (gate_ok && fresh) begin ri <= 2'd0; sp <= 8'd0; bi <= 8'd0; state <= S_SN; end
                    else begin timer <= 16'd2048; state <= S_ARM; end   // not ready -> re-poll
                end else begin
                    hs_address <= roff; hs_access_read <= 1'b1; state <= S_GA_L;
                end
            end
            S_GA_L: begin
                if (hs_data_out != rsv) gate_ok <= 1'b0;
                hs_address <= rlast; hs_access_read <= 1'b1; state <= S_GB_L;
            end
            S_GB_L: begin
                if (hs_data_out != rev) gate_ok <= 1'b0;
                ri <= ri + 2'd1; state <= S_GA; halt <= 1'b1;          // next region (stay settled)
            end

            // --- inject: shadow -> RAM, one byte per cycle, across all regions ---
            S_INJ: begin
                pause <= 1'b1;
                if (!rv) begin ri <= 2'd0; sp <= 8'd0; bi <= 8'd0; state <= S_SN; end
                else begin
                    hs_address <= roff + {4'd0, bi};
                    hs_data_in <= shadow[sp];
                    hs_access_write <= 1'b1; hs_write_enable <= 1'b1;
                    sp <= sp + 8'd1;
                    if (bi + 8'd1 == rlen) begin bi <= 8'd0; ri <= ri + 2'd1; end
                    else bi <= bi + 8'd1;
                end
            end

            // --- snapshot: RAM -> shadow, one byte per 2 cycles, across all regions ---
            S_SN: begin
                pause <= 1'b1;
                if (!rv) begin shadow[8'd255] <= MAGIC; timer <= POLL_INTERVAL; state <= S_HOLD; end
                else begin hs_address <= roff + {4'd0, bi}; hs_access_read <= 1'b1; state <= S_SN_L; end
            end
            S_SN_L: begin
                shadow[sp] <= hs_data_out; sp <= sp + 8'd1;
                if (bi + 8'd1 == rlen) begin bi <= 8'd0; ri <= ri + 2'd1; end
                else bi <= bi + 8'd1;
                state <= S_SN;
            end

            // --- hold between snapshots (CPU runs) ---
            S_HOLD: begin
                pause <= 1'b0;
                if (timer != 0) timer <= timer - 16'd1;
                else if (vbl) begin ri <= 2'd0; sp <= 8'd0; bi <= 8'd0; state <= S_SN; end
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
