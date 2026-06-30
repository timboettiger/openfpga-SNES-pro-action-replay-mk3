//----------------------------------------------------------------------------
// xband_mapper.sv -- SNES cartridge-address decode for the XBAND add-on.
//
// Selects which storage answers a given CPU address: XBAND BIOS, the pass-
// through game ROM, the 64 KB battery SRAM, or the FRED register window.
//
// HiROM decode -- CONFIRMED against the real 1 MB BIOS dump
// (docs/xband/13-rom-memory-map.md): header @ $FFC0, mapmode 0x31 (HiROM +
// FastROM), romsize 0x0A (1 MB), ramsize 0x06 (64 KB), checksum 0x1A5D verified,
// emulation RESET $FFE0 -> JML $D0:0000. The register offsets are in
// docs/xband/07-fred-register-map.md.
//
// Address map (HiROM):
//   * ROM   : $C0-$FF:$0000-$FFFF (full banks) and $00-$3F/$80-$BF:$8000-$FFFF
//             (upper half). 1 MB mirrored across 16 banks.
//   * SRAM  : 64 KB linear at bank $E0 (the BIOS reads $E0:0000), plus the
//             classic HiROM $20-$3F:$6000-$7FFF small window.
//   * regs  : a FRED register window in cart space (offsets per doc 07).
//
// Gating (see doc 07 control/kill bits):
//   * KILL_HERE_ASSERT (KILL[0]) -- FRED owns the bus; the pass-through cart
//     cannot be seen, so ROM-window reads come from the XBAND BIOS. This is the
//     boot state. With it clear the ROM window is the pass-through game cart.
//   * kRomHi (CONTROL[2]) -- selects which 512 KB half of the 1 MB BIOS is
//     exposed in the program window (lower = code, upper = assets; see doc 13).
//   * kEnSafeRom (CONTROL[1]) + safe-ROM base/bounds -- a small ROM range that
//     FRED keeps served from the pass-through game cart even while "Here" is
//     asserted, so a patch can call back into the original game code.
//   * FRED patch redirect -- when the patch engine redirects a game access into
//     an injected subroutine, the access is served from XBAND SRAM at the
//     translated address instead of the cart.
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

    // safe-ROM range (from xband_fred_regs)
    input  logic [23:0]  saferom_base,
    input  logic [23:0]  saferom_bounds,

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
  wire safe_rom_en = (control_reg & CTL_EN_SAFE_ROM) != 8'h00;

  // ---- HiROM region decode -------------------------------------------------
  // SRAM: 64 KB linear at bank $E0, or the $20-$3F:$6000-$7FFF small window.
  wire in_sram_e0  = (bank == SRAM_BANK);
  wire in_sram_win = (bank[7:5] == 3'b001)            // $20-$3F
                   & (off >= 16'h6000) & (off <= 16'h7FFF);
  wire in_sram     = in_sram_e0 | in_sram_win;

  // ROM: $C0-$FF full banks (excluding the SRAM bank), or $00-$3F/$80-$BF
  // upper half ($8000-$FFFF).
  wire in_rom_full = (bank >= 8'hC0) & ~in_sram_e0;
  wire in_rom_half = off[15]
                   & ( (bank <= 8'h3F) | ((bank >= 8'h80) & (bank <= 8'hBF)) );
  wire in_rom_win  = in_rom_full | in_rom_half;

  // FRED register window. NOTE: the exact retail location is still the
  // integration point (the dev kFredBase is a 68k address). Placeholder: a
  // 512-byte window in bank $00 ($5400-$55FF) that does not overlap ROM/SRAM.
  wire in_reg_win  = (bank == 8'h00) & (off[15:9] == 7'h2A);

  // Safe-ROM: while "Here" is asserted, a programmed [base, base+bounds) range
  // is still served from the pass-through game cart (so injected code can call
  // back into the original game). Honoured only inside the ROM window.
  wire [23:0] saferom_off = cpu_addr - saferom_base;
  wire        in_saferom  = safe_rom_en
                          & (cpu_addr >= saferom_base)
                          & (saferom_off < saferom_bounds);

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
    end else if (in_sram) begin
      sel_sram = 1'b1;
    end else if (in_rom_win) begin
      if (here && in_saferom) begin
        // Safe-ROM hole: keep the pass-through game cart visible here.
        sel_game = 1'b1;
      end else if (here) begin
        sel_bios = 1'b1;          // FRED owns the bus -> XBAND BIOS
      end else begin
        sel_game = 1'b1;          // pass-through game cartridge
      end
    end
  end

  // SRAM flat offset (16 bits = 64 KB). A patch redirect supplies the already-
  // translated safe-RAM address; bank $E0 is fully linear; the $6000-$7FFF
  // small window packs {bank[2:0], 13-bit page} so a few banks cover 64 KB.
  always_comb begin
    if (patch_redirect)
      sram_offset = patch_redirect_addr[XBAND_SRAM_ADDR_BITS-1:0];
    else if (in_sram_e0)
      sram_offset = off;                              // $E0:0000-$E0:FFFF
    else
      sram_offset = { bank[2:0], cpu_addr[12:0] };    // banked $6000-$7FFF
  end

  // FRED register byte offset (even-addressed; see xband_pkg).
  assign reg_offset  = off[8:0];

  // BIOS byte address (20 bits = 1 MB, HiROM 512 KB program window). kRomHi is
  // the top bit (selects the 512 KB code half vs. asset half); bank[2:0] give
  // an 8-bank/512 KB window and the full 16-bit offset is HiROM-style.
  assign bios_read      = sel_bios;
  assign bios_read_addr = { rom_hi, bank[2:0], off };

  wire _unused_ok = &{1'b0, clk, rst_n,
                      patch_redirect_addr[23:XBAND_SRAM_ADDR_BITS]};

endmodule

`default_nettype wire
