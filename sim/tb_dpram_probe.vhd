-- Probe: confirm the project's altsyncram-backed dpram elaborates under GHDL
-- (altera_mf lib) and characterise its read latency, so the e2e harness models
-- the buffer exactly. Writes a byte, reads it back, prints the q_a latency.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dpram_probe is end entity;

architecture sim of tb_dpram_probe is
  signal clk : std_logic := '0';
  signal run : boolean := true;
  signal addr_a, addr_b : std_logic_vector(12 downto 0) := (others => '0');
  signal data_a, data_b : std_logic_vector(7 downto 0) := (others => '0');
  signal wren_a, wren_b : std_logic := '0';
  signal q_a, q_b : std_logic_vector(7 downto 0);
begin
  clk <= not clk after 10 ns when run else '0';

  dut : entity work.dpram
    generic map (addr_width_g => 13, data_width_g => 8)
    port map (
      address_a => addr_a, data_a => data_a, wren_a => wren_a, enable_a => '1', clock_a => clk, q_a => q_a,
      address_b => addr_b, data_b => data_b, wren_b => wren_b, enable_b => '1', clock_b => clk, q_b => q_b
    );

  stim : process
  begin
    -- write 0xA5 to addr 7 on port A
    wait until rising_edge(clk);
    addr_a <= std_logic_vector(to_unsigned(7,13)); data_a <= x"A5"; wren_a <= '1';
    wait until rising_edge(clk);
    wren_a <= '0';
    -- read it back on port A: present addr, then sample q_a over a few cycles
    addr_a <= std_logic_vector(to_unsigned(7,13));
    wait until rising_edge(clk);
    report "after 1 read cycle: q_a = " & integer'image(to_integer(unsigned(q_a)));
    wait until rising_edge(clk);
    report "after 2 read cycles: q_a = " & integer'image(to_integer(unsigned(q_a)));
    -- cross-port: read addr 7 on port B
    addr_b <= std_logic_vector(to_unsigned(7,13));
    wait until rising_edge(clk);
    report "port B after 1 cycle: q_b = " & integer'image(to_integer(unsigned(q_b)));
    wait until rising_edge(clk);
    report "port B after 2 cycles: q_b = " & integer'image(to_integer(unsigned(q_b)));
    if to_integer(unsigned(q_a)) = 165 then
      report "DPRAM-OK: altsyncram read-back works under GHDL";
    else
      report "DPRAM-FAIL: read-back mismatch" severity error;
    end if;
    run <= false;
    wait;
  end process;
end architecture;
