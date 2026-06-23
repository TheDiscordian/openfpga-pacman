// MIT License
//
// Copyright (c) 2026 TheDiscordian and openFPGA Pac-Man contributors
//
// High-score persistence for the openFPGA Pac-Man core.
//
// Pac-Man never repaints the HIGH SCORE from work RAM on a timer or at screen
// setup: the value digits are drawn to video RAM only inline, the instant the
// live score beats the stored high score (ROM #2a9b-#2abe). During a session
// that is why a beaten high score stays on screen. But after a reboot, restoring
// a saved score into 0x4E88 triggers no draw -- and the attract demo cannot beat
// a real high score to trigger one -- so the only way to SHOW a restored score
// is to draw the digits ourselves. Pinning 0x4E88 must NOT be done: the compare
// at #2a93 (`ret c`) then aborts forever and the player can never beat it.
//
// So this controller, after the boot gate, each frame (paused, in vblank):
//   * reads the live high score at 0x4E88 and captures it into the save shadow
//     when it has risen (only-increase),
//   * UNTIL the score is first beaten: seeds 0x4E88 from the shadow when it is
//     below the saved value (a floor, never a pin) and paints the saved digits
//     into video RAM 0x43F2(MSD)..0x43ED(LSD), so the restored score is visible
//     and survives screen clears,
//   * ONCE the live score exceeds the saved value (the ROM has drawn the new
//     high score itself), it hands off: snapshot only, never touching 0x4E88 or
//     the tiles again -- native behaviour, exactly as before.
// Tile encoding mirrors the ROM (#2ace): digit 0-9 -> tile 0x00-0x09, blank tile
// 0x40, up to 4 leading zeros suppressed. The shadow IS the APF save image.
//
// CRITICAL: pacman.vhd gates the CPU work-RAM write with `and not (hs_access_read
// or hs_access_write)`, so every tap access is wrapped in a CPU pause, in vblank.
//
// Pac-Man / Ms. Pac-Man (work-RAM offsets, CPU base 0x4000):
//   score      : 0x0E88, 4 bytes BCD (3 active + 0 high byte); stored = displayed (no x10)
//   tiles      : 0x43F2(MSD)..0x43ED(LSD) digits -- the 6 digits ARE the full value
//   start gate : 0x03ED==0x40 AND 0x03D1==0x48 AND 0x0E88==0x00 (boot RAM clear past)

`default_nettype none
module hiscore #(
    parameter [15:0] RUN_INTERVAL = 16'hFFFF   // run-loop tick (~one 60Hz frame); shrink in sim
) (
    input  wire        clk,
    input  wire        ce,
    input  wire        reset,
    input  wire        loaded,
    input  wire        en_paint,   // 1 = Pac-Man-family layout: seed/paint the saved score.
                                   // 0 = other variant: stay idle (the offsets/glyphs below are
                                   // Pac-Man-specific and would paint garbage into its high-score area).
    input  wire        vbl,

    output reg  [11:0] hs_address,
    output reg  [7:0]  hs_data_in,
    input  wire [7:0]  hs_data_out,
    output reg         hs_write_enable,
    output reg         hs_access_read,
    output reg         hs_access_write,
    output reg         pause,

    input  wire        sv_wr,
    input  wire [3:0]  sv_wr_addr,
    input  wire [7:0]  sv_wr_data,
    input  wire [3:0]  sv_rd_addr,
    output wire [7:0]  sv_rd_data
);
    localparam [11:0] SCORE_OFF = 12'hE88;
    localparam [11:0] CHK0_OFF  = 12'h3ED;
    localparam [11:0] CHK1_OFF  = 12'h3D1;
    localparam [11:0] TILE_OFF  = 12'h3EC;   // 0x43EC trailing zero; digits at +1..+6

    // ---- shadow (the .sav image) ----
    reg [7:0]  shadow [0:3];
    reg [7:0]  live   [0:3];
    reg        seed, commit;
    assign sv_rd_data = shadow[sv_rd_addr[1:0]];
    always @(posedge clk) begin
        if (sv_wr)       shadow[sv_wr_addr[1:0]] <= sv_wr_data;
        else if (seed)   {shadow[3],shadow[2],shadow[1],shadow[0]} <= 32'd0;
        else if (commit) {shadow[3],shadow[2],shadow[1],shadow[0]} <=
                         {live[3],live[2],live[1],live[0]};
    end

    // 4-byte BCD magnitude compare (byte 3 most significant)
    wire gt = (live[3]>shadow[3]) ? 1'b1 : (live[3]<shadow[3]) ? 1'b0 :
              (live[2]>shadow[2]) ? 1'b1 : (live[2]<shadow[2]) ? 1'b0 :
              (live[1]>shadow[1]) ? 1'b1 : (live[1]<shadow[1]) ? 1'b0 :
              (live[0]>shadow[0]);
    wire eq = (live[0]==shadow[0]) & (live[1]==shadow[1]) &
              (live[2]==shadow[2]) & (live[3]==shadow[3]);

    // ---- controller ----
    localparam S_WAIT =5'd0,  S_POLLR=5'd1,  S_POLLP=5'd2,
               S_GA_S =5'd3,  S_GA_L =5'd4,  S_GB_S =5'd5, S_GB_L=5'd6,
               S_GC_S =5'd7,  S_GC_L =5'd8,  S_RUN  =5'd9, S_RDP =5'd10,
               S_RD_S =5'd11, S_RD_L =5'd12, S_CMP  =5'd13,
               S_SEED =5'd14, S_PAINT=5'd15;

    reg [4:0]  state;
    reg [1:0]  idx;       // score byte walk (read / re-seed)
    reg [2:0]  tpos;      // tile walk: 6=MSD(0x43F2) .. 1=LSD(0x43ED), 0=trailing(0x43EC)
    reg [15:0] timer;
    reg        halt;
    reg        done;      // score beaten once -> hand off to native ROM drawing
    reg        azero;     // saved value all zero -> blank field (match native blank-for-0)
    reg [2:0]  bc;        // leading-zero blank budget (4)
    reg        sig;       // a significant digit has appeared

    // current paint digit (MSD..LSD) from the shadow (the saved value)
    reg  [3:0] dig;
    always @(*) case (tpos)
        3'd6: dig = shadow[2][7:4];
        3'd5: dig = shadow[2][3:0];
        3'd4: dig = shadow[1][7:4];
        3'd3: dig = shadow[1][3:0];
        3'd2: dig = shadow[0][7:4];
        3'd1: dig = shadow[0][3:0];
        default: dig = 4'd0;
    endcase

    always @(posedge clk) begin
        seed   <= 1'b0;
        commit <= 1'b0;

        if (reset) begin
            state <= S_WAIT; pause <= 1'b0; idx <= 2'd0; timer <= 16'd0; halt <= 1'b0;
            done <= 1'b0;
            hs_access_read <= 1'b0; hs_access_write <= 1'b0; hs_write_enable <= 1'b0;
        end else if (ce) begin
            hs_access_read  <= 1'b0;
            hs_access_write <= 1'b0;
            hs_write_enable <= 1'b0;

            case (state)
            S_WAIT: begin
                pause <= 1'b0;
                if (loaded && en_paint) begin
                    if ((shadow[0]==8'hFF) & (shadow[1]==8'hFF) &
                        (shadow[2]==8'hFF) & (shadow[3]==8'hFF))
                        seed <= 1'b1;                 // fresh card -> 0
                    timer <= 16'd2048; state <= S_POLLR;
                end
            end

            // --- start gate: boot done + RAM clear past (CPU paused to read) ---
            S_POLLR: begin pause<=1'b0; if (timer!=0) timer<=timer-16'd1;
                           else if (vbl) begin halt<=1'b0; state<=S_POLLP; end end
            S_POLLP: begin pause<=1'b1; if (halt) state<=S_GA_S; halt<=1'b1; end
            S_GA_S:  begin hs_address<=CHK0_OFF; hs_access_read<=1'b1; state<=S_GA_L; end
            S_GA_L:  begin if (hs_data_out==8'h40) state<=S_GB_S;
                           else begin timer<=16'd2048; state<=S_POLLR; end end
            S_GB_S:  begin hs_address<=CHK1_OFF; hs_access_read<=1'b1; state<=S_GB_L; end
            S_GB_L:  begin if (hs_data_out==8'h48) state<=S_GC_S;
                           else begin timer<=16'd2048; state<=S_POLLR; end end
            S_GC_S:  begin hs_address<=SCORE_OFF; hs_access_read<=1'b1; state<=S_GC_L; end
            S_GC_L:  begin if (hs_data_out==8'h00) begin timer<=16'd0; state<=S_RUN; end
                           else begin timer<=16'd2048; state<=S_POLLR; end end

            // --- run loop: read score each frame ---
            S_RUN: begin pause<=1'b0; if (timer!=0) timer<=timer-16'd1;
                         else if (vbl) begin halt<=1'b0; idx<=2'd0; state<=S_RDP; end end
            S_RDP: begin pause<=1'b1; if (halt) state<=S_RD_S; halt<=1'b1; end
            S_RD_S: begin hs_address<=SCORE_OFF+{10'd0,idx}; hs_access_read<=1'b1; state<=S_RD_L; end
            S_RD_L: begin live[idx]<=hs_data_out;
                          if (idx==2'd3) state<=S_CMP; else begin idx<=idx+2'd1; state<=S_RD_S; end end
            S_CMP: begin
                if (gt) commit <= 1'b1;                          // only-increase capture
                if (done || gt) begin
                    if (gt) done <= 1'b1;                        // beaten: ROM owns the display now
                    timer <= RUN_INTERVAL; state <= S_RUN;          // snapshot only from here
                end else begin                                  // eq/lt: keep the saved score shown
                    azero <= (shadow[0]==0)&(shadow[1]==0)&(shadow[2]==0);
                    bc <= 3'd4; sig <= 1'b0; tpos <= 3'd6;
                    if (!eq) begin idx<=2'd0; state<=S_SEED; end // lt: re-seed the 0x4E88 floor
                    else state <= S_PAINT;
                end
            end
            S_SEED: begin                                        // 0x4E88 floor = shadow (not pinned)
                hs_address<=SCORE_OFF+{10'd0,idx}; hs_data_in<=shadow[idx];
                hs_access_write<=1'b1; hs_write_enable<=1'b1;
                if (idx==2'd3) state<=S_PAINT; else idx<=idx+2'd1;
            end
            S_PAINT: begin                                       // walk the 6 digit tiles MSD..LSD
                hs_address<=TILE_OFF+{9'd0,tpos};
                hs_access_write<=1'b1; hs_write_enable<=1'b1;
                if (azero)             hs_data_in<=8'h40;                 // no high score: blank
                else if (dig==4'd0 && !sig && bc!=3'd0) begin
                                       hs_data_in<=8'h40; bc<=bc-3'd1;    // suppressed leading zero
                end else begin
                                       hs_data_in<={4'd0,dig};           // digit glyph 0x00-0x09
                                       if (dig!=4'd0) sig<=1'b1;
                end
                if (tpos==3'd1) begin timer<=RUN_INTERVAL; state<=S_RUN; end
                else tpos<=tpos-3'd1;
            end

            default: state <= S_WAIT;
            endcase
        end
    end
endmodule
`default_nettype wire
