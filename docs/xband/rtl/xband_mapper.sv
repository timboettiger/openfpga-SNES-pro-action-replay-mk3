//----------------------------------------------------------------------------
// xband_mapper.sv -- SNES cartridge-address decode for the XBAND add-on.
//
// Selects which storage answers a given CPU address: XBAND BIOS, the pass-
// through game ROM, the 64 KB battery SRAM, or the FRED register window.
// See docs/xband/11-rtl-architecture.md for the (LoROM-style, to-be-confirmed)
// memory map, and docs/xband/07-fred-register-map.md for the register offsets.
//
// Gating (see doc 07 control/kill bits):
//   * KILL_HERE_ASSERT (KILL[0]) -- FRED owns the bus; the pass-through cart
//     cannot be seen, so ROM-window reads come from the XBAND BIOS. This is the
//     boot state and is re-asserted whenever FRED needs the BIOS visible. With
//     it clear the ROM window is the pass-through game cart.
//   * kRomHi (CONTROL[2]) -- selects the upper 512 KB half of the 1 MB BIOS,
//     forming the top BIOS address bit.
//   * FRED patch redirect -- when the patch engine redirects a game access into
//     an injected subroutine, the access is served from XBAND SRAM at the
//     translated address instead of the cart.
//
// Reference skeleton -- the exact retail decode must be confirmed against a
// real 1 MB BIOS dump. The structure mirrors rtl/chip/mk3/mk3_mapper.sv.
//----------------------------------------------------------------------------
`default_nettype none

module xband_mapper
  import xband_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    input  logic [23:0]  cpu_addr,

    // FRED control/kill state (from xband_fred_regs)
    input  logic [7:0]   control_reg,
    input  logic [7:0]   kill_reg,

    // FRED patch engine redirect (from xband_fred_patch)
    input  logic         patch_redirect,
    input  logic [23:0]  patch_redirect_addr,

    output logic         sel_bios,
    output logic         sel_game,
    output logic         sel_sram,
    output logic         sel_reg,

    output logic [XBAND_SRAM_ADDR_BITS-1:0] sram_offset,
    output logic [8:0]   reg_offset,

    output logic         bios_read,
    output logic [XBAND_ROM_ADDR_BITS-1:0]  bios_read_addr
);

  // SNES address fields
  wire [7:0]  bank = cpu_addr[23:16];
  wire [15:0] off  = cpu_addr[15:0];

  // FRED arbitration bits.
  wire here   = (kill_reg    & KILL_HERE_ASSERT) != 8'h00;  // cart not visible
  wire rom_hi = (control_reg & CTL_ROM_HI)       != 8'h00;  // upper BIOS half

  // $xx:$6000-$7FFF -> SRAM window (banked); flat 15-bit offset within bank,
  // bank[1] selects the upper half so a few banks cover 64 KB.
  wire in_sram_win = (off >= 16'h6000) && (off <= 16'h7FFF);
  // $00-$3F / $80-$BF : $8000-$FFFF -> ROM (BIOS or game)
  wire in_rom_win  = off[15];
  // FRED register window (placeholder: a dedicated cart sub-range). The retail
  // decode must be confirmed; here we expose a 512-byte window in bank $00.
  wire in_reg_win  = (bank == 8'h00) && (off[15:9] == 7'h2A); // $5400-$55FF (placeholder)

  always_comb begin
    sel_bios = 1'b0;
    sel_game = 1'b0;
    sel_sram = 1'b0;
    sel_reg  = 1'b0;

    if (in_reg_win) begin
      sel_reg = 1'b1;
    end else if (patch_redirect) begin
      // FRED redirected this access into the injected subroutine in SRAM.
      sel_sram = 1'b1;
    end else if (in_sram_win) begin
      sel_sram = 1'b1;
    end else if (in_rom_win) begin
      // KILL_HERE_ASSERT => FRED owns the bus (BIOS visible); otherwise the
      // access falls through to the pass-through game cartridge.
      if (here) sel_bios = 1'b1;
      else      sel_game = 1'b1;
    end
  end

  // SRAM flat offset (16 bits = 64 KB). A patch redirect supplies the already-
  // translated safe-RAM address; otherwise use the banked $6000-$7FFF window:
  // {bank[2:0], 13-bit page within window}.
  assign sram_offset = patch_redirect ? patch_redirect_addr[XBAND_SRAM_ADDR_BITS-1:0]
                                      : { bank[2:0], cpu_addr[12:0] };

  // FRED register byte offset (even-addressed; see xband_pkg).
  assign reg_offset  = off[8:0];

  // BIOS byte address (20 bits = 1 MB, LoROM-style). kRomHi forms the top bank
  // bit so it selects the upper/lower 512 KB half: {rom_hi, bank[3:0], page}.
  assign bios_read      = sel_bios;
  assign bios_read_addr = { rom_hi, bank[3:0], cpu_addr[14:0] };

  wire _unused_ok = &{1'b0, clk, rst_n, patch_redirect_addr[23:XBAND_SRAM_ADDR_BITS]};

endmodule

`default_nettype wire
