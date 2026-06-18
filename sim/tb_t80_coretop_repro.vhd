-- ============================================================================
-- GHDL testbench: REPRODUCE the on-device save-state failure by driving the T80
-- the SAME way core_top.v + pacman.vhd do, instead of the clean CLKEN-freeze the
-- passing tb_t80_saverestore.vhd uses.
--
-- KEY DIFFERENCES vs the passing TB (these are what the real core does):
--
--   PAUSE MECHANISM
--     tb_t80_saverestore: pause = drop CLKEN to 0 (CPU clock frozen). WAIT_n='1'.
--     REAL pacman.vhd   : CLKEN = hcnt(0) and ena_6  -- KEEPS PULSING during pause.
--                         WAIT_n = sync_bus_wreq_l and (not pause) -- pause drives
--                         WAIT_n LOW. So the CPU stalls at MCycle=1/TState=2 with
--                         the clock still enabled, NOT at the M1/T1 boundary.
--
--   SAVE TRIGGER
--     tb_t80_saverestore: snapshots dut_a at a CLEAN M1/T1 boundary (ss_bndry='1').
--     REAL core_top.v   : host pulses savestate_start ASYNCHRONOUSLY while the game
--                         runs. ss_pause_o asserts (WAIT_n low). ss_cpu_load is only
--                         asserted during the CPU phase (cnt>=4096), AFTER the 4096
--                         RAM bytes have been walked (4096*3 = 12288 sys cycles).
--                         By the time the CPU registers are read, the CPU has been
--                         WAIT-stalled mid-instruction for thousands of cycles.
--
-- This TB models BOTH precisely:
--   dut_a (golden) : runs free with the pacman CLKEN/WAIT pause model.
--   dut_b (restored): gets the snapshot taken from dut_a at the WAIT-stall point,
--                     restored with ss_load held across the CPU phase only.
--
-- Phase A: run dut_a; at an arbitrary (mid-instruction) moment assert pause
--          (WAIT_n low, CLKEN pulsing) exactly like ss_pause_o. Hold it for the
--          RAM-phase duration (CPU stalled), THEN read the 32 CPU bytes with
--          ss_cpu_load asserted (the CPU phase), exactly like the FSM.
-- Phase B: import into dut_b with ss_load held only across the writes, release.
-- Phase C: release pause on BOTH and lockstep-compare the external bus.
--
-- If the restored core diverges from the golden, that reproduces the on-device
-- "load does nothing / glitches / resets" symptom.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_t80_coretop_repro is
  generic ( PAUSE_DELAY : integer := 1200 );  -- async-save offset (sweepable)
end entity;

architecture sim of tb_t80_coretop_repro is

  signal clk     : std_logic := '0';
  signal running : boolean   := true;

  -- pacman CLKEN model: a 2-phase clock-enable that KEEPS PULSING during pause.
  -- (real: hcnt(0) and ena_6; here a simple toggle so CEN is high every 2nd clk.)
  signal cen_div : std_logic := '0';
  signal cen     : std_logic;

  -- pause level (maps to ss_pause_o -> WAIT_n low). Applied to BOTH cores' WAIT_n.
  signal a_pause : std_logic := '0';
  signal b_pause : std_logic := '0';

  ----------------------------------------------------------------------------
  -- dut_a : golden
  ----------------------------------------------------------------------------
  signal a_reset_n : std_logic := '0';
  signal a_m1_n, a_mreq_n, a_iorq_n, a_rd_n, a_wr_n, a_rfsh_n, a_halt_n, a_busak_n : std_logic;
  signal a_A     : std_logic_vector(15 downto 0);
  signal a_DI, a_DO : std_logic_vector(7 downto 0);
  signal a_ss_idx  : std_logic_vector(4 downto 0) := (others => '0');
  signal a_ss_dout : std_logic_vector(7 downto 0);
  signal a_ss_bndry: std_logic;
  signal a_ss_din  : std_logic_vector(7 downto 0) := (others => '0');
  signal a_ss_wr   : std_logic := '0';
  signal a_ss_load : std_logic := '0';

  ----------------------------------------------------------------------------
  -- dut_b : restored
  ----------------------------------------------------------------------------
  signal b_reset_n : std_logic := '0';
  signal b_m1_n, b_mreq_n, b_iorq_n, b_rd_n, b_wr_n, b_rfsh_n, b_halt_n, b_busak_n : std_logic;
  signal b_A     : std_logic_vector(15 downto 0);
  signal b_DI, b_DO : std_logic_vector(7 downto 0);
  signal b_ss_idx  : std_logic_vector(4 downto 0) := (others => '0');
  signal b_ss_dout : std_logic_vector(7 downto 0);
  signal b_ss_bndry: std_logic;
  signal b_ss_din  : std_logic_vector(7 downto 0) := (others => '0');
  signal b_ss_wr   : std_logic := '0';
  signal b_ss_load : std_logic := '0';

  type ssbuf_t is array(0 to 31) of std_logic_vector(7 downto 0);
  signal snap : ssbuf_t := (others => (others => '0'));

  type mem_t is array(0 to 4095) of std_logic_vector(7 downto 0);
  -- Same program as the passing TB: defines every architectural register.
  constant PROG : mem_t := (
    16#00# => x"3E", 16#01# => x"5A",
    16#02# => x"B7",
    16#03# => x"08",
    16#04# => x"3E", 16#05# => x"99",
    16#06# => x"B7",
    16#07# => x"08",
    16#0A# => x"31", 16#0B# => x"34", 16#0C# => x"12",
    16#0D# => x"01", 16#0E# => x"78", 16#0F# => x"56",
    16#10# => x"11", 16#11# => x"BC", 16#12# => x"9A",
    16#13# => x"21", 16#14# => x"F0", 16#15# => x"DE",
    16#16# => x"DD", 16#17# => x"21", 16#18# => x"EF", 16#19# => x"BE",
    16#1A# => x"FD", 16#1B# => x"21", 16#1C# => x"0D", 16#1D# => x"F0",
    16#1E# => x"3E", 16#1F# => x"3F",
    16#20# => x"ED", 16#21# => x"47",
    16#22# => x"FB",
    16#23# => x"D9",
    16#24# => x"01", 16#25# => x"11", 16#26# => x"22",
    16#27# => x"11", 16#28# => x"33", 16#29# => x"44",
    16#2A# => x"21", 16#2B# => x"55", 16#2C# => x"66",
    16#2D# => x"C3", 16#2E# => x"50", 16#2F# => x"01",
    16#150# => x"78",
    16#151# => x"32", 16#152# => x"00", 16#153# => x"08",
    16#154# => x"08",
    16#155# => x"32", 16#156# => x"01", 16#157# => x"08",
    16#158# => x"08",
    16#159# => x"32", 16#15A# => x"02", 16#15B# => x"08",
    16#15C# => x"F5",
    16#15D# => x"F1",
    16#15E# => x"18", 16#15F# => x"F0",
    others => x"00");

  signal mem_a : mem_t := PROG;
  signal mem_b : mem_t := PROG;

  constant TRACE_LEN : integer := 256;
  type trace_t is array(0 to TRACE_LEN-1) of std_logic_vector(33 downto 0);
  signal trace_a : trace_t := (others => (others => '0'));
  signal trace_b : trace_t := (others => (others => '0'));
  signal cap_a   : boolean := false;
  signal cap_b   : boolean := false;
  signal idx_a   : integer := 0;
  signal idx_b   : integer := 0;

  function pack_bus(A  : std_logic_vector(15 downto 0);
                    DO : std_logic_vector(7 downto 0);
                    mreq, rd, wr, m1, iorq, rfsh : std_logic)
                    return std_logic_vector is
    variable v : std_logic_vector(33 downto 0) := (others => '0');
  begin
    v(33 downto 18) := A;
    v(17 downto 10) := DO;
    v(9) := mreq; v(8) := rd; v(7) := wr;
    v(6) := m1;   v(5) := iorq; v(4) := rfsh;
    return v;
  end function;

begin

  ----------------------------------------------------------------------------
  -- pacman-style clock-enable: divides clk by 2, keeps pulsing during pause.
  ----------------------------------------------------------------------------
  process(clk) begin
    if rising_edge(clk) then cen_div <= not cen_div; end if;
  end process;
  cen <= cen_div;   -- CEN high on alternate clocks (CLKEN keeps pulsing always)

  ----------------------------------------------------------------------------
  -- two CPU instances. WAIT_n is driven LOW by pause (pacman model), CLKEN=cen
  -- keeps pulsing regardless of pause -- this is the on-device behaviour.
  ----------------------------------------------------------------------------
  dut_a : entity work.T80sed
    port map (
      RESET_n => a_reset_n, CLK_n => clk, CLKEN => cen, WAIT_n => (not a_pause),
      INT_n => '1', NMI_n => '1', BUSRQ_n => '1',
      M1_n => a_m1_n, MREQ_n => a_mreq_n, IORQ_n => a_iorq_n,
      RD_n => a_rd_n, WR_n => a_wr_n, RFSH_n => a_rfsh_n,
      HALT_n => a_halt_n, BUSAK_n => a_busak_n,
      A => a_A, DI => a_DI, DO => a_DO,
      ss_idx => a_ss_idx, ss_dout => a_ss_dout, ss_bndry => a_ss_bndry,
      ss_din => a_ss_din, ss_wr => a_ss_wr, ss_load => a_ss_load);

  dut_b : entity work.T80sed
    port map (
      RESET_n => b_reset_n, CLK_n => clk, CLKEN => cen, WAIT_n => (not b_pause),
      INT_n => '1', NMI_n => '1', BUSRQ_n => '1',
      M1_n => b_m1_n, MREQ_n => b_mreq_n, IORQ_n => b_iorq_n,
      RD_n => b_rd_n, WR_n => b_wr_n, RFSH_n => b_rfsh_n,
      HALT_n => b_halt_n, BUSAK_n => b_busak_n,
      A => b_A, DI => b_DI, DO => b_DO,
      ss_idx => b_ss_idx, ss_dout => b_ss_dout, ss_bndry => b_ss_bndry,
      ss_din => b_ss_din, ss_wr => b_ss_wr, ss_load => b_ss_load);

  a_DI <= mem_a(to_integer(unsigned(a_A(11 downto 0))));
  process(clk) begin
    if rising_edge(clk) then
      if a_mreq_n = '0' and a_wr_n = '0' then
        mem_a(to_integer(unsigned(a_A(11 downto 0)))) <= a_DO;
      end if;
    end if;
  end process;

  b_DI <= mem_b(to_integer(unsigned(b_A(11 downto 0))));
  process(clk) begin
    if rising_edge(clk) then
      if b_mreq_n = '0' and b_wr_n = '0' then
        mem_b(to_integer(unsigned(b_A(11 downto 0)))) <= b_DO;
      end if;
    end if;
  end process;

  clk <= not clk after 5 ns when running else '0';

  rec_a : process(clk)
  begin
    if rising_edge(clk) and cap_a and idx_a < TRACE_LEN then
      trace_a(idx_a) <= pack_bus(a_A, a_DO, a_mreq_n, a_rd_n, a_wr_n,
                                 a_m1_n, a_iorq_n, a_rfsh_n);
      idx_a <= idx_a + 1;
    end if;
  end process;

  rec_b : process(clk)
  begin
    if rising_edge(clk) and cap_b and idx_b < TRACE_LEN then
      trace_b(idx_b) <= pack_bus(b_A, b_DO, b_mreq_n, b_rd_n, b_wr_n,
                                 b_m1_n, b_iorq_n, b_rfsh_n);
      idx_b <= idx_b + 1;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- main stimulus
  ----------------------------------------------------------------------------
  stim : process
    variable ok : boolean := true;
    constant MAXOFF  : integer := 6;
    constant STEADY  : integer := 8;
    constant WINDOW  : integer := 200;
    variable best_k  : integer := -999;
    variable matched : boolean;

    -- read one snapshot byte out of dut_a (ss_load held -> CPU phase park)
    procedure a_rd(i : integer) is
    begin
      a_ss_idx <= std_logic_vector(to_unsigned(i, 5));
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;

    procedure b_rd(i : integer) is
    begin
      b_ss_idx <= std_logic_vector(to_unsigned(i, 5));
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;

    procedure b_wr(i : integer; d : std_logic_vector(7 downto 0)) is
    begin
      b_ss_idx <= std_logic_vector(to_unsigned(i, 5));
      b_ss_din <= d;
      b_ss_wr  <= '1';
      wait until rising_edge(clk);
      b_ss_wr  <= '0';
      wait for 1 ns;
    end procedure;
  begin
    ------------------------------------------------------------------ reset both
    a_reset_n <= '0';
    b_reset_n <= '0';
    b_ss_load <= '1';                 -- park dut_b held in restore from t=0
    b_pause   <= '1';                 -- dut_b also paused (WAIT_n low) while parked
    wait for 200 ns;
    a_reset_n <= '1';                 -- only A runs; B stays reset+parked

    ----------------------------------------- Phase A: run A, then ASYNC pause it
    -- run a fixed number of CEN cycles so the CPU is deep in the spin loop, then
    -- pause at an ARBITRARY point (NOT gated on ss_bndry) -- exactly like an async
    -- host savestate_start.
    for n in 0 to PAUSE_DELAY loop
      wait until rising_edge(clk);
    end loop;

    -- assert pause asynchronously (ss_pause_o -> WAIT_n low, CLKEN still pulsing)
    a_pause <= '1';
    report "Phase A: ASYNC pause asserted at PC-ish A=0x" & to_hstring(a_A) &
           " M1_n=" & std_logic'image(a_m1_n) &
           " bndry=" & std_logic'image(a_ss_bndry) severity note;

    -- HOLD the pause for the RAM-phase duration the real FSM imposes before it
    -- ever touches the CPU bytes: 4096 bytes * 3 sys cycles = 12288 sys cycles.
    -- (CPU is WAIT-stalled this whole time, just like on device.)
    for n in 0 to 12288 loop
      wait until rising_edge(clk);
    end loop;
    report "Phase A: RAM phase elapsed; CPU WAIT-stalled. A=0x" & to_hstring(a_A) &
           " M1_n=" & std_logic'image(a_m1_n) &
           " bndry=" & std_logic'image(a_ss_bndry) severity note;

    -- NOW the FSM enters the CPU phase: it asserts ss_cpu_load (= ss_active &
    -- ss_cpu_ph) and walks the 32 register bytes. Replicate: hold ss_load and
    -- read each byte.
    a_ss_load <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    report "Phase A: ss_load asserted (CPU phase). A=0x" & to_hstring(a_A) &
           " M1_n=" & std_logic'image(a_m1_n) &
           " bndry=" & std_logic'image(a_ss_bndry) severity note;

    for i in 0 to 31 loop
      a_rd(i);
      snap(i) <= a_ss_dout;
      wait for 1 ns;
      report "SNAP[" & integer'image(i) & "] = 0x" & to_hstring(a_ss_dout) severity note;
    end loop;
    a_ss_idx <= (others => '0');

    --------------------------------------------------- Phase B: import into dut_b
    b_reset_n <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    for i in 0 to 31 loop
      b_wr(i, snap(i));
    end loop;
    report "Phase B: snapshot written into dut_b" severity note;

    report "  dut_b parked at A=0x" & to_hstring(b_A) &
           " bndry=" & std_logic'image(b_ss_bndry) severity note;

    -- Structural readback compare (catches dropped/mis-packed bytes).
    for i in 0 to 31 loop
      if i /= 11 and i /= 12 and i /= 13 and i /= 14 and i /= 15 then
        b_rd(i);
        if b_ss_dout /= snap(i) then
          report "READBACK MISMATCH idx " & integer'image(i) &
                 " got 0x" & to_hstring(b_ss_dout) &
                 " expected 0x" & to_hstring(snap(i)) severity warning;
        end if;
      end if;
    end loop;
    b_ss_idx <= (others => '0');

    ----------------------------------------- Phase C: release + lockstep compare
    -- Release BOTH cores. dut_a: drop pause (FSM done) and ss_load. dut_b: drop
    -- ss_load and pause. Then both should free-run identically if restore is good.
    -- core_top drops ss_pause_o and ss_cpu_load together at SS_FIN.
    a_ss_load <= '0';
    a_pause   <= '0';
    b_ss_load <= '0';
    b_pause   <= '0';
    cap_a <= true;
    cap_b <= true;
    for n in 0 to TRACE_LEN + 8 loop
      wait until rising_edge(clk);
    end loop;
    cap_a <= false;
    cap_b <= false;
    wait for 1 ns;
    report "Phase C: captured " & integer'image(idx_a) & " (a) / " &
           integer'image(idx_b) & " (b) bus samples" severity note;

    ----------------------------------------------------------- verdict
    for k in -MAXOFF to MAXOFF loop
      matched := true;
      for j in 0 to WINDOW-1 loop
        if (STEADY + j + k) < 0 or (STEADY + j + k) >= idx_a
           or (STEADY + j) >= idx_b then
          matched := false; exit;
        end if;
        if trace_b(STEADY + j) /= trace_a(STEADY + j + k) then
          matched := false; exit;
        end if;
      end loop;
      if matched then best_k := k; exit; end if;
    end loop;

    if best_k > -999 then
      ok := true;
      report "PASS: restored dut_b bus trace == golden dut_a trace for " &
             integer'image(WINDOW) & " samples at phase offset k=" &
             integer'image(best_k) severity note;
    else
      ok := false;
      report "FAIL: no phase offset in +/-" & integer'image(MAXOFF) &
             " gives a " & integer'image(WINDOW) & "-sample match" severity error;
      for j in 0 to 31 loop
        report "  a[" & integer'image(j) & "]=0x" & to_hstring(trace_a(j)) &
               "   b[" & integer'image(j) & "]=0x" & to_hstring(trace_b(j))
          severity note;
      end loop;
    end if;

    if ok then
      report "tb_t80_coretop_repro DONE-OK (no divergence reproduced)" severity note;
    else
      report "tb_t80_coretop_repro REPRODUCED-DIVERGENCE" severity note;
    end if;

    running <= false;
    wait;
  end process;

end architecture;
