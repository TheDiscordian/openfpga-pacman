// =============================================================================
// tb_ss_load.v -- iverilog regression for the on-device "load flickers forever /
// never restores" savestate fix (branch feat/savestates).
//
// It lifts the REAL savestate FSM out of core_top.v (the SS_IDLE/SS_ARM/SS_LD*/
// SS_FIN state machine, the ss_cpu_* park bus, ss_pause_o, the clk_74a status
// resync) verbatim into ss_fsm, drives it from a host model that performs the
// real 0x00A4 LOAD / 0x00A0 SAVE sequences (fill the bridge buffer through a
// data_loader, pulse savestate_load/start, poll the ok flag exactly like
// core_bridge_cmd.v's 0xA4/0xA0 handlers), and stubs pacman's ss_cpu_bndry two
// ways:
//
//   CPU free-running -> ss_cpu_bndry pulses (M1/T1)
//   CPU held         -> ss_cpu_bndry never pulses (the Memory-load reset case)
//
// THE BUG (pre-fix, 39cb6a3): LOAD armed in SS_ARM and waited for the natural
// M1/T1 boundary. Around a Memory load the Pocket holds the core in reset, so
// the CPU never reaches M1/T1 -> SS_ARM waited forever -> savestate_load_ok never
// asserted -> the host spun in the 0xA4 poll -> screen flickered forever.
//
// THE FIX (this file mirrors core_top.v): LOAD skips SS_ARM and forces the park
// immediately (a load overwrites all CPU state; the park itself creates the
// M1/T1 boundary). SAVE keeps the SS_ARM natural-boundary wait, now with a
// bounded timeout fallback (SS_ARM_TMO) so no wait can wedge the host forever.
//
// Scenarios (all must PASS):
//   [A] LOAD, CPU free-running  -> completes, RAM restored, never armed
//   [B] LOAD, CPU HELD          -> completes anyway (was the on-device hang)
//   [C] SAVE, CPU free-running  -> arms + completes on the natural boundary
//   [D] SAVE, CPU HELD          -> SS_ARM timeout fires, completes (no hang)
//
// `timescale 1ns/1ps
// Run: iverilog -g2012 -o /tmp/tb_ss_load.vvp sim/tb_ss_load.v && vvp /tmp/tb_ss_load.vvp
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// ss_fsm: the savestate FSM + park bus + status resync, copied from core_top.v
// (lines ~840-993) with only the surrounding-signal plumbing turned into ports.
// Logic is byte-for-byte the shipped FSM; nothing is "fixed" here.
// -----------------------------------------------------------------------------
module ss_fsm (
    input  wire        clk_sys,
    input  wire        clk_74a,
    // bridge pulses (clk_74a domain), same as core_bridge_cmd drives
    input  wire        savestate_start,
    input  wire        savestate_load,
    // pacman feedback (clk_sys)
    input  wire        ss_cpu_bndry,
    input  wire [7:0]  ss_cpu_dout,
    input  wire [7:0]  hs_dout,
    // dpram port A (FSM side)
    output reg  [12:0] ssa_addr,
    output reg  [7:0]  ssa_wdata,
    output reg         ssa_we,
    input  wire [7:0]  ssa_q,
    // CPU park bus into pacman
    output wire [4:0]  ss_cpu_idx,
    output wire [7:0]  ss_cpu_din,
    output wire        ss_cpu_wr,
    output wire        ss_cpu_load,
    // hiscore tap (work RAM) drive
    output reg  [11:0] ss_addr_o,
    output reg  [7:0]  ss_din_o,
    output reg         ss_wen_o,
    output reg         ss_rd_o,
    output reg         ss_wr_o,
    output reg         ss_pause_o,
    output wire        ss_active,
    // status back to host (clk_74a)
    output wire        savestate_load_ack,
    output wire        savestate_load_busy,
    output wire        savestate_load_ok,
    output wire        savestate_start_ok,
    // observability
    output wire [3:0]  ss_st_o
);
    localparam [12:0] SS_RAM   = 13'd4096;
    localparam [12:0] SS_BYTES = 13'd4128;

    // CDC of start/load pulses into clk_sys
    reg [2:0] ss_start_sr = 3'd0, ss_load_sr = 3'd0;
    always @(posedge clk_sys) begin
        ss_start_sr <= {ss_start_sr[1:0], savestate_start};
        ss_load_sr  <= {ss_load_sr[1:0],  savestate_load};
    end
    wire ss_start_rise = (ss_start_sr[2:1] == 2'b01);
    wire ss_load_rise  = (ss_load_sr[2:1]  == 2'b01);

    reg ss_bndry_q = 1'b0;
    always @(posedge clk_sys) ss_bndry_q <= ss_cpu_bndry;

    localparam SS_IDLE=4'd0, SS_SV0=4'd1, SS_SV1=4'd2, SS_SV2=4'd3,
               SS_LD0=4'd4, SS_LD1=4'd5, SS_LD2=4'd6, SS_FIN=4'd7,
               SS_ARM=4'd8;
    // SS_ARM bounded fallback (SAVE only). Use a SMALL timeout here so the sim's SAVE
    // scenario exercises the fallback in bounded time; the synthesised core uses
    // ~2^21 clk_sys cycles (~one frame) -- see core_top.v SS_ARM_TMO. The override is
    // accepted via a parameter so the testbench can shrink it without touching logic.
    parameter [20:0] SS_ARM_TMO = 21'd200;
    localparam       SS_ARM_CW  = 21;
    reg  [SS_ARM_CW-1:0] ss_arm_cnt = {SS_ARM_CW{1'b0}};
    reg  [3:0]  ss_st = SS_IDLE;
    reg  [12:0] ss_cnt;
    reg         ss_busy_cs = 1'b0;
    reg         ss_save_ok_cs = 1'b0, ss_load_ok_cs = 1'b0;
    reg         ss_op_load = 1'b0;
    reg  [4:0]  ss_cpu_idx_r;
    reg  [7:0]  ss_cpu_din_r;
    reg         ss_cpu_wr_r;
    assign ss_active  = (ss_st != SS_IDLE);
    wire   ss_walking = (ss_st != SS_IDLE) && (ss_st != SS_ARM);
    wire   ss_cpu_ph  = (ss_cnt >= SS_RAM);
    assign ss_st_o    = ss_st;

    always @(posedge clk_sys) begin
        ss_rd_o <= 1'b0; ss_wr_o <= 1'b0; ss_wen_o <= 1'b0; ssa_we <= 1'b0; ss_cpu_wr_r <= 1'b0;
        case (ss_st)
        SS_IDLE: begin
            ss_pause_o <= 1'b0;
            ss_arm_cnt <= {SS_ARM_CW{1'b0}};
            if (ss_start_rise) begin
                ss_st <= SS_ARM; ss_cnt <= 13'd0; ss_op_load <= 1'b0;
                ss_busy_cs <= 1'b1; ss_save_ok_cs <= 1'b0;
            end else if (ss_load_rise) begin
                // LOAD skips SS_ARM -- go straight to the walk, park immediately.
                ss_st <= SS_LD0; ss_cnt <= 13'd0; ss_op_load <= 1'b1;
                ss_busy_cs <= 1'b1; ss_load_ok_cs <= 1'b0; ss_pause_o <= 1'b1;
            end
        end
        SS_ARM: begin
            // SAVE only; bounded fallback forces the park if no boundary arrives.
            ss_arm_cnt <= ss_arm_cnt + {{(SS_ARM_CW-1){1'b0}}, 1'b1};
            if (ss_bndry_q || (ss_arm_cnt == SS_ARM_TMO)) begin
                ss_pause_o <= 1'b1;
                ss_st <= ss_op_load ? SS_LD0 : SS_SV0;
            end
        end
        SS_SV0: begin
            if (ss_cpu_ph) ss_cpu_idx_r <= ss_cnt[4:0];
            else begin ss_addr_o <= ss_cnt[11:0]; ss_rd_o <= 1'b1; end
            ss_st <= SS_SV1;
        end
        SS_SV1: begin ss_st <= SS_SV2; end
        SS_SV2: begin
            ssa_addr  <= ss_cnt;
            ssa_wdata <= ss_cpu_ph ? ss_cpu_dout : hs_dout;
            ssa_we    <= 1'b1;
            if (ss_cnt == SS_BYTES - 1) ss_st <= SS_FIN;
            else begin ss_cnt <= ss_cnt + 13'd1; ss_st <= SS_SV0; end
        end
        SS_LD0: begin ssa_addr <= ss_cnt; ss_st <= SS_LD1; end
        SS_LD1: begin ss_st <= SS_LD2; end
        SS_LD2: begin
            if (ss_cpu_ph) begin
                ss_cpu_idx_r <= ss_cnt[4:0]; ss_cpu_din_r <= ssa_q; ss_cpu_wr_r <= 1'b1;
            end else begin
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

    assign ss_cpu_idx  = ss_cpu_idx_r;
    assign ss_cpu_din  = ss_cpu_din_r;
    assign ss_cpu_wr   = ss_cpu_wr_r;
    assign ss_cpu_load = ss_walking;

    reg [2:0] ss_busy_74 = 3'd0, ss_save_ok_74 = 3'd0, ss_load_ok_74 = 3'd0;
    always @(posedge clk_74a) begin
        ss_busy_74    <= {ss_busy_74[1:0],    ss_busy_cs};
        ss_save_ok_74 <= {ss_save_ok_74[1:0], ss_save_ok_cs};
        ss_load_ok_74 <= {ss_load_ok_74[1:0], ss_load_ok_cs};
    end
    assign savestate_load_ack   = ss_busy_74[2] | ss_load_ok_74[2];
    assign savestate_load_busy  = ss_busy_74[2];
    assign savestate_load_ok    = ss_load_ok_74[2];
    assign savestate_start_ok   = ss_save_ok_74[2];
endmodule

// -----------------------------------------------------------------------------
// dpram model: 1-cycle registered read latency on both ports, matching the
// project's altsyncram-backed dpram(13,8) used for ss_buf.
// -----------------------------------------------------------------------------
module dpram_model (
    input  wire        clk,
    input  wire [12:0] addr_a, input wire [7:0] data_a, input wire wren_a, output reg [7:0] q_a,
    input  wire [12:0] addr_b, input wire [7:0] data_b, input wire wren_b, output reg [7:0] q_b
);
    reg [7:0] mem [0:8191];
    always @(posedge clk) begin
        if (wren_a) mem[addr_a] <= data_a;
        q_a <= mem[addr_a];
        if (wren_b) mem[addr_b] <= data_b;
        q_b <= mem[addr_b];
    end
endmodule

// =============================================================================
module tb_ss_load;
    // clocks: clk_sys ~24.576MHz, clk_74a ~74.25MHz (relative ratio only)
    reg clk_sys = 0; always #20 clk_sys = ~clk_sys;   // 25ns half -> 40ns period
    reg clk_74a = 0; always #7  clk_74a = ~clk_74a;   // faster bridge clock

    // ---- pacman ss_cpu_bndry stub --------------------------------------------
    // cpu_running=1: CPU clock-enabled & free, M1/T1 boundary pulses each "frame".
    // cpu_running=0: CPU held (reset / WAIT-stalled) -> boundary frozen at 0.
    reg cpu_running = 1'b1;
    reg [4:0] bndry_div = 0;
    reg ss_cpu_bndry = 0;
    always @(posedge clk_sys) begin
        if (cpu_running) begin
            // free CPU reaches an M1/T1 fetch boundary periodically. On real HW a
            // Z80 instruction is a handful of CEN beats, so M1/T1 recurs often;
            // model it every 24 clk_sys cycles (well inside the host poll budget).
            bndry_div <= (bndry_div == 5'd23) ? 5'd0 : bndry_div + 5'd1;
            ss_cpu_bndry <= (bndry_div == 5'd0);
        end else begin
            // held CPU: MCycle/TState frozen, ss_bndry combinational-low forever
            bndry_div <= 0;
            ss_cpu_bndry <= 1'b0;
        end
    end
    wire [7:0] ss_cpu_dout = 8'hC0;     // arbitrary CPU reg read-out

    // ---- work-RAM (hiscore tap) read model -----------------------------------
    reg [7:0] workram [0:4095];
    reg [11:0] wr_addr_reg = 0;
    wire [7:0] hs_dout = workram[wr_addr_reg];

    // ---- FSM wiring ----------------------------------------------------------
    reg  savestate_start = 0;
    reg  savestate_load  = 0;
    wire [12:0] ssa_addr; wire [7:0] ssa_wdata; wire ssa_we; wire [7:0] ssa_q;
    wire [4:0]  ss_cpu_idx; wire [7:0] ss_cpu_din; wire ss_cpu_wr, ss_cpu_load;
    wire [11:0] ss_addr_o; wire [7:0] ss_din_o; wire ss_wen_o, ss_rd_o, ss_wr_o;
    wire ss_pause_o, ss_active;
    wire savestate_load_ack, savestate_load_busy, savestate_load_ok, savestate_start_ok;
    wire [3:0] ss_st_o;

    // work-RAM tap: register address, commit writes from the FSM (load path)
    always @(posedge clk_sys) begin
        wr_addr_reg <= ss_addr_o;
        if (ss_active && ss_wen_o) workram[ss_addr_o] <= ss_din_o;
    end

    ss_fsm dut (
        .clk_sys(clk_sys), .clk_74a(clk_74a),
        .savestate_start(savestate_start), .savestate_load(savestate_load),
        .ss_cpu_bndry(ss_cpu_bndry), .ss_cpu_dout(ss_cpu_dout), .hs_dout(hs_dout),
        .ssa_addr(ssa_addr), .ssa_wdata(ssa_wdata), .ssa_we(ssa_we), .ssa_q(ssa_q),
        .ss_cpu_idx(ss_cpu_idx), .ss_cpu_din(ss_cpu_din), .ss_cpu_wr(ss_cpu_wr), .ss_cpu_load(ss_cpu_load),
        .ss_addr_o(ss_addr_o), .ss_din_o(ss_din_o), .ss_wen_o(ss_wen_o), .ss_rd_o(ss_rd_o), .ss_wr_o(ss_wr_o),
        .ss_pause_o(ss_pause_o), .ss_active(ss_active),
        .savestate_load_ack(savestate_load_ack), .savestate_load_busy(savestate_load_busy),
        .savestate_load_ok(savestate_load_ok), .savestate_start_ok(savestate_start_ok),
        .ss_st_o(ss_st_o)
    );

    // ---- bridge buffer dpram + host fill model -------------------------------
    // Port B = bridge/host (fills the buffer on load). Port A = FSM.
    reg  [12:0] hb_addr = 0; reg [7:0] hb_data = 0; reg hb_we = 0;
    wire [7:0]  ssb_q;
    dpram_model ss_buf (
        .clk(clk_sys),
        .addr_a(ssa_addr), .data_a(ssa_wdata), .wren_a(ssa_we), .q_a(ssa_q),
        .addr_b(hb_addr),  .data_b(hb_data),   .wren_b(hb_we),  .q_b(ssb_q)
    );

    // Host fills all 4128 buffer bytes (the data_loader streamed write).
    task host_fill_buffer;
        integer i;
        begin
            @(posedge clk_sys);
            for (i = 0; i < 4128; i = i + 1) begin
                hb_addr <= i[12:0]; hb_data <= i[7:0] ^ 8'h5A; hb_we <= 1'b1;
                @(posedge clk_sys);
            end
            hb_we <= 1'b0;
            @(posedge clk_sys);
        end
    endtask

    // Host 0x00A4 LOAD: pulse savestate_load, poll savestate_load_ok, with a
    // bounded poll budget that mirrors "host gives up / retries -> flicker".
    integer poll;
    integer fail = 0;
    reg load_done;
    task host_load(input integer max_poll);
        begin
            load_done = 1'b0;
            @(posedge clk_74a); savestate_load <= 1'b1;   // request load
            // poll like core_bridge_cmd.v 0xA4: read ok each "frame"
            for (poll = 0; poll < max_poll; poll = poll + 1) begin
                repeat (50) @(posedge clk_74a);
                if (savestate_load_ok) begin
                    load_done = 1'b1;
                    poll = max_poll; // break
                end
            end
            @(posedge clk_74a); savestate_load <= 1'b0;   // host clears in ST_IDLE
        end
    endtask

    // Host 0x00A0 SAVE: pulse savestate_start, poll savestate_start_ok (mirrors
    // core_bridge_cmd.v's 0xA0 handler).
    reg save_done;
    task host_save(input integer max_poll);
        begin
            save_done = 1'b0;
            @(posedge clk_74a); savestate_start <= 1'b1;
            for (poll = 0; poll < max_poll; poll = poll + 1) begin
                repeat (50) @(posedge clk_74a);
                if (savestate_start_ok) begin
                    save_done = 1'b1;
                    poll = max_poll;
                end
            end
            @(posedge clk_74a); savestate_start <= 1'b0;
        end
    endtask

    integer st_arm_cycles;
    reg counting_arm;
    // count consecutive cycles parked in SS_ARM (state 8)
    always @(posedge clk_sys) begin
        if (ss_st_o == 4'd8) begin
            if (counting_arm) st_arm_cycles <= st_arm_cycles + 1;
        end
    end

    localparam [3:0] SS_ARM_ST = 4'd8, SS_FIN_ST = 4'd7, SS_IDLE_ST = 4'd0;

    // Verify the work RAM restored by the load equals what the host wrote into the
    // bridge buffer (bytes 0..4095). The host fill writes buffer[i] = i^0x5A, so a
    // correct LOAD must leave workram[i] = i^0x5A.
    task check_ram_restore(output integer mism);
        integer j; reg [7:0] exp;
        begin
            mism = 0;
            for (j = 0; j < 4096; j = j + 1) begin
                exp = (j[7:0]) ^ 8'h5A;
                if (workram[j] !== exp) mism = mism + 1;
            end
        end
    endtask

    integer i, mism;
    initial begin
        savestate_start = 1'b0;
        save_done = 1'b0;

        $display("============================================================");
        $display(" tb_ss_load: REGRESSION -- fixed savestate FSM (LOAD skips SS_ARM)");
        $display("============================================================");

        // ===== SCENARIO A: LOAD, CPU free-running (boundary pulses) ============
        for (i = 0; i < 4096; i = i + 1) workram[i] = 8'h00;
        cpu_running = 1'b1;
        $display("\n[A] LOAD with CPU free-running (ss_cpu_bndry pulses)");
        host_fill_buffer;
        st_arm_cycles = 0; counting_arm = 1;
        host_load(1200);
        counting_arm = 0;
        check_ram_restore(mism);
        $display("    SS_ARM cycles burned: %0d (LOAD must not enter SS_ARM => 0)", st_arm_cycles);
        $display("    final ss_st = %0d (0=IDLE)  load_ok=%b load_done=%b  RAM mismatches=%0d",
                 ss_st_o, savestate_load_ok, load_done, mism);
        if (load_done && ss_st_o == SS_IDLE_ST && mism == 0 && st_arm_cycles == 0)
            $display("    => PASS: LOAD completed, returned to IDLE, RAM restored, never armed");
        else begin $display("    => FAIL"); fail = fail + 1; end

        // ===== SCENARIO B: LOAD, CPU HELD (boundary never pulses) ==============
        // The on-device Memory-load case: the Pocket holds the core in reset while
        // it streams the state in, so the CPU never reaches M1/T1. PRE-FIX this
        // wedged SS_ARM forever (flicker). POST-FIX the load skips SS_ARM and the
        // park forces M1/T1 itself, so it MUST still complete.
        for (i = 0; i < 4096; i = i + 1) workram[i] = 8'hFF;
        cpu_running = 1'b0;
        repeat (10) @(posedge clk_sys);
        $display("\n[B] LOAD with CPU HELD (ss_cpu_bndry never pulses) -- the on-device Memory-load case");
        host_fill_buffer;
        st_arm_cycles = 0; counting_arm = 1;
        host_load(1200);
        counting_arm = 0;
        check_ram_restore(mism);
        $display("    SS_ARM cycles burned: %0d (must be 0 -- LOAD bypasses the wait)", st_arm_cycles);
        $display("    final ss_st = %0d (0=IDLE)  load_ok=%b load_done=%b  RAM mismatches=%0d",
                 ss_st_o, savestate_load_ok, load_done, mism);
        if (load_done && ss_st_o == SS_IDLE_ST && mism == 0 && st_arm_cycles == 0)
            $display("    => PASS: LOAD completed despite the held CPU (no hang, RAM restored)");
        else begin $display("    => FAIL: load did not complete with CPU held"); fail = fail + 1; end

        // ===== SCENARIO C: SAVE, CPU free-running (natural boundary) ===========
        // SAVE must STILL arm in SS_ARM and wait for the natural M1/T1 boundary.
        cpu_running = 1'b1;
        repeat (10) @(posedge clk_sys);
        $display("\n[C] SAVE with CPU free-running (must arm + use the natural boundary)");
        st_arm_cycles = 0; counting_arm = 1;
        host_save(1200);
        counting_arm = 0;
        $display("    SS_ARM cycles burned: %0d (>0 => SAVE armed and waited)", st_arm_cycles);
        $display("    final ss_st = %0d (0=IDLE)  start_ok=%b save_done=%b",
                 ss_st_o, savestate_start_ok, save_done);
        if (save_done && ss_st_o == SS_IDLE_ST && st_arm_cycles > 0)
            $display("    => PASS: SAVE armed on the natural boundary and completed");
        else begin $display("    => FAIL: save did not complete via boundary"); fail = fail + 1; end

        // ===== SCENARIO D: SAVE, CPU HELD (timeout fallback) ==================
        // Defense in depth: if the boundary never arrives at SAVE time, the SS_ARM
        // bounded fallback (SS_ARM_TMO) must force the park so the host handshake
        // can never wedge forever.
        cpu_running = 1'b0;
        repeat (10) @(posedge clk_sys);
        $display("\n[D] SAVE with CPU HELD (boundary never pulses -- exercise SS_ARM timeout)");
        st_arm_cycles = 0; counting_arm = 1;
        host_save(1200);
        counting_arm = 0;
        $display("    SS_ARM cycles burned: %0d (~SS_ARM_TMO => fallback fired)", st_arm_cycles);
        $display("    final ss_st = %0d (0=IDLE)  start_ok=%b save_done=%b",
                 ss_st_o, savestate_start_ok, save_done);
        if (save_done && ss_st_o == SS_IDLE_ST && st_arm_cycles > 0)
            $display("    => PASS: SS_ARM timeout forced the park, SAVE completed (no hang)");
        else begin $display("    => FAIL: save hung with CPU held (timeout did not fire)"); fail = fail + 1; end

        $display("\n============================================================");
        if (fail == 0) $display(" RESULT: ALL PASS -- LOAD no longer hangs, SAVE path intact");
        else           $display(" RESULT: %0d scenario(s) FAILED", fail);
        $display("============================================================");
        $finish;
    end

    initial begin #50000000; $display("\n[WATCHDOG] global sim timeout"); $finish; end
endmodule
`default_nettype wire
