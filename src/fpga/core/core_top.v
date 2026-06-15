//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign dram_a = 'h0;
assign dram_ba = 'h0;
assign dram_dq = {16{1'bZ}};
assign dram_dqm = 'h0;
assign dram_clk = 'h0;
assign dram_cke = 'h0;
assign dram_ras_n = 'h1;
assign dram_cas_n = 'h1;
assign dram_we_n = 'h1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


// for bridge write data, we just broadcast it to all bus devices
// for bridge read data, we have to mux it
// add your own devices here
always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    32'h10xxxxxx: begin
        // example
        // bridge_rd_data <= example_device_data;
        bridge_rd_data <= 0;
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    endcase
end


//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked_s; 
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;
    
    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported;
    wire    [31:0]  savestate_addr;
    wire    [31:0]  savestate_size;
    wire    [31:0]  savestate_maxloadsize;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
    
    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    reg             target_dataslot_read;       
    reg             target_dataslot_write;
    reg             target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg             target_dataslot_openfile;   // require additional param/resp structs to be mapped
    
    wire            target_dataslot_ack;        
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    reg     [15:0]  target_dataslot_id;
    reg     [31:0]  target_dataslot_slotoffset;
    reg     [31:0]  target_dataslot_bridgeaddr;
    reg     [31:0]  target_dataslot_length;
    
    wire    [31:0]  target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire    [31:0]  target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands
    
// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire            datatable_wren;
    wire    [31:0]  datatable_data;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),
    
    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),
    
    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),
    
    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),
    
    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);



////////////////////////////////////////////////////////////////////////////////////////



// video generation
// ~12,288,000 hz pixel clock
//
// we want our video mode of 320x240 @ 60hz, this results in 204800 clocks per frame
// we need to add hblank and vblank times to this, so there will be a nondisplay area. 
// it can be thought of as a border around the visible area.
// to make numbers simple, we can have 400 total clocks per line, and 320 visible.
// dividing 204800 by 400 results in 512 total lines per frame, and 240 visible.
// this pixel clock is fairly high for the relatively low resolution, but that's fine.
// PLL output has a minimum output frequency anyway.


assign video_rgb_clock = clk_pix;
assign video_rgb_clock_90 = clk_pix_90;
assign video_rgb = vidout_rgb;
assign video_de = vidout_de;
assign video_skip = vidout_skip;
assign video_vs = vidout_vs;
assign video_hs = vidout_hs;

    // -----------------------------------------------------------------------
    // Pac-Man video. The PACMAN core scans its native ~288x224 raster and
    // updates RGB + blank/sync on the ENA_6 (6.144 MHz) beat in the clk_sys
    // domain. clk_pix is the same 6.144 MHz PLL output, so we register one
    // fresh pixel per clk_pix edge. Portrait rotation is the scaler's job
    // (video.json rotation:270). 3:3:2 core RGB -> 8:8:8.
    // -----------------------------------------------------------------------
    wire [2:0]  core_r, core_g;
    wire [1:0]  core_b;
    wire        core_hsync, core_vsync, core_hblank, core_vblank;

    reg [23:0]  vidout_rgb;
    reg         vidout_de;
    reg         vidout_skip;
    reg         vidout_vs;
    reg         vidout_hs;

    // Border: auto-detect the core's active window from its blanking edges,
    // then grow it by BORDER px of black on every side. The scaler shrinks the
    // larger frame to the panel, leaving a thin centred margin. BORDER is at the
    // DE-pixel level (1 ~= a ~10px panel margin); bump for a wider border.
    localparam [9:0] BORDER = 10'd1;

    reg  [9:0] hcnt = 0, vcnt = 0;
    reg        hs_d = 0, vs_d = 0, hb_d = 0, vb_d = 0;
    reg  [9:0] h_start = 0, h_end = 10'h3ff, v_start = 0, v_end = 10'h3ff;

    // The grown window (active +/- BORDER) drives DE for the black margin. RGB is
    // gated on the core's EXACT blanking so no blanking data can leak into the
    // picture (the border ring is therefore always black).
    wire in_window = (hcnt + BORDER >= h_start) && (hcnt <= h_end + BORDER) &&
                     (vcnt + BORDER >= v_start) && (vcnt <= v_end + BORDER);

always @(posedge clk_pix) begin
    hs_d <= core_hsync;  vs_d <= core_vsync;
    hb_d <= core_hblank; vb_d <= core_vblank;

    // pixel/line counters: hcnt resets each line on hsync, vcnt each frame on vsync
    if (core_hsync & ~hs_d) hcnt <= 10'd0;
    else                    hcnt <= hcnt + 10'd1;
    if (core_vsync & ~vs_d)      vcnt <= 10'd0;
    else if (core_hsync & ~hs_d) vcnt <= vcnt + 10'd1;

    // latch the active-window bounds from the blanking edges (stable frame-to-frame)
    if (~core_hblank &  hb_d) h_start <= hcnt;
    if ( core_hblank & ~hb_d) h_end   <= hcnt;
    if (~core_vblank &  vb_d) v_start <= vcnt;
    if ( core_vblank & ~vb_d) v_end   <= vcnt;

    // registered video out: DE across the grown window, black in the border ring
    vidout_skip <= 1'b0;
    vidout_hs   <= core_hsync;
    vidout_vs   <= core_vsync;
    vidout_de   <= in_window;
    vidout_rgb  <= (core_hblank | core_vblank) ? 24'h0 :
                   { core_r, core_r, core_r[2:1],
                     core_g, core_g, core_g[2:1],
                     core_b, core_b, core_b, core_b };
end




//
//
// audio: Namco WSG output -> I2S via sound_i2s (analogue-pocket-utils).
// O_AUDIO is the WSG's unsigned 10-bit sum (0 = silence); feed both channels.
// (The template's silence generator below is now unused and optimised away.)
//
    sound_i2s #(
        .CHANNEL_WIDTH (10),
        .SIGNED_INPUT  (0)
    ) aud (
        .clk_74a    (clk_74a),
        .clk_audio  (clk_sys),
        .audio_l    (pac_audio),
        .audio_r    (pac_audio),
        .audio_mclk (audio_mclk),
        .audio_lrck (audio_lrck),
        .audio_dac  (audio_dac)
    );

// generate MCLK = 12.288mhz with fractional accumulator
    reg         [21:0]  audgen_accum;
    reg                 audgen_mclk;
    parameter   [20:0]  CYCLE_48KHZ = 21'd122880 * 2;
always @(posedge clk_74a) begin
    audgen_accum <= audgen_accum + CYCLE_48KHZ;
    if(audgen_accum >= 21'd742500) begin
        audgen_mclk <= ~audgen_mclk;
        audgen_accum <= audgen_accum - 21'd742500 + CYCLE_48KHZ;
    end
end

// generate SCLK = 3.072mhz by dividing MCLK by 4
    reg [1:0]   aud_mclk_divider;
    wire        audgen_sclk = aud_mclk_divider[1] /* synthesis keep*/;
    reg         audgen_lrck_1;
always @(posedge audgen_mclk) begin
    aud_mclk_divider <= aud_mclk_divider + 1'b1;
end

// shift out audio data as I2S 
// 32 total bits per channel, but only 16 active bits at the start and then 16 dummy bits
//
    reg     [4:0]   audgen_lrck_cnt;    
    reg             audgen_lrck;
    reg             audgen_dac;
always @(negedge audgen_sclk) begin
    audgen_dac <= 1'b0;
    // 48khz * 64
    audgen_lrck_cnt <= audgen_lrck_cnt + 1'b1;
    if(audgen_lrck_cnt == 31) begin
        // switch channels
        audgen_lrck <= ~audgen_lrck;
        
    end 
end


///////////////////////////////////////////////


    wire    clk_sys;       // 49.152 MHz core carrier (ENA_6 = /8 = 6.144 MHz)
    wire    clk_pix;       // 6.144 MHz pixel clock (video_rgb_clock)
    wire    clk_pix_90;    // 6.144 MHz @ 90 deg (video_rgb_clock_90 / DDIO)

    wire    pll_core_locked;
    wire    pll_core_locked_s;
synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( 0 ),

    .outclk_0       ( clk_sys ),
    .outclk_1       ( clk_pix ),
    .outclk_2       ( clk_pix_90 ),

    .locked         ( pll_core_locked )
);


// ===========================================================================
// Pac-Man core integration
// ===========================================================================

    // Clock enables in the clk_sys (49.152 MHz) domain. ENA_6 = 6.144 MHz
    // (pixel + CPU beat, clk_sys/8); ENA_4/ENA_1M79 feed only variant sound
    // chips, unused for Pac-Man / Ms. Pac-Man (approximate dividers are fine).
    reg [2:0] div6   = 0;  reg ce_6m   = 0;
    reg [3:0] div4   = 0;  reg ce_4m   = 0;
    reg [4:0] div179 = 0;  reg ce_1m79 = 0;
    always @(posedge clk_sys) begin
        div6   <= div6 + 3'd1;                               ce_6m   <= (div6   == 3'd0);
        div4   <= (div4   == 4'd11) ? 4'd0 : div4   + 4'd1;  ce_4m   <= (div4   == 4'd0);
        div179 <= (div179 == 5'd27) ? 5'd0 : div179 + 5'd1;  ce_1m79 <= (div179 == 5'd0);
    end

    // Hold the core in reset until the PLL has locked and every required ROM
    // data slot has finished loading.
    wire reset_n_s, dl_complete_s;
    synch_3 s_rst (reset_n,              reset_n_s,     clk_sys);
    synch_3 s_dl  (dataslot_allcomplete, dl_complete_s, clk_sys);
    wire core_reset = ~reset_n_s | ~dl_complete_s;

    // ROM load: APF bridge writes -> the core's MiSTer-style dn_* download bus.
    wire        ioctl_wr;
    wire [15:0] ioctl_addr;
    wire [7:0]  ioctl_data;
    data_loader #(
        .ADDRESS_MASK_UPPER_4 (4'h0),
        .ADDRESS_SIZE         (16),
        .OUTPUT_WORD_SIZE     (1)
    ) rom_loader (
        .clk_74a              (clk_74a),
        .clk_memory           (clk_sys),
        .bridge_wr            (bridge_wr),
        .bridge_endian_little (bridge_endian_little),
        .bridge_addr          (bridge_addr),
        .bridge_wr_data       (bridge_wr_data),
        .write_en             (ioctl_wr),
        .write_addr           (ioctl_addr),
        .write_data           (ioctl_data)
    );

    // Controller: cont1_key bitmap -> Pac-Man IN0/IN1 (active-low). Single
    // player, upright cabinet; coin = Select, start 1P = Start.
    wire m_up    = cont1_key[0];
    wire m_down  = cont1_key[1];
    wire m_left  = cont1_key[2];
    wire m_right = cont1_key[3];
    wire m_coin  = cont1_key[14];
    wire m_start = cont1_key[15];
    wire [7:0] pac_in0 = { 1'b1, 1'b1, ~m_coin,  1'b1, ~m_down, ~m_right, ~m_left, ~m_up };
    wire [7:0] pac_in1 = { 1'b1, 1'b1, ~m_start, 1'b1, 1'b1,    1'b1,     1'b1,    1'b1  };

    // Per-game variant: each game's instance JSON pushes its mod value to bridge
    // address VARIANT_ADDR via a memory_write (the standard Pocket mechanism, so
    // updater-assembled cores produce it). Latch in the bridge clock domain, then
    // 2-FF-sync into the core clock and decode to the core's mod_* selects
    // (MiSTer mod numbering: 0 = Pac-Man, 5 = Ms. Pac-Man, ...).
    // DIP defaults from the MRA (FF,FF,C9): dipsw1=C9, dipsw2=FF.
    localparam [31:0] VARIANT_ADDR = 32'h50000000;
    reg  [7:0] mod_bridge = 8'd0;
    always @(posedge clk_74a)
        if (bridge_wr && bridge_addr == VARIANT_ADDR) mod_bridge <= bridge_wr_data[7:0];
    reg  [7:0] mod_s1 = 8'd0, mod_reg = 8'd0;
    always @(posedge clk_sys) begin mod_s1 <= mod_bridge; mod_reg <= mod_s1; end

    wire mod_plus  = (mod_reg == 8'd1);
    wire mod_club  = (mod_reg == 8'd2);
    wire mod_bird  = (mod_reg == 8'd4);
    wire mod_ms    = (mod_reg == 8'd5);
    wire mod_mrtnt = (mod_reg == 8'd7);
    wire mod_woodp = (mod_reg == 8'd8);
    wire mod_eeek  = (mod_reg == 8'd9);
    wire mod_alib  = (mod_reg == 8'd10);
    wire mod_ponp  = (mod_reg == 8'd11);
    wire mod_van   = (mod_reg == 8'd12);
    wire mod_dshop = (mod_reg == 8'd14);
    wire mod_glob  = (mod_reg == 8'd15);
    wire mod_jmpst = (mod_reg == 8'd16);

    wire [9:0] pac_audio;
    pacman pacman_core (
        .O_VIDEO_R (core_r), .O_VIDEO_G (core_g), .O_VIDEO_B (core_b),
        .O_HSYNC (core_hsync), .O_VSYNC (core_vsync),
        .O_HBLANK (core_hblank), .O_VBLANK (core_vblank),
        .O_AUDIO (pac_audio),
        .in0 (pac_in0), .in1 (pac_in1),
        .dipsw1 (8'hC9), .dipsw2 (8'hFF),
        .mod_plus (mod_plus), .mod_jmpst (mod_jmpst), .mod_bird (mod_bird), .mod_mrtnt (mod_mrtnt),
        .mod_ms (mod_ms), .mod_woodp (mod_woodp), .mod_eeek (mod_eeek), .mod_glob (mod_glob),
        .mod_alib (mod_alib), .mod_ponp (mod_ponp | mod_van | mod_dshop),
        .mod_van (mod_van | mod_dshop), .mod_dshop (mod_dshop),
        .mod_club (mod_club),
        .flip_screen (1'b0), .h_offset (3'd0), .v_offset (3'd0),
        .dn_addr (ioctl_addr), .dn_data (ioctl_data), .dn_wr (ioctl_wr),
        .pause (1'b0),
        .hs_address (12'd0), .hs_data_in (8'd0), .hs_data_out (),
        .hs_write_enable (1'b0), .hs_access_read (1'b0), .hs_access_write (1'b0),
        .RESET (core_reset),
        .CLK (clk_sys),
        .ENA_6 (ce_6m), .ENA_4 (ce_4m), .ENA_1M79 (ce_1m79)
    );


    
endmodule
