-- GHDL testbench: validate the T80 savestate EXPORT read-out bus.
-- Runs a tiny Z80 program that loads known values into the registers, then reads
-- all 32 ss_idx bytes back out and checks the scalar regs (ACC, SP). The regfile
-- bytes are dumped for inspection. Run via:
--   ghdl -i --std=08 -fsynopsys cpu/*.vhd sim/tb_t80_ss.vhd
--   ghdl -m --std=08 -fsynopsys tb_t80_ss && ghdl -r --std=08 tb_t80_ss
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_t80_ss is end entity;

architecture sim of tb_t80_ss is
  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n : std_logic;
  signal A       : std_logic_vector(15 downto 0);
  signal DI, DO  : std_logic_vector(7 downto 0);
  signal ss_idx  : std_logic_vector(4 downto 0) := (others => '0');
  signal ss_dout : std_logic_vector(7 downto 0);
  signal ss_bndry: std_logic;
  signal running : boolean := true;

  type mem_t is array(0 to 4095) of std_logic_vector(7 downto 0);
  signal mem : mem_t := (
     0 => x"31",  1 => x"34",  2 => x"12",   -- LD SP,$1234
     3 => x"01",  4 => x"78",  5 => x"56",   -- LD BC,$5678
     6 => x"11",  7 => x"BC",  8 => x"9A",   -- LD DE,$9ABC
     9 => x"21", 10 => x"F0", 11 => x"DE",   -- LD HL,$DEF0
    12 => x"3E", 13 => x"42",                -- LD A,$42
    14 => x"0C",                             -- INC C  -> C=$79
    15 => x"76",                             -- HALT   (settle; no scratch churn)
    others => x"00");
begin
  dut : entity work.T80sed
    port map (
      RESET_n => reset_n, CLK_n => clk, CLKEN => '1', WAIT_n => '1',
      INT_n => '1', NMI_n => '1', BUSRQ_n => '1',
      M1_n => m1_n, MREQ_n => mreq_n, IORQ_n => iorq_n,
      RD_n => rd_n, WR_n => wr_n, RFSH_n => rfsh_n,
      HALT_n => halt_n, BUSAK_n => busak_n,
      A => A, DI => DI, DO => DO,
      ss_idx => ss_idx, ss_dout => ss_dout, ss_bndry => ss_bndry);

  -- async memory read
  DI <= mem(to_integer(unsigned(A(11 downto 0))));

  -- synchronous memory write
  process(clk) begin
    if rising_edge(clk) then
      if mreq_n = '0' and wr_n = '0' then
        mem(to_integer(unsigned(A(11 downto 0)))) <= DO;
      end if;
    end if;
  end process;

  clk <= not clk after 5 ns when running else '0';

  stim : process
    variable ok : boolean := true;
    procedure rd(i : integer) is
    begin
      ss_idx <= std_logic_vector(to_unsigned(i, 5));
      wait for 12 ns;
    end procedure;
  begin
    reset_n <= '0';
    wait for 120 ns;
    reset_n <= '1';
    wait for 6000 ns;   -- run the program to the spin loop

    running <= false;   -- freeze the CPU clock; ss read path is pure combinational
    wait for 30 ns;

    for i in 0 to 31 loop
      rd(i);
      report "ss_idx=" & integer'image(i) &
             "  ss_dout=0x" &
             to_hstring(ss_dout);
    end loop;

    -- Expected post-program state: A=42, SP=1234, PC=0010 (HALT@$0F+1),
    -- BC=5679 (INC C), DE=9ABC, HL=DEF0. Regfile: 16/17=B/C, 18/19=D/E, 20/21=H/L.
    check : for k in 0 to 10 loop
      case k is
        when 0  => rd(0);  if unsigned(ss_dout) /= 16#42# then ok := false; report "FAIL ACC=0x"  & to_hstring(ss_dout) severity error; end if;
        when 1  => rd(6);  if unsigned(ss_dout) /= 16#34# then ok := false; report "FAIL SPl=0x"  & to_hstring(ss_dout) severity error; end if;
        when 2  => rd(7);  if unsigned(ss_dout) /= 16#12# then ok := false; report "FAIL SPh=0x"  & to_hstring(ss_dout) severity error; end if;
        when 3  => rd(8);  if unsigned(ss_dout) /= 16#10# then ok := false; report "FAIL PCl=0x"  & to_hstring(ss_dout) severity error; end if;
        when 4  => rd(16); if unsigned(ss_dout) /= 16#56# then ok := false; report "FAIL B=0x"    & to_hstring(ss_dout) severity error; end if;
        when 5  => rd(17); if unsigned(ss_dout) /= 16#79# then ok := false; report "FAIL C=0x"    & to_hstring(ss_dout) severity error; end if;
        when 6  => rd(18); if unsigned(ss_dout) /= 16#9A# then ok := false; report "FAIL D=0x"    & to_hstring(ss_dout) severity error; end if;
        when 7  => rd(19); if unsigned(ss_dout) /= 16#BC# then ok := false; report "FAIL E=0x"    & to_hstring(ss_dout) severity error; end if;
        when 8  => rd(20); if unsigned(ss_dout) /= 16#DE# then ok := false; report "FAIL H=0x"    & to_hstring(ss_dout) severity error; end if;
        when 9  => rd(21); if unsigned(ss_dout) /= 16#F0# then ok := false; report "FAIL L=0x"    & to_hstring(ss_dout) severity error; end if;
        when 10 => null;
      end case;
    end loop;

    if ok then
      report "EXPORT-OK: all registers (A/BC/DE/HL/SP/PC) read back correctly via ss bus" severity note;
    else
      report "EXPORT-FAIL" severity error;
    end if;

    running <= false;
    wait;
  end process;
end architecture;
