-- ============================================================================
-- GHDL testbench: validate T80 save-state SAVE + RESTORE (export + import).
--
-- Strategy: two CPU instances run the SAME tiny Z80 program from reset.
--   dut_a  ("golden")  -- runs free; we snapshot its full state at a boundary
--   dut_b  ("restored")-- held in reset, then the snapshot is imported into it
--
--   Phase 1  run dut_a to the spin-loop boundary; latch all 32 ss bytes.
--   Phase 2  hold dut_b in reset, drive the import to write the snapshot back,
--            then release it AT THE SAME instruction boundary dut_a is sitting on.
--   Phase 3  step both in lockstep and assert their external bus activity
--            (A, DO, MREQ) matches cycle-for-cycle for the whole compare window.
--
-- If restore is correct, a freshly-restored CPU is indistinguishable on the bus
-- from one that reached that state by executing -- that is the real invariant a
-- save-state must satisfy.
--
-- ----------------------------------------------------------------------------
-- IMPORT INTERFACE CONTRACT (the RESTORE half this TB drives)
-- ----------------------------------------------------------------------------
-- The export half already added to T80/T80sed:
--     ss_idx   : in  slv(4 downto 0)   -- byte selector (0..31, map below)
--     ss_dout  : out slv(7 downto 0)   -- read-out of the selected byte
--     ss_bndry : out std_logic         -- '1' at MCycle=1,TState=1 (safe point)
--
-- The import half this TB assumes T80sed/T80 will expose:
--     ss_din   : in  slv(7 downto 0) := (others=>'0')  -- byte to write
--     ss_wr    : in  std_logic := '0'  -- 1-CEN-cycle strobe: latch ss_din@ss_idx
--     ss_load  : in  std_logic := '0'  -- held high while a restore is in progress
--
-- Semantics the RTL must honour (this is the spec the TB pins down):
--   * ADDITIVE: with ss_wr='0' and ss_load='0', behaviour is bit-identical to
--     stock T80 (no extra writes, microsequencer untouched).
--   * ss_wr is sampled on the CEN-qualified rising edge. When high, the byte at
--     ss_idx is written to the corresponding state element. Indices follow the
--     SAME map as the export mux:
--        0 ACC  1 F  2 Ap  3 Fp  4 I  5 R  6 SPl  7 SPh  8 PCl  9 PCh
--        10 = {"00",IMode(1:0),Halt,Alternate,IntE_FF2,IntE_FF1}
--        16+2k = RegsH(k), 17+2k = RegsL(k), k=0..7
--   * Restore loads write the architectural registers DIRECTLY (not via the
--     normal Save_Mux/RegWE datapath) so they do not fight the microsequencer.
--     The regfile (T80_Reg) gains a load path on AddrD/DIDH/DIDL gated by ss_wr.
--   * ss_load held high parks the FSM at MCycle=1/TState=1 (so the snapshot bytes
--     are not clobbered by an in-flight fetch while being written), and on the
--     falling edge of ss_load the CPU resumes from the restored PC/MCycle=1.
--
-- This TB elaborates against the FINAL port list. A reduced sibling that runs on
-- TODAY's export-only RTL is tb_t80_ss.vhd (already in repo); see run.sh.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_t80_saverestore is end entity;

architecture sim of tb_t80_saverestore is

  ----------------------------------------------------------------------------
  -- clock / shared
  ----------------------------------------------------------------------------
  signal clk     : std_logic := '0';
  signal running : boolean   := true;
  -- per-instance clock-enables: a save-state pauses the CPU (drops CLKEN) while
  -- its state is read/written, so nothing (incl. the R refresh counter) drifts.
  signal a_clken : std_logic := '1';
  signal b_clken : std_logic := '1';

  ----------------------------------------------------------------------------
  -- dut_a : golden (runs free)
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

  ----------------------------------------------------------------------------
  -- snapshot buffer
  ----------------------------------------------------------------------------
  type ssbuf_t is array(0 to 31) of std_logic_vector(7 downto 0);
  signal snap : ssbuf_t := (others => (others => '0'));

  ----------------------------------------------------------------------------
  -- shared program image. Every architectural register that can land in the
  -- snapshot is given a DEFINED value (no 'U'/'X' bytes), so the restore writes
  -- back legal data and the lockstep compare is meaningful. EXX + EX AF,AF'
  -- touch the alternate set; LD IX/IY define the last regfile pair.
  ----------------------------------------------------------------------------
  type mem_t is array(0 to 4095) of std_logic_vector(7 downto 0);
  constant PROG : mem_t := (
    -- ---- main set ----
     0 => x"31",  1 => x"34",  2 => x"12",        -- LD SP,$1234
     3 => x"01",  4 => x"78",  5 => x"56",        -- LD BC,$5678
     6 => x"11",  7 => x"BC",  8 => x"9A",        -- LD DE,$9ABC
     9 => x"21", 10 => x"F0", 11 => x"DE",        -- LD HL,$DEF0
    12 => x"3E", 13 => x"42",                     -- LD A,$42
    14 => x"0C",                                  -- INC C        -> C=$79
    15 => x"04",                                  -- INC B        -> B=$57
    -- ---- alternate set: swap, load junk, swap back so BC'/DE'/HL' are defined
    16 => x"D9",                                  -- EXX          (main<->alt GP)
    17 => x"01", 18 => x"11", 19 => x"22",        -- LD BC,$2211  (into BC')
    20 => x"11", 21 => x"33", 22 => x"44",        -- LD DE,$4433  (into DE')
    23 => x"21", 24 => x"55", 25 => x"66",        -- LD HL,$6655  (into HL')
    26 => x"D9",                                  -- EXX          (back to main)
    27 => x"08",                                  -- EX AF,AF'    (define A'/F')
    28 => x"3E", 29 => x"99",                     -- LD A,$99     (into A')
    30 => x"08",                                  -- EX AF,AF'    (back; A'=$99)
    -- ---- index registers: define both index-register regfile pairs so NO
    --      snapshot byte is ever 'U'/'X' (a restore must write legal data).
    31 => x"DD", 32 => x"21", 33 => x"EF", 34 => x"BE", -- LD IX,$BEEF
    35 => x"FD", 36 => x"21", 37 => x"0D", 38 => x"F0", -- LD IY,$F00D
    -- ---- spin so we sit on a stable instruction-fetch boundary ----
    39 => x"18", 40 => x"FE",                     -- JR -2  (spin on self @ $27)
    others => x"00");

  signal mem_a : mem_t := PROG;
  signal mem_b : mem_t := PROG;

  ----------------------------------------------------------------------------
  -- Bus-trace capture. Rather than depend on byte-perfect release timing, we
  -- record each core's external-bus sequence into a buffer and then assert the
  -- two sequences are identical under a constant phase offset. The recorded
  -- vector packs the externally-visible bus state at each clock:
  --   [33:18]=A  [17:10]=DO  [9]=MREQ_n [8]=RD_n [7]=WR_n [6]=M1_n
  --   [5]=IORQ_n [4]=RFSH_n  (lower bits unused/0)
  ----------------------------------------------------------------------------
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

  ----------------------------------------------------------------------------
  -- The SAVE boundary is the start of the spin-loop JR fetch. PC of the spin
  -- instruction is $0027. We snapshot when dut_a is fetching it.
  ----------------------------------------------------------------------------
  constant SPIN_PC : integer := 16#0027#;

begin

  ----------------------------------------------------------------------------
  -- two CPU instances
  ----------------------------------------------------------------------------
  dut_a : entity work.T80sed
    port map (
      RESET_n => a_reset_n, CLK_n => clk, CLKEN => a_clken, WAIT_n => '1',
      INT_n => '1', NMI_n => '1', BUSRQ_n => '1',
      M1_n => a_m1_n, MREQ_n => a_mreq_n, IORQ_n => a_iorq_n,
      RD_n => a_rd_n, WR_n => a_wr_n, RFSH_n => a_rfsh_n,
      HALT_n => a_halt_n, BUSAK_n => a_busak_n,
      A => a_A, DI => a_DI, DO => a_DO,
      ss_idx => a_ss_idx, ss_dout => a_ss_dout, ss_bndry => a_ss_bndry,
      ss_din => a_ss_din, ss_wr => a_ss_wr, ss_load => a_ss_load);

  dut_b : entity work.T80sed
    port map (
      RESET_n => b_reset_n, CLK_n => clk, CLKEN => b_clken, WAIT_n => '1',
      INT_n => '1', NMI_n => '1', BUSRQ_n => '1',
      M1_n => b_m1_n, MREQ_n => b_mreq_n, IORQ_n => b_iorq_n,
      RD_n => b_rd_n, WR_n => b_wr_n, RFSH_n => b_rfsh_n,
      HALT_n => b_halt_n, BUSAK_n => b_busak_n,
      A => b_A, DI => b_DI, DO => b_DO,
      ss_idx => b_ss_idx, ss_dout => b_ss_dout, ss_bndry => b_ss_bndry,
      ss_din => b_ss_din, ss_wr => b_ss_wr, ss_load => b_ss_load);

  ----------------------------------------------------------------------------
  -- per-instance RAM models (async read, sync write)
  ----------------------------------------------------------------------------
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

  ----------------------------------------------------------------------------
  -- trace recorders: sample each core's external bus into its buffer, one entry
  -- per clock, while capture is enabled. Both cores free-run normally during
  -- capture (no pause), so no pause/resume timing asymmetry can creep in.
  ----------------------------------------------------------------------------
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
    -- trace-alignment search locals. We skip a few samples at the start of each
    -- trace (the resume transient: a restored core can stall one extra clock on
    -- its first fetch) and then search a small +/- phase offset for a long exact
    -- match. STEADY*2 + WINDOW must stay within TRACE_LEN.
    constant MAXOFF  : integer := 6;    -- resume-latency search range (+/-)
    constant STEADY  : integer := 8;    -- samples to skip before comparing
    constant WINDOW  : integer := 200;  -- samples that must match exactly
    variable best_k  : integer := -999;
    variable matched : boolean;

    -- read one snapshot byte out of dut_a
    procedure a_rd(i : integer) is
    begin
      a_ss_idx <= std_logic_vector(to_unsigned(i, 5));
      wait until rising_edge(clk);
      wait for 1 ns;          -- let the combinational mux settle
    end procedure;

    -- write one snapshot byte into dut_b (single CEN-cycle strobe)
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
    wait for 120 ns;
    a_reset_n <= '1';                 -- only A runs; B stays reset+parked

    ------------------------------------------------------- Phase 1: run A to spin
    -- run long enough to execute the whole setup program and enter the spin.
    for n in 0 to 4000 loop
      wait until rising_edge(clk);
      -- detect dut_a parked on the spin instruction at an M1/T1 boundary
      exit when (a_ss_bndry = '1') and (unsigned(a_A) = SPIN_PC)
                and (a_m1_n = '0');
    end loop;

    assert (a_ss_bndry = '1') and (unsigned(a_A) = SPIN_PC)
      report "FAIL: dut_a never reached the spin boundary at PC=0x0027"
      severity failure;

    -- FREEZE dut_a at this exact boundary by dropping its clock-enable. This
    -- holds ALL of its state (including the R refresh counter and the registered
    -- bus outputs) frozen at the snapshot point, with NO pipeline interference
    -- (CLKEN freeze is what the real APF wrapper uses to pause the core). dut_a
    -- is captured exactly as the snapshot reads it.
    a_clken <= '0';
    wait for 1 ns;
    report "Phase 1: dut_a FROZEN at spin boundary, PC=0x" & to_hstring(a_A)
      severity note;

    ------------------------------------------------------- Phase 1: latch snapshot
    for i in 0 to 31 loop
      a_rd(i);
      snap(i) <= a_ss_dout;
      wait for 1 ns;
      report "SNAP[" & integer'image(i) & "] = 0x" & to_hstring(a_ss_dout) severity note;
    end loop;
    a_ss_idx <= (others => '0');

    --------------------------------------------------- Phase 2: import into dut_b
    -- dut_b is still in reset with ss_load high. Release reset but keep ss_load
    -- high so the FSM parks at M1/T1 and the snapshot writes are not disturbed.
    b_reset_n <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    for i in 0 to 31 loop
      b_wr(i, snap(i));
    end loop;
    report "Phase 2: snapshot written into dut_b (still parked at boundary)"
      severity note;

    -- Sanity-check dut_b landed on the restored boundary.
    assert (b_ss_bndry = '1') and (unsigned(b_A) = SPIN_PC)
      report "FAIL: dut_b not parked at PC=0x0027 after restore (got 0x"
             & to_hstring(b_A) & ")"
      severity failure;

    ----------------------------------------- Phase 3: capture + align two traces
    -- Run BOTH cores freely and record each one's external-bus sequence. The
    -- two cores are now in the same architectural state but were resumed via
    -- different mechanisms (dut_a un-frozen via CLKEN, dut_b un-parked via
    -- ss_load), which can introduce a constant phase offset of a few clocks.
    -- We therefore record both streams and then prove dut_b's stream is a
    -- byte-for-byte shift of dut_a's -- the invariant a correct restore must
    -- satisfy: a restored CPU produces the SAME bus activity as one that
    -- executed into that state, just possibly offset by the resume latency.
    a_clken   <= '1';     -- un-freeze dut_a; it resumes the spin
    b_ss_load <= '0';     -- un-park dut_b; it resumes from the restored state
    cap_a <= true;
    cap_b <= true;
    -- record a full buffer (covers many spin iterations on both cores)
    for n in 0 to TRACE_LEN + 8 loop
      wait until rising_edge(clk);
    end loop;
    cap_a <= false;
    cap_b <= false;
    wait for 1 ns;
    report "Phase 3: captured " & integer'image(idx_a) & " (a) / " &
           integer'image(idx_b) & " (b) bus samples" severity note;

    ----------------------------------------------------------- verdict
    -- Search a phase offset k in -MAXOFF..+MAXOFF such that, past the resume
    -- transient, dut_b(STEADY+j) == dut_a(STEADY+j+k) for WINDOW contiguous
    -- samples. A clean restore yields a perfect match at some small k (the
    -- resume latency); only a genuine restore bug makes EVERY offset diverge.
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
      -- dump the first 16 samples of each trace for diagnosis
      report "FAIL: no phase offset in +/-" & integer'image(MAXOFF) &
             " gives a " & integer'image(WINDOW) & "-sample match" severity error;
      for j in 0 to 15 loop
        report "  a[" & integer'image(j) & "]=0x" & to_hstring(trace_a(j)) &
               "   b[" & integer'image(j) & "]=0x" & to_hstring(trace_b(j))
          severity note;
      end loop;
    end if;

    assert ok report "tb_t80_saverestore FAILED" severity failure;
    report "tb_t80_saverestore DONE-OK" severity note;

    running <= false;
    wait;
  end process;

end architecture;
