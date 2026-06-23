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
    32'h2xxxxxxx: begin
        // high-score save image (read back by the Pocket on Quit/sleep)
        bridge_rd_data <= save_rd_data;
    end
    32'h4xxxxxxx: begin
        // savestate ("Memories") buffer -- read back by the Pocket on save flush.
        // Without this arm the save reads back all zeros (SS_ADDR=0x40000000,
        // ss_unloader ADDRESS_MASK_UPPER_4=0x4), so a load restores a blank machine.
        bridge_rd_data <= ss_rd_data;
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    // DIP readback -- interact OSD reads each value back per frame
    32'h50000004: begin bridge_rd_data <= {30'd0, dip_coin};  end
    32'h50000008: begin bridge_rd_data <= {30'd0, dip_life};  end
    32'h5000000C: begin bridge_rd_data <= {30'd0, dip_bonus}; end
    32'h50000010: begin bridge_rd_data <= {31'd0, dip_diff};  end
    32'h50000014: begin bridge_rd_data <= {29'd0, lp_k}; end
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

    // Symmetric 1px black border around the active region. Auto-detect the active
    // bounds from the blanking edges, then grow by BORDER. The latches capture
    // h_end as the first BLANK column (last_active+1) and v_start one line early,
    // so the right/top comparisons subtract 1 to keep the margin symmetric -- 1px
    // on every side. DE = active + 2*BORDER = 290x226, matching video.json
    // exactly (no geometry mismatch -> no edge stripe). RGB is the core picture,
    // black in the border ring.
    localparam [9:0] BORDER = 10'd1;

    reg  [9:0] hcnt = 0, vcnt = 0;
    reg        hs_d = 0, vs_d = 0, hb_d = 0, vb_d = 0;
    reg  [9:0] h_start = 0, h_end = 10'h3ff, v_start = 0, v_end = 10'h3ff;
    reg        in_window_d = 0;

    // Scaler slot select (video.json scaler_modes): 0 = ROT90 (vertical, the default
    // for Pac-Man et al.), 1 = ROT0 (landscape, Ponpoko -- the set's one horizontal
    // game), 2 = ROT270 (vertical-but-180-from-Pac-Man: birdiy, vanvan, dremshpr).
    // Slot 1 must declare clean exact-active dims (288x224, 4:3); feeding the scaler
    // our padded 290x226/9:7 in ROT0 tore the landscape image apart (stretched, black
    // gaps). The rotated slots tolerate the padding; ROT0 does not.
    // The APF "Set Scaler Slot" control word is emitted on video_rgb at the DE
    // falling edge (func code [2:0]=000, slot in the low bits of the [23:13]
    // parameter field); takes effect next frame.
    // Rotation strategy: the birdiy/van/dshop trio sits 180 deg from Pac-Man (they were
    // assigned ROT270 vs Pac-Man's ROT90). Rather than a second rotated scaler slot (the
    // ROT270 slot black-screened on device), render them on the known-good slot 0 (ROT90)
    // and apply the RTL 180 deg cocktail flip (flip_screen below): ROT90 . flip180 == ROT270.
    // Only Ponpoko is a true 90 deg case (landscape) that still needs its own ROT0 slot 1.
    wire [2:0] scaler_slot = mod_ponp ? 3'd1 : 3'd0;

    // Birdiy/Van-Van/Dream Shopper run the picture flipped; under flip the content
    // overruns its active window by 1px and leaks a colored stripe at the left edge
    // (the 1px border masks the un-flipped side only). Blank the outermost active
    // column on both H edges for these games so the leak is always covered -- border
    // and DE dimensions are unchanged, so no clip and no video.json change.
    wire flip_trio  = mod_bird | mod_van | mod_dshop;
    wire h_edge_col = (hcnt == h_start) | (hcnt + 10'd1 == h_end);

    // Ponpoko (ROT0 slot 1) declares exact-active 288x224; drop the 1px border for it so
    // the DE window equals that. The Pocket scaler blanks when the active DE window does
    // not match the selected slot's declared width x height (verified rule), which is why
    // slot 1's 288x224 vs the padded 290x226 DE showed black. Every other game keeps the
    // border (DE 290x226 = its slot's declared dims).
    wire [9:0] de_bdr = mod_ponp ? 10'd0 : BORDER;
    // The auto-detected V window sits one line low vs a symmetric border (0 top / 2 bottom
    // in source coords). Unflipped games never notice, but the trio runs the picture
    // 180-flipped, which moves that asymmetry to the TOP -> the top pixel line is clipped
    // (visible on Birdiy, whose content reaches the edge). Shift the trio's V window up one
    // line so the border is symmetric; height (226) is unchanged, so no scaler mismatch.
    wire [9:0] vsh = flip_trio ? 10'd1 : 10'd0;
    wire in_window = (hcnt + de_bdr >= h_start) && (hcnt + 10'd1 <= h_end + de_bdr) &&
                     (vcnt + de_bdr + vsh >= v_start + 10'd1) && (vcnt + vsh <= v_end + de_bdr);

    // Pac-Man color DAC: the PROM bits drive a resistor ladder (R/G via
    // 1000/470/220 ohm, B via 470/220 ohm), not a binary-weighted DAC. These
    // weights match MAME's compute_resistor_weights, so intermediate shades
    // hit the real board's analog levels instead of bit-replication's approx.
    function [7:0] dac_rg;
        input [2:0] c;
        case (c)
            3'd0: dac_rg = 8'd0;   3'd1: dac_rg = 8'd33;
            3'd2: dac_rg = 8'd71;  3'd3: dac_rg = 8'd104;
            3'd4: dac_rg = 8'd151; 3'd5: dac_rg = 8'd184;
            3'd6: dac_rg = 8'd222; 3'd7: dac_rg = 8'd255;
        endcase
    endfunction
    function [7:0] dac_b;
        input [1:0] c;
        case (c)
            2'd0: dac_b = 8'd0;   2'd1: dac_b = 8'd81;
            2'd2: dac_b = 8'd174; 2'd3: dac_b = 8'd255;
        endcase
    endfunction

always @(posedge clk_pix) begin
    hs_d <= core_hsync;  vs_d <= core_vsync;
    hb_d <= core_hblank; vb_d <= core_vblank;

    // pixel/line counters: hcnt resets each line on hsync, vcnt each frame on vsync
    if (core_hsync & ~hs_d) hcnt <= 10'd0;
    else                    hcnt <= hcnt + 10'd1;
    if (core_vsync & ~vs_d)      vcnt <= 10'd0;
    else if (core_hsync & ~hs_d) vcnt <= vcnt + 10'd1;

    // latch active-window bounds from the blanking edges (stable frame-to-frame)
    if (~core_hblank &  hb_d) h_start <= hcnt;
    if ( core_hblank & ~hb_d) h_end   <= hcnt;
    if (~core_vblank &  vb_d) v_start <= vcnt;
    if ( core_vblank & ~vb_d) v_end   <= vcnt;

    // DE across the grown window; RGB black wherever the core is blanking, so the
    // border ring is always black. On the first blanking pixel after DE falls, emit
    // the APF "Set Scaler Slot" control word to pick the rotation slot.
    in_window_d <= in_window;
    vidout_skip <= 1'b0;
    vidout_hs   <= core_hsync;
    vidout_vs   <= core_vsync;
    vidout_de   <= in_window;
    if (in_window)
        vidout_rgb <= (core_hblank | core_vblank | (flip_trio & h_edge_col)) ? 24'h0 :
                      { dac_rg(core_r), dac_rg(core_g), dac_b(core_b) };
    else if (in_window_d)            // DE falling edge -> scaler slot select
        vidout_rgb <= { 8'd0, scaler_slot, 13'd0 };  // [2:0]=000 Set Scaler Slot
    else
        vidout_rgb <= 24'h0;         // safe blanking default = slot 0
end




//
//
// audio: Namco WSG output -> I2S via sound_i2s (analogue-pocket-utils).
// O_AUDIO is the WSG's unsigned 10-bit sum (0 = silence); feed both channels.
// (The template's silence generator below is now unused and optimised away.)
//
    // The WSG time-multiplexes its 3 voices onto O_AUDIO (one vol*wavetable
    // product per slot); the real board sums them in its analog mixer. Integrate
    // O_AUDIO over each 48 kHz frame (512 clk_sys = exactly 2 multiplex windows =
    // 2 samples per voice) to recover that sum and anti-alias before sound_i2s
    // point-samples it. sum/512 -> bits [18:9].
    // Audio output: selectable low-pass. The "Low-Pass Filter" menu value IS the IIR
    // shift K (0 = bypass = raw 1.0.0 path); each cutoff is OSD-selectable. corner ~=
    // 48k/(2*pi*2^K): K1~5k K2~2.5k K3~1.2k K4~600 K5~300 Hz (bigger K -> more muffled).
    // Rounded leaky IIR in 10.12 fixed-point; lp_k is static OSD config (clk_74a),
    // used directly like the DIPs.
    reg  [8:0]         aud_div = 9'd0;
    reg  [19:0]        aud_acc = 20'd0;
    reg  [9:0]         aud_raw = 10'd0;          // raw box-average (K=0 bypass)
    reg  signed [23:0] aud_lpf = 24'sd0;         // low-pass state (10.12)
    wire signed [23:0] lp_rnd = (lp_k == 3'd0) ? 24'sd0 : (24'sd1 <<< (lp_k - 3'd1));
    wire [9:0] pac_audio_s = (lp_k != 3'd0) ? aud_lpf[21:12] : aud_raw;     // low-pass (K=0 bypass)
    always @(posedge clk_sys) begin
        aud_div <= aud_div + 9'd1;
        if (aud_div == 9'd511) begin
            aud_raw <= aud_acc[18:9];
            aud_lpf <= aud_lpf + ((($signed({2'b0, aud_acc[18:9], 12'd0}) - aud_lpf) + lp_rnd) >>> lp_k);
            aud_acc <= pac_audio;                // seed next 48 kHz frame
        end else begin
            aud_acc <= aud_acc + pac_audio;
        end
    end

    sound_i2s #(
        .CHANNEL_WIDTH (10),
        .SIGNED_INPUT  (0)
    ) aud (
        .clk_74a    (clk_74a),
        .clk_audio  (clk_sys),
        .audio_l    (pac_audio_s),
        .audio_r    (pac_audio_s),
        .audio_mclk (audio_mclk),
        .audio_lrck (audio_lrck),
        .audio_dac  (audio_dac)
    );

// (sound_i2s above generates audio_mclk/lrck/dac itself; the template's separate
//  audgen_* I2S clock generator was unused and has been removed.)

///////////////////////////////////////////////


    wire    clk_sys;       // 24.576 MHz core carrier (ENA_6 = /4 = 6.144 MHz)
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

    // Clock enables in the clk_sys (24.576 MHz) domain, matching the MiSTer
    // reference dividers. ENA_6 = 6.144 MHz (pixel + CPU beat); ENA_4/ENA_1M79
    // feed only variant sound chips, unused for Ms. Pac-Man.
    reg [1:0] div6   = 0;  reg ce_6m   = 0;
    reg [2:0] div4   = 0;  reg ce_4m   = 0;
    reg [3:0] div179 = 0;  reg ce_1m79 = 0;
    always @(posedge clk_sys) begin
        div6   <= div6 + 2'd1;                              ce_6m   <= (div6   == 2'd0);
        div4   <= (div4   == 3'd5)  ? 3'd0 : div4   + 3'd1; ce_4m   <= (div4   == 3'd0);
        div179 <= (div179 == 4'd12) ? 4'd0 : div179 + 4'd1; ce_1m79 <= (div179 == 4'd0);
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

    // High-score save. APF save slot on bridge window 0x2: save_loader fills the
    // 256-byte shadow from <rom>.sav, the save_unloader streams it back to SD on
    // Quit/sleep. The hiscore controller restores it into work RAM after boot and
    // periodically snapshots the per-variant high-score regions.
    wire        hs_sv_wr;
    wire [7:0]  hs_sv_wr_addr, hs_sv_rd_addr;
    wire [7:0]  hs_sv_wr_data, hs_sv_rd_data;
    wire [31:0] save_rd_data;
    wire [11:0] hs_addr;
    wire [7:0]  hs_din, hs_dout;
    wire        hs_wen, hs_rd, hs_wr_acc, hs_pause;
    // hiscore drives its own copy of the work-RAM tap; the savestate FSM (below)
    // muxes onto the same physical tap into PACMAN when a save/load is in progress.
    wire [11:0] hsi_addr;
    wire [7:0]  hsi_din;
    wire        hsi_wen, hsi_rd, hsi_wr_acc, hsi_pause;

    // Pause the core while the Pocket menu / sleep overlay is up. osnotify_inmenu
    // is in the clk_74a bridge domain; 2-FF sync into clk_sys and OR it into the
    // core pause so the game freezes instead of advancing unseen behind the menu
    // (and is quiescent for the high-score flush on sleep).
    reg [1:0] inmenu_sync = 2'd0;
    always @(posedge clk_sys) inmenu_sync <= {inmenu_sync[0], osnotify_inmenu};
    wire menu_pause = inmenu_sync[1];
    wire core_pause = hs_pause | menu_pause;

    data_loader #(.ADDRESS_MASK_UPPER_4 (4'h2), .ADDRESS_SIZE (8), .OUTPUT_WORD_SIZE (1)) save_loader (
        .clk_74a (clk_74a), .clk_memory (clk_sys),
        .bridge_wr (bridge_wr), .bridge_endian_little (bridge_endian_little),
        .bridge_addr (bridge_addr), .bridge_wr_data (bridge_wr_data),
        .write_en (hs_sv_wr), .write_addr (hs_sv_wr_addr), .write_data (hs_sv_wr_data)
    );
    data_unloader #(.ADDRESS_MASK_UPPER_4 (4'h2), .ADDRESS_SIZE (8), .READ_MEM_CLOCK_DELAY (4), .INPUT_WORD_SIZE (1)) save_unloader (
        .clk_74a (clk_74a), .clk_memory (clk_sys),
        .bridge_rd (bridge_rd), .bridge_endian_little (bridge_endian_little),
        .bridge_addr (bridge_addr), .bridge_rd_data (save_rd_data),
        .read_en (), .read_addr (hs_sv_rd_addr), .read_data (hs_sv_rd_data)
    );
    hiscore hi (
        .clk (clk_sys), .ce (ce_6m), .reset (core_reset), .loaded (dl_complete_s),
        .mod_sel (mod_reg[4:0]), .ss_busy (ss_active), .vbl (core_vblank),
        .hs_address (hsi_addr), .hs_data_in (hsi_din), .hs_data_out (hs_dout),
        .hs_write_enable (hsi_wen), .hs_access_read (hsi_rd), .hs_access_write (hsi_wr_acc),
        .pause (hsi_pause),
        .sv_wr (hs_sv_wr), .sv_wr_addr (hs_sv_wr_addr), .sv_wr_data (hs_sv_wr_data),
        .sv_rd_addr (hs_sv_rd_addr), .sv_rd_data (hs_sv_rd_data)
    );

    // ===================================================================
    // Save states ("Memories") -- full machine-state snapshot/restore
    // -------------------------------------------------------------------
    // The blob captures everything that defines the running machine, walked by one
    // unified counter (3 cycles/byte) through three taps into a bridge buffer at
    // SS_ADDR: 4 KB main work RAM (hiscore tap), the 32-byte T80 register set
    // (ss_cpu_* bus), and pacman's own timing/IRQ/control latches (ss_st_* bus).
    // The whole walk runs under park (ss_cpu_load) + pause (ss_pause_o) + freeze
    // (ss_freeze) so the snapshot is internally coherent and the restore is not
    // stomped by free-running flops. Base + Ms. Pac-Man resume bit-exact; the audio
    // PSG dpram (vol/frq) and sprite_xy_ram self-heal within one frame from captured
    // RAM, and the variant SN76489/YM2149 chips are not yet captured. See SAVESTATES.md.
    // ===================================================================
    localparam        SS_SUPPORTED = 1'b1;
    localparam [31:0] SS_ADDR      = 32'h40000000;  // bridge window 0x4
    localparam [12:0] SS_RAM       = 13'd4096;      // 4KB main work RAM (buffer 0..4095)
    localparam [12:0] SS_CPU       = 13'd4128;      // + 32 T80 CPU bytes (buffer 4096..4127)
    localparam [12:0] SS_BYTES     = 13'd4140;      // + 12 pacman machine-state bytes (4128..4139)

    assign savestate_supported   = SS_SUPPORTED;
    assign savestate_addr        = SS_ADDR;
    assign savestate_size        = {19'd0, SS_BYTES};
    assign savestate_maxloadsize = {19'd0, SS_BYTES};

    // Bridge <-> savestate buffer. data_loader writes it on load; data_unloader
    // reads it on save (mutually exclusive, so one bridge port suffices).
    wire        ssb_ld_we;
    wire [12:0] ssb_ld_addr;
    wire [7:0]  ssb_ld_data;
    wire [12:0] ssb_ul_addr;
    wire [7:0]  ssb_ul_data;
    wire [31:0] ss_rd_data;
    data_loader #(.ADDRESS_MASK_UPPER_4 (4'h4), .ADDRESS_SIZE (13), .OUTPUT_WORD_SIZE (1)) ss_loader (
        .clk_74a (clk_74a), .clk_memory (clk_sys),
        .bridge_wr (bridge_wr), .bridge_endian_little (bridge_endian_little),
        .bridge_addr (bridge_addr), .bridge_wr_data (bridge_wr_data),
        .write_en (ssb_ld_we), .write_addr (ssb_ld_addr), .write_data (ssb_ld_data)
    );
    data_unloader #(.ADDRESS_MASK_UPPER_4 (4'h4), .ADDRESS_SIZE (13), .READ_MEM_CLOCK_DELAY (4), .INPUT_WORD_SIZE (1)) ss_unloader (
        .clk_74a (clk_74a), .clk_memory (clk_sys),
        .bridge_rd (bridge_rd), .bridge_endian_little (bridge_endian_little),
        .bridge_addr (bridge_addr), .bridge_rd_data (ss_rd_data),
        .read_en (), .read_addr (ssb_ul_addr), .read_data (ssb_ul_data)
    );

    // True dual-port state buffer in M10K. A hand-rolled array with two write ports
    // infers as registers here (blew ALMs to 157%), so use the project's
    // altsyncram-backed dpram. Port A = serialise FSM, port B = bridge; port B reads
    // (unloader, save) and writes (loader, load) never overlap, so its address muxes
    // on the loader write-enable. 1-cycle registered read latency on both ports.
    reg  [12:0] ssa_addr;
    reg  [7:0]  ssa_wdata;
    reg         ssa_we;
    wire [7:0]  ssa_q, ssb_q;
    dpram #(.addr_width_g(13), .data_width_g(8)) ss_buf (
        .clock_a (clk_sys), .address_a (ssa_addr), .data_a (ssa_wdata),
        .wren_a  (ssa_we),  .enable_a (1'b1), .q_a (ssa_q),
        .clock_b (clk_sys), .address_b (ssb_ld_we ? ssb_ld_addr : ssb_ul_addr),
        .data_b  (ssb_ld_data), .wren_b (ssb_ld_we), .enable_b (1'b1), .q_b (ssb_q)
    );
    assign ssb_ul_data = ssb_q;

    // start/load pulses cross from the clk_74a bridge into clk_sys.
    reg [2:0] ss_start_sr = 3'd0, ss_load_sr = 3'd0;
    always @(posedge clk_sys) begin
        ss_start_sr <= {ss_start_sr[1:0], savestate_start};
        ss_load_sr  <= {ss_load_sr[1:0],  savestate_load};
    end
    wire ss_start_rise = (ss_start_sr[2:1] == 2'b01);
    wire ss_load_rise  = (ss_load_sr[2:1]  == 2'b01);

    // ss_cpu_bndry is already in clk_sys (the T80 runs on clk_sys via pacman.vhd
    // CLK=>clk), so the FSM gates on it DIRECTLY -- no synchronizer. A 2FF sync here
    // would only add lag, letting the CPU run past the boundary before the park
    // engages. Register it once just to break the long pacman->T80 comb path into
    // the FSM (1-cycle align with the FSM's own registered state); the park
    // re-asserts M1/T1 every CEN edge anyway, so a 1-cycle align is exact.
    reg ss_bndry_q = 1'b0;
    always @(posedge clk_sys) ss_bndry_q <= ss_cpu_bndry;

    // 3 cycles per byte: present address/index, wait one cycle for the registered
    // read, then capture (save) or write back (load). One unified counter walks the
    // 4140-byte blob: bytes 0..4095 = work RAM (via the hiscore tap), 4096..4127 =
    // T80 CPU registers (ss_cpu_* bus), 4128..4139 = pacman machine state (ss_st_* bus:
    // hcnt/vcnt/control_reg/cpu_vec_reg/sync_bus/watchdog/protection + IRQ/flags).
    localparam SS_IDLE=4'd0, SS_SV0=4'd1, SS_SV1=4'd2, SS_SV2=4'd3,
               SS_LD0=4'd4, SS_LD1=4'd5, SS_LD2=4'd6, SS_FIN=4'd7,
               SS_ARM=4'd8;
    // SS_ARM bounded fallback: if the natural M1/T1 boundary never arrives (SAVE path
    // only -- LOAD no longer arms), force the park after ~one frame so the host
    // handshake (busy/ok) can never wedge forever. clk_sys ~24.576MHz, a frame is
    // ~410k cycles; 2^21-1 (~85ms, ~5 frames) is well past one frame yet bounded.
    localparam        SS_ARM_CW  = 21;              // counter width
    localparam [20:0] SS_ARM_TMO = 21'h1FFFFF;      // 2^21-1 clk_sys cycles
    reg  [SS_ARM_CW-1:0] ss_arm_cnt = {SS_ARM_CW{1'b0}};
    reg  [3:0]  ss_st = SS_IDLE;
    reg  [12:0] ss_cnt;
    reg         ss_busy_cs = 1'b0;
    reg         ss_save_ok_cs = 1'b0, ss_load_ok_cs = 1'b0;
    reg         ss_op_load = 1'b0;                  // current op: 0=save, 1=load
    reg         ss_pause_o, ss_rd_o, ss_wr_o, ss_wen_o;
    reg  [11:0] ss_addr_o;
    reg  [7:0]  ss_din_o;
    reg  [4:0]  ss_cpu_idx_r;
    reg  [7:0]  ss_cpu_din_r;
    reg         ss_cpu_wr_r;
    reg  [4:0]  ss_st_idx_r;                         // pacman machine-state bus
    reg  [7:0]  ss_st_din_r;
    reg         ss_st_wr_r;
    wire        ss_active = (ss_st != SS_IDLE);
    wire        ss_walking = (ss_st != SS_IDLE) && (ss_st != SS_ARM);
    // Strict-priority half-open phases so exactly one tap drives the buffer per byte:
    //   RAM   0..4095   (cnt < SS_RAM)         hiscore tap
    //   CPU   4096..4127 (SS_RAM..<SS_CPU)     ss_cpu_* bus
    //   STATE 4128..4139 (cnt >= SS_CPU)       ss_st_* bus (pacman timing/IRQ/control)
    wire        ss_cpu_ph = (ss_cnt >= SS_RAM) && (ss_cnt < SS_CPU);
    wire        ss_st_ph  = (ss_cnt >= SS_CPU);
    always @(posedge clk_sys) begin
        ss_rd_o <= 1'b0; ss_wr_o <= 1'b0; ss_wen_o <= 1'b0; ssa_we <= 1'b0; ss_cpu_wr_r <= 1'b0; ss_st_wr_r <= 1'b0;
        case (ss_st)
        SS_IDLE: begin
            ss_pause_o <= 1'b0;
            ss_arm_cnt <= {SS_ARM_CW{1'b0}};
            // SAVE arms in SS_ARM and waits for the CPU to reach an M1/T1 boundary
            // before walking any byte. Crucially DO NOT assert ss_pause_o during the
            // arm wait: the CPU must keep running so it finishes its current
            // instruction (incl. any in-flight store write) and reaches a real fetch
            // boundary. Clearing the per-op ok here (not on the next op's rise)
            // guarantees the host samples ack=0 for a fresh request.
            //
            // LOAD does NOT arm: it goes straight to the walk (SS_LD0) and forces the
            // park immediately. A load OVERWRITES the entire CPU register set, so there
            // is no in-flight instruction to protect and no live fetch boundary worth
            // waiting for -- the park (T80.vhd:1177, CEN-independent) forces
            // MCycle/TState=M1/T1 itself the instant we leave SS_IDLE. (reset_n is
            // power-on-only, apf_top.v:217-232: the Pocket does NOT hold the core in
            // reset during a Memory load, so the core is freely running -- ss_pause_o
            // AND ss_freeze, asserted from the first load cycle, are what freeze the CPU
            // and the timing/IRQ flops, not reset. Arming LOAD would just wait one frame
            // for the SS_ARM timeout for no benefit, so skip it.)
            if (ss_start_rise) begin
                ss_st <= SS_ARM; ss_cnt <= 13'd0; ss_op_load <= 1'b0;
                ss_busy_cs <= 1'b1; ss_save_ok_cs <= 1'b0;
            end else if (ss_load_rise) begin
                ss_st <= SS_LD0; ss_cnt <= 13'd0; ss_op_load <= 1'b1;
                ss_busy_cs <= 1'b1; ss_load_ok_cs <= 1'b0; ss_pause_o <= 1'b1;
            end
        end
        // SAVE only: wait for the CPU to reach an M1/T1 fetch boundary NATURALLY.
        // ss_cpu_load is NOT asserted here (ss_walking false in SS_ARM) and ss_pause_o
        // is LOW, so the T80 runs free to the end of its current instruction -- any
        // in-flight memory cycle (e.g. a store's write) COMPLETES instead of being
        // truncated by a forced park. The moment ss_cpu_bndry='1' we enter the walk,
        // which raises ss_cpu_load (park: forces+holds MCycle/TState=M1/T1,
        // T80.vhd:1177) AND ss_pause_o. The park pins the CPU at exactly the boundary
        // it naturally reached -- so the captured PC/regs are coherent with the
        // captured RAM. A bounded fallback (ss_arm_cnt) forces the park anyway if the
        // boundary never arrives within ~one frame, so the host handshake can never
        // wedge forever (busy stuck high) regardless of CPU clocking state.
        SS_ARM: begin
            ss_arm_cnt <= ss_arm_cnt + {{(SS_ARM_CW-1){1'b0}}, 1'b1};
            if (ss_bndry_q || (ss_arm_cnt == SS_ARM_TMO)) begin
                ss_pause_o <= 1'b1;
                ss_st <= ss_op_load ? SS_LD0 : SS_SV0;
            end
        end
        // SAVE: present source addr/index -> wait -> capture into buffer[cnt]
        SS_SV0: begin
            if (ss_st_ph)       ss_st_idx_r  <= ss_cnt[4:0];                  // STATE phase
            else if (ss_cpu_ph) ss_cpu_idx_r <= ss_cnt[4:0];                  // CPU phase
            else begin ss_addr_o <= ss_cnt[11:0]; ss_rd_o <= 1'b1; end        // RAM phase
            ss_st <= SS_SV1;
        end
        SS_SV1: begin ss_st <= SS_SV2; end               // read latency (addr/index held)
        SS_SV2: begin
            ssa_addr  <= ss_cnt;
            ssa_wdata <= ss_st_ph ? ss_st_dout : (ss_cpu_ph ? ss_cpu_dout : hs_dout);
            ssa_we    <= 1'b1;
            if (ss_cnt == SS_BYTES - 1) ss_st <= SS_FIN;
            else begin ss_cnt <= ss_cnt + 13'd1; ss_st <= SS_SV0; end
        end
        // LOAD: read buffer[cnt] -> write the dest (RAM tap or CPU bus)
        SS_LD0: begin ssa_addr <= ss_cnt; ss_st <= SS_LD1; end
        SS_LD1: begin ss_st <= SS_LD2; end               // dpram read latency
        SS_LD2: begin
            if (ss_st_ph) begin                                              // STATE phase
                ss_st_idx_r <= ss_cnt[4:0]; ss_st_din_r <= ssa_q; ss_st_wr_r <= 1'b1;
            end else if (ss_cpu_ph) begin                                    // CPU phase
                ss_cpu_idx_r <= ss_cnt[4:0]; ss_cpu_din_r <= ssa_q; ss_cpu_wr_r <= 1'b1;
            end else begin                                                   // RAM phase
                ss_addr_o <= ss_cnt[11:0]; ss_din_o <= ssa_q; ss_wen_o <= 1'b1; ss_wr_o <= 1'b1;
            end
            if (ss_cnt == SS_BYTES - 1) ss_st <= SS_FIN;
            else begin ss_cnt <= ss_cnt + 13'd1; ss_st <= SS_LD0; end
        end
        SS_FIN: begin
            ss_busy_cs <= 1'b0; ss_pause_o <= 1'b0;
            if (ss_op_load) ss_load_ok_cs <= 1'b1;
            else            ss_save_ok_cs <= 1'b1;
            ss_st <= SS_IDLE;
        end
        endcase
    end

    // CPU savestate bus into pacman/T80. ss_cpu_load is held for the entire WALK
    // (ss_walking = active && not SS_ARM), parking the T80 at M1/T1 continuously.
    // SAVE: SS_ARM first lets the CPU run free to the boundary it naturally reaches
    // (ss_cpu_load NOT asserted in SS_ARM, ss_pause_o LOW) so no in-flight bus cycle
    // is truncated; the walk then asserts ss_cpu_load and the T80 park (T80.vhd:1177,
    // re-forced every CEN edge) pins it at that exact boundary while RAM/regs are
    // read -> captured PC/regs coherent with captured RAM.
    // LOAD: skips SS_ARM (see SS_IDLE) and asserts ss_cpu_load immediately. A load
    // overwrites the whole register set, so there is no in-flight instruction to
    // protect -- the park (T80.vhd:1177, CEN-independent) forces MCycle/TState=M1/T1
    // itself and the restore proceeds. The CPU freeze is ss_cpu_load (park) + ss_pause_o
    // (pause). The pacman timing/IRQ/control flops (hcnt/vcnt/control_reg/cpu_int_l/
    // watchdog/sync_bus, NOT pause-gated) are frozen separately by ss_freeze (=ss_walking)
    // -- WITHOUT that freeze a restored value is stomped by the very next ena_6 edge, so
    // the load cold-booted the game. (reset_n is power-on-only, apf_top.v:217-232: the
    // host does NOT reset the core during a Memory load; the earlier "held in reset"
    // reasoning here was wrong -- ss_pause_o + ss_freeze are the freeze, not reset.)
    assign ss_cpu_idx  = ss_cpu_idx_r;
    assign ss_cpu_din  = ss_cpu_din_r;
    assign ss_cpu_wr   = ss_cpu_wr_r;
    assign ss_cpu_load = ss_walking;

    // pacman machine-state bus (timing/IRQ/control latches). ss_freeze is held for
    // the WHOLE walk (=ss_walking) so the free-running hcnt/vcnt/cpu_int_l/watchdog/
    // sync_bus flops hold: a SAVE snapshots them coherent with the M1/T1-parked CPU,
    // and a LOAD's restore strobes are not stomped by the next ena_6 edge. Released
    // with the park at SS_FIN so the first post-restore cycle sees the saved timing.
    assign ss_st_idx = ss_st_idx_r;
    assign ss_st_din = ss_st_din_r;
    assign ss_st_wr  = ss_st_wr_r;
    assign ss_freeze = ss_walking;

    // tap mux: savestate FSM owns the tap while active, else hiscore does.
    assign hs_addr   = ss_active ? ss_addr_o : hsi_addr;
    assign hs_din    = ss_active ? ss_din_o  : hsi_din;
    assign hs_wen    = ss_active ? ss_wen_o  : hsi_wen;
    assign hs_rd     = ss_active ? ss_rd_o   : hsi_rd;
    assign hs_wr_acc = ss_active ? ss_wr_o   : hsi_wr_acc;
    assign hs_pause  = hsi_pause | ss_pause_o;

    // status back to the clk_74a bridge (slow levels). busy is shared (one op at a
    // time) but ok is PER-OP: a SAVE only ever lights savestate_start_ok and a LOAD
    // only savestate_load_ok. Sharing one ok across both let a finished SAVE leave
    // savestate_load_ok asserted, so the host saw the next LOAD as already-acked and
    // short-circuited it ("load does nothing"). Each ok is cleared at its own op's
    // start (SS_IDLE rise), so a fresh request reads ack=0 -> busy=1 -> ok=1.
    reg [2:0] ss_busy_74 = 3'd0, ss_save_ok_74 = 3'd0, ss_load_ok_74 = 3'd0;
    always @(posedge clk_74a) begin
        ss_busy_74    <= {ss_busy_74[1:0],    ss_busy_cs};
        ss_save_ok_74 <= {ss_save_ok_74[1:0], ss_save_ok_cs};
        ss_load_ok_74 <= {ss_load_ok_74[1:0], ss_load_ok_cs};
    end
    assign savestate_start_ack  = ss_busy_74[2] | ss_save_ok_74[2];
    assign savestate_start_busy = ss_busy_74[2];
    assign savestate_start_ok   = ss_save_ok_74[2];
    assign savestate_start_err  = 1'b0;
    assign savestate_load_ack   = ss_busy_74[2] | ss_load_ok_74[2];
    assign savestate_load_busy  = ss_busy_74[2];
    assign savestate_load_ok    = ss_load_ok_74[2];
    assign savestate_load_err   = 1'b0;

    // Continuously report the save slot's size so the Pocket flushes the FULL
    // high-score NVRAM: 256 bytes, matching data.json size_maximum and the 256-byte
    // shadow (incl. the validity marker at byte 255). data_slots index 2 (Game, ROM,
    // Save) -> size word at 2*2+1 = 5. (Was 32'd4 for the old Pac-Man-only format,
    // which truncated the marker + score regions so the .sav never restored.)
    reg [31:0] dt_data = 32'd256;
    reg [9:0]  dt_addr = 10'd5;
    reg        dt_wren = 1'b0;
    always @(posedge clk_74a) begin
        dt_addr <= 10'd5;
        dt_data <= 32'd256;
        dt_wren <= 1'b1;
    end
    assign datatable_addr = dt_addr;
    assign datatable_data = dt_data;
    assign datatable_wren = dt_wren;

    // Controllers -> Pac-Man IN0/IN1. cont1 = player 1; cont2 = player 2.
    // Base Pac-Man is active-low (board doc: controls pull high, switch to ground);
    // Ponpoko's board is the exception (active-high) -- handled in the per-mod mux.
    // Variant action buttons sit on different IN bits per game; the actual pac_in0/
    // pac_in1 are built below, after the mod decode, so they can branch on mod.
    wire m_up    = cont1_key[0]  | cont2_key[0];
    wire m_down  = cont1_key[1]  | cont2_key[1];
    wire m_left  = cont1_key[2]  | cont2_key[2];
    wire m_right = cont1_key[3]  | cont2_key[3];
    wire m_coin  = cont1_key[14] | cont2_key[14];     // either pad inserts a coin
    wire m_start   = cont1_key[15];                   // 1P start
    wire m_start_2 = cont2_key[15];                   // 2P start
    // Single-button variants: any face/shoulder button (A/B/X/Y/L/R) is the action.
    wire m_btn   = |cont1_key[9:4];                   // P1 action
    wire m_btn_2 = |cont2_key[9:4];                   // P2 action

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

    // DIP switches, set from the Analogue menu via interact.json (each writes a
    // 0..3 field value to its bridge address). dipsw1 assembled to the MRA byte;
    // defaults reproduce 0xC9 (1C/1C, 3 lives, bonus@10000, normal). dip_cabinet
    // drives IN1[7] (1=upright, 0=cocktail -> reads player-2 controls).
    reg [1:0] dip_coin  = 2'd1;   // 0x50000004  0=Free 1=1C/1C 2=1C/2C 3=2C/1C
    reg [1:0] dip_life  = 2'd2;   // 0x50000008  0=1 1=2 2=3 3=5
    reg [1:0] dip_bonus = 2'd0;   // 0x5000000C  0=10000 1=15000 2=20000 3=None
    reg       dip_diff  = 1'b1;   // 0x50000010  0=Hard 1=Normal
    reg [2:0] lp_k = 3'd1;        // 0x50000014  low-pass shift K (0=Off, default K1 5kHz)
    always @(posedge clk_74a) if (bridge_wr) case (bridge_addr)
        32'h50000004: dip_coin  <= bridge_wr_data[1:0];
        32'h50000008: dip_life  <= bridge_wr_data[1:0];
        32'h5000000C: dip_bonus <= bridge_wr_data[1:0];
        32'h50000010: dip_diff  <= bridge_wr_data[0];
        32'h50000014: lp_k <= bridge_wr_data[2:0];
    endcase

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

    // Per-mod IN0/IN1. Default = base Pac-Man (active-low, no action button).
    // Variant action-button bits and Ponpoko's active-high polarity come from
    // each game's MAME-reverse-engineered board map (no variant schematics exist):
    //   alibaba  IN0 b6 = hammer        van/dshop IN0 b4 = action
    //   eeekk    IN0 b7 = P2, IN1 b6 = P1   birdiy IN1 b4 = P1, b7 = P2
    //   jumpshot IN1 b5 = P1, b6 = P2 shoot (no start; coin-start)
    //   ponpoko  whole port active-high; IN0 b4 = button; coins stay active-low
    //   club     P1 from cont1, P2 from cont2 (its input mux reads each separately)
    reg [7:0] pac_in0, pac_in1;
    always @(*) begin
        pac_in0 = { 1'b1, 1'b1, ~m_coin, 1'b1, ~m_down, ~m_right, ~m_left, ~m_up };
        pac_in1 = { 1'b1, ~m_start_2, ~m_start, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1 };
        case (1'b1)
            mod_alib:  pac_in0[6] = ~m_btn;
            mod_van:   pac_in0[4] = ~m_btn;
            mod_dshop: pac_in0[4] = ~m_btn;
            mod_eeek:  begin pac_in0[7] = ~m_btn_2; pac_in1[6] = ~m_btn; end
            mod_bird:  begin pac_in1[4] = ~m_btn;   pac_in1[7] = ~m_btn_2; end
            mod_jmpst: begin pac_in1[5] = ~m_btn;   pac_in1[6] = ~m_btn_2; end
            mod_ponp:  begin
                pac_in0 = { 1'b1, 1'b1, ~m_coin, m_btn, m_down, m_right, m_left, m_up };
                pac_in1 = { 1'b0, m_start_2, m_start, m_btn_2, 1'b0, 1'b0, 1'b0, 1'b0 };
            end
            mod_club:  begin
                pac_in0[3:0] = ~{ cont1_key[1], cont1_key[3], cont1_key[2], cont1_key[0] };
                pac_in1[3:0] = ~{ cont2_key[1], cont2_key[3], cont2_key[2], cont2_key[0] };
            end
            default: ;
        endcase
    end

    // Per-mod DIPs. The OSD menu (interact.json) stays Pac-Man-labeled, but the core
    // places each generic field (coin/life/bonus/diff) on the loaded game's real DSW
    // bits so the toggles DO the right thing. Board-RE from MAME (no variant
    // schematics). Cabinet/service bits are pinned to upright/inactive so a toggle
    // can't flip a game into cocktail/test (dead controls); the dangerous DSW2s
    // (vanvan = no sprite collision, dremshpr = invuln infinite-loop) are forced 0.
    // Value translations for games whose fields are reordered / on different bits:
    wire [1:0] club_coin  = (dip_coin == 2'd0) ? 2'd1 : dip_coin;          // Free invalid -> 1C1C
    wire [1:0] mrtnt_coin = (dip_coin == 2'd1) ? 2'd3 :
                            (dip_coin == 2'd3) ? 2'd1 : dip_coin;          // 1C1C<->2C1C swapped
    wire [1:0] ponp_bonus = dip_bonus + 2'd1;                              // 10k/30k/50k/None
    wire [3:0] ponp_coin  = (dip_coin == 2'd0) ? 4'h0 : (dip_coin == 2'd1) ? 4'h1 :
                            (dip_coin == 2'd2) ? 4'h3 : 4'h2;              // ponpoko DSW2[3:0]
    wire [1:0] van_coin   = (dip_coin == 2'd0) ? 2'b00 : (dip_coin == 2'd1) ? 2'b11 :
                            (dip_coin == 2'd2) ? 2'b10 : 2'b01;            // 2C1C/1C1C/1C2C/1C3C
    wire [1:0] van_bonus  = (dip_bonus == 2'd0) ? 2'b10 : (dip_bonus == 2'd1) ? 2'b01 :
                            (dip_bonus == 2'd2) ? 2'b00 : 2'b11;

    reg [7:0] pac_dipsw1, pac_dipsw2;
    always @(*) begin
        pac_dipsw2 = 8'hFF;                                                // harmless for active-low games
        pac_dipsw1 = { 1'b1, dip_diff, dip_bonus, dip_life, dip_coin };    // base / pacplus / alibaba
        case (1'b1)
            mod_club:  pac_dipsw1 = { 2'b00, dip_bonus, 1'b1, (dip_life == 2'd3), club_coin };
            mod_bird:  pac_dipsw1 = { 1'b1, 1'b1, 1'b1, 1'b0, dip_life, dip_coin };
            mod_mrtnt: pac_dipsw1 = { 1'b1, 1'b1, ~dip_bonus, ~dip_life, mrtnt_coin };
            mod_woodp: pac_dipsw1 = { 1'b1, 1'b1, dip_bonus, dip_life, dip_coin };
            mod_eeek:  pac_dipsw1 = { 2'b11, 1'b0, dip_diff, 2'b00, ~dip_life };
            mod_ponp:  begin
                pac_dipsw1 = { 1'b1, 1'b1, dip_life, 2'b00, ponp_bonus };
                pac_dipsw2 = { 1'b1, 1'b0, 2'b11, ponp_coin };
            end
            mod_van:   begin
                pac_dipsw1 = { van_coin, ~dip_life, van_bonus, 1'b1, 1'b0 };
                pac_dipsw2 = 8'h00;
            end
            mod_dshop: begin
                pac_dipsw1 = { van_coin, ~dip_life, van_bonus, 1'b1, 1'b1 };
                pac_dipsw2 = 8'h00;
            end
            mod_jmpst: pac_dipsw1 = 8'hDD;                                 // no coin/life/bonus/diff dips
            default: ;
        endcase
    end

    wire [9:0] pac_audio;
    // Savestate buses into pacman, all driven by the FSM above.
    // CPU bus: read-out (idx/dout/bndry) + restore (din/wr/load) of the T80 registers.
    wire [4:0] ss_cpu_idx;
    wire [7:0] ss_cpu_dout;
    wire       ss_cpu_bndry;
    wire [7:0] ss_cpu_din;
    wire       ss_cpu_wr;
    wire       ss_cpu_load;
    // Machine-state bus: pacman's own timing/IRQ/control latches (hcnt/vcnt/control_reg/
    // cpu_vec_reg/cpu_int_l/watchdog/sync_bus/protection counters) + ss_freeze, which
    // holds those free-running flops for the whole walk so save/restore is coherent.
    wire [4:0] ss_st_idx;
    wire [7:0] ss_st_dout;
    wire [7:0] ss_st_din;
    wire       ss_st_wr;
    wire       ss_freeze;

    pacman pacman_core (
        .O_VIDEO_R (core_r), .O_VIDEO_G (core_g), .O_VIDEO_B (core_b),
        .O_HSYNC (core_hsync), .O_VSYNC (core_vsync),
        .O_HBLANK (core_hblank), .O_VBLANK (core_vblank),
        .O_AUDIO (pac_audio),
        .in0 (pac_in0), .in1 (pac_in1),
        .dipsw1 (pac_dipsw1), .dipsw2 (pac_dipsw2),
        .mod_plus (mod_plus), .mod_jmpst (mod_jmpst), .mod_bird (mod_bird), .mod_mrtnt (mod_mrtnt),
        .mod_ms (mod_ms), .mod_woodp (mod_woodp), .mod_eeek (mod_eeek), .mod_glob (mod_glob),
        .mod_alib (mod_alib), .mod_ponp (mod_ponp | mod_van | mod_dshop),
        .mod_van (mod_van | mod_dshop), .mod_dshop (mod_dshop),
        .mod_club (mod_club),
        .flip_screen (flip_trio), .h_offset (3'd0), .v_offset (3'd0),
        .dn_addr (ioctl_addr), .dn_data (ioctl_data), .dn_wr (ioctl_wr),
        .pause (core_pause),
        .hs_address (hs_addr), .hs_data_in (hs_din), .hs_data_out (hs_dout),
        .hs_write_enable (hs_wen), .hs_access_read (hs_rd), .hs_access_write (hs_wr_acc),
        .ss_cpu_idx (ss_cpu_idx), .ss_cpu_dout (ss_cpu_dout), .ss_cpu_bndry (ss_cpu_bndry),
        .ss_cpu_din (ss_cpu_din), .ss_cpu_wr (ss_cpu_wr), .ss_cpu_load (ss_cpu_load),
        .ss_st_idx (ss_st_idx), .ss_st_dout (ss_st_dout),
        .ss_st_din (ss_st_din), .ss_st_wr (ss_st_wr), .ss_freeze (ss_freeze),
        .RESET (core_reset),
        .CLK (clk_sys),
        .ENA_6 (ce_6m), .ENA_4 (ce_4m), .ENA_1M79 (ce_1m79)
    );


    
endmodule
