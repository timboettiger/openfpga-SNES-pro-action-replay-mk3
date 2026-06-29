//----------------------------------------------------------------------------
// xband_mapper.sv -- SNES cartridge-address decode for the XBAND add-on.
//
// Selects which storage answers a given CPU address: XBAND BIOS, the pass-
// through game ROM, the 64 KB battery SRAM, or the FRED register window.
// See docs/xband/11-rtl-architecture.md for the (LoROM-style, to-be-confirmed)
// memory map, and docs/xband/07-fred-register-map.md for the register offsets.
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
    end else if (in_sram_win) begin
      sel_sram = 1'b1;
    end else if (in_rom_win) begin
      // TODO: gate BIOS vs. game on FRED control/kill (RomHi, Here, vectors).
      //       For now: BIOS visible (boot), game ROM via FRED patch engine.
      sel_bios = 1'b1;
    end
  end

  // SRAM flat offset (16 bits = 64 KB): {bank[2:0], 13-bit page within window}.
  assign sram_offset = { bank[2:0], cpu_addr[12:0] };

  // FRED register byte offset (even-addressed; see xband_pkg).
  assign reg_offset  = off[8:0];

  // BIOS byte address (20 bits = 1 MB, LoROM-style: {5-bit bank, 15-bit page}).
  assign bios_read      = sel_bios;
  assign bios_read_addr = { bank[4:0], cpu_addr[14:0] };

  wire _unused_ok = &{1'b0, clk, rst_n};

endmodule

`default_nettype wire
