#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# The four PLL outputs are all derived from one VCO and are integer/phase-related
# (clk_pix = clk_sys/4, clk_pix_90 the same at +90deg), NOT asynchronous. Grouping
# them async false-paths the clk_sys->clk_pix video-output capture, leaving it
# untimed and placement-dependent (the fit-sensitive right-edge stripe). Keep the
# PLL outputs in ONE group so the crossing is analysed; only the genuinely
# unrelated host/bridge clocks stay asynchronous.
set CLK_SYS    {ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLK_PIX    {ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLK_PIX_90 {ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLK_SYS_B  {ic|mp1|mf_pllbase_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [list $CLK_SYS $CLK_PIX $CLK_PIX_90 $CLK_SYS_B]

# The video output registers capture core RGB/blank/sync (generated in clk_sys on
# the ce_6m = /4 pixel beat) into clk_pix (= clk_sys/4). The data is stable for a
# full pixel (4 clk_sys cycles), so relax the same-VCO transfer to its true 4:1
# ratio instead of the default single-cycle requirement.
set_multicycle_path -setup 4 -from [get_clocks $CLK_SYS] -to [get_clocks $CLK_PIX]
set_multicycle_path -hold  3 -from [get_clocks $CLK_SYS] -to [get_clocks $CLK_PIX]
