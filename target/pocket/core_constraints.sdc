#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[0].*|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[2].*|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[3].*|divclk } \
 -group { ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

derive_clock_uncertainty

# SNES <-> SDRAM is accessed across the 4:1 clk_sys:clk_mem ratio with the request
# held stable, so the crossing is multicycle. NOTE: the SNES wrapper is `snes`
# (MAIN_SNES); the previous `ic|nes|sdram` was a stale NES-template name that
# silently matched nothing (Quartus "Ignored filter" warning), leaving SDRAM
# analyzed single-cycle. Fixed to `snes`.
set_multicycle_path -from {ic|snes|sdram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -setup 2
set_multicycle_path -from {ic|snes|sdram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -hold 1

set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|snes|sdram|*} -setup 2
set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|snes|sdram|*} -hold 1

# PSRAM (WRAM = cram0, ARAM = cram1) is accessed the same way (clk_sys -> clk_mem,
# request held stable). The savestate DMA adds an input mux on these clk_mem paths;
# without multicycle they are analyzed single-cycle and dominate the negative slack.
set_multicycle_path -from {ic|snes|wram|* ic|snes|aram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -setup 2
set_multicycle_path -from {ic|snes|wram|* ic|snes|aram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -hold 1

set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|snes|wram|* ic|snes|aram|*} -setup 2
set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|snes|wram|* ic|snes|aram|*} -hold 1

set_false_path -from {ic|nes|mapper_flags*}
#set_false_path -from {ic|nes|downloading*}
