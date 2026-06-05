--------------------------------------------------------------------------------
-- mk3_sram.vhd
--
-- 32 KB SRAM, the HY62256A on the original MK3 PCB (banks $00/02/04/06,
-- $6000-$7FFF; bank decode in mk3_mapper.sv). Flat 15-bit address on port A.
--
-- Dual-port:
--   Port A = SNES cart bus (ce/we/addr/din/dout, unregistered read)
--   Port B = Pocket save engine (sv_*), for save/restore of the 32 KB
--
-- Port A read is unregistered (same-cycle): the cart-data path consumes dout
-- combinationally. Writes are synchronous, gated by ce & we (SYSCLKF_CE
-- upstream). Reset must not clear the array, it holds the cheat list across a
-- soft reset; the save engine restores it at boot.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mk3_sram is
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;
        -- Port A: SNES cartridge bus
        ce      : in  std_logic;                       -- chip enable from mapper
        we      : in  std_logic;                       -- write enable
        addr    : in  std_logic_vector(14 downto 0);   -- 15-bit -> 32 KB
        din     : in  std_logic_vector(7 downto 0);
        dout    : out std_logic_vector(7 downto 0);
        -- Port B: Pocket save/restore engine (persistence)
        sv_addr : in  std_logic_vector(14 downto 0) := (others => '0');
        sv_din  : in  std_logic_vector(7 downto 0)  := (others => '0');
        sv_wren : in  std_logic := '0';
        sv_q    : out std_logic_vector(7 downto 0)
    );
end entity mk3_sram;

architecture rtl of mk3_sram is

    -- Port A write strobe: commit when the mapper selects this block (ce) AND
    -- a write is requested (we), matching the previous single-port behaviour.
    signal wren_a : std_logic;

begin

    wren_a <= ce and we;

    -- rst_n intentionally unreferenced: reset must not clear the array. Kept
    -- for interface symmetry.

    -- 32 KB dual-port block RAM, unregistered read on both ports (the async
    -- timing the menu/cheat code needs). Same work.dpram the base BSRAM uses.
    sram_blk : entity work.dpram
        generic map (
            addr_width => 15,
            data_width => 8
        )
        port map (
            clock     => clk,
            -- Port A: SNES side (async read, gated write)
            address_a => addr,
            data_a    => din,
            wren_a    => wren_a,
            q_a       => dout,
            -- Port B: Pocket save engine
            address_b => sv_addr,
            data_b    => sv_din,
            wren_b    => sv_wren,
            q_b       => sv_q
        );

end architecture rtl;
