//----------------------------------------------------------------------------
// xband_fred_patch.sv -- FRED patch engine (behavioural model).
//
// FRED exposes 11 patch vectors (Vector0..VectorA) plus a zero-page remap and a
// trans-address remap, each individually enabled via kEnableLow/kEnableHigh, and
// gated by "safe RAM"/"safe ROM" ranges. A downloaded game patch programs the
// vector table (kVTable*), the source range (kRange*), the destination (kTr*),
// arms the enables, then runs injected subroutines from SRAM. See
// docs/xband/07-fred-register-map.md and docs/xband/09-game-patches.md.
//
// What this module implements (the compare/redirect datapath):
//   * Trans-address / vector remap: a contiguous source window beginning at
//     range_base is redirected into the translation base tr_base while any
//     vector enable (Vector0..VectorA) or ktransAddrEnable is armed. The window
//     size is taken from the safe-RAM bounds (the injected code region), so the
//     redirect offset is the distance from range_base and the destination is
//     tr_base + offset.
//   * Zero-page remap: when kzeroPageEnable is set, accesses to $00xx (zero page
//     within the active bank) are relocated into the safe-RAM page so the
//     injected code's zero-page variables live in XBAND SRAM.
//   * Safe-RAM containment: a redirect is only produced when the destination
//     lands inside [saferam_base, saferam_base + saferam_bounds); otherwise the
//     access passes through to the cartridge unchanged.
//
// The exact retail compare granularity (per-vector table entries held in SRAM,
// safe-ROM interaction) still needs validation against a real BIOS dump and a
// real game patch; this is a faithful model of the documented register
// behaviour and the integration point for that work.
//----------------------------------------------------------------------------
`default_nettype none

module xband_fred_patch
  import xband_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // programmed by xband_fred_regs
    input  logic [7:0]  enable_lo,       // Vector7..Vector0
    input  logic [7:0]  enable_hi,       // zeroPage/transAddr/Vector8..A
    input  logic [23:0] range_base,      // {range_hi,range_mid,range_lo}
    input  logic [23:0] tr_base,         // {trb_hi,tr_mid,trb_lo}
    input  logic [23:0] vtable_base,     // {vtable_hi,vtable_lo,..}
    input  logic [23:0] saferam_base,
    input  logic [23:0] saferam_bounds,

    // game access being decoded
    input  logic [23:0] cpu_addr,
    input  logic        cpu_active,

    // result
    output logic        redirect,        // 1 => use redirect_addr instead of cart
    output logic [23:0] redirect_addr
);

  // -------------------------------------------------------------------------
  // Decode the arming bits from the enable registers (see xband_pkg / doc 07).
  // -------------------------------------------------------------------------
  wire        zeropage_en  = enable_hi[7];                 // ENH_ZEROPAGE  (0x80)
  wire        transaddr_en = enable_hi[6];                 // ENH_TRANSADDR (0x40)
  wire [7:0]  vectors_lo   = enable_lo;                    // Vector7..Vector0
  wire [2:0]  vectors_hi   = enable_hi[2:0];               // VectorA..Vector8
  wire        any_vector   = (|vectors_lo) | (|vectors_hi);

  // The patch is "armed" when any vector or the trans-address remap is enabled.
  wire        range_armed  = any_vector | transaddr_en;

  // -------------------------------------------------------------------------
  // Trans-address / vector remap: range_base .. range_base+saferam_bounds maps
  // to tr_base .. tr_base+saferam_bounds. saferam_bounds doubles as the size of
  // the injected-code window (a downloaded patch programs both together).
  // -------------------------------------------------------------------------
  wire [23:0] range_off    = cpu_addr - range_base;
  wire        in_range     = cpu_active
                           & (cpu_addr >= range_base)
                           & (range_off < saferam_bounds);
  wire [23:0] range_dest   = tr_base + range_off;

  // Destination must land inside safe RAM for the redirect to be honoured.
  wire [23:0] saferam_off  = range_dest - saferam_base;
  wire        dest_in_sram = (range_dest >= saferam_base)
                           & (saferam_off < saferam_bounds);

  wire        range_hit    = range_armed & in_range & dest_in_sram;

  // -------------------------------------------------------------------------
  // Zero-page remap: relocate $00xx into the safe-RAM page. The 256-byte page
  // sits at saferam_base; the low byte indexes within it.
  // -------------------------------------------------------------------------
  wire        zp_hit       = cpu_active & zeropage_en & (cpu_addr[15:8] == 8'h00);
  wire [23:0] zp_dest      = {saferam_base[23:8], cpu_addr[7:0]};

  // -------------------------------------------------------------------------
  // Registered result. Zero-page has priority over the range remap because the
  // injected code's variables must always resolve to SRAM.
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      redirect      <= 1'b0;
      redirect_addr <= 24'h000000;
    end else if (zp_hit) begin
      redirect      <= 1'b1;
      redirect_addr <= zp_dest;
    end else if (range_hit) begin
      redirect      <= 1'b1;
      redirect_addr <= range_dest;
    end else begin
      redirect      <= 1'b0;
      redirect_addr <= cpu_addr;
    end
  end

  // vtable_base is programmed by the patch but its per-vector entries live in
  // SRAM; the SRAM-resident dispatch is reached through range_dest above. Keep
  // the port observed so lint stays clean until the table walk is modelled.
  wire _unused_ok = &{1'b0, vtable_base, enable_hi[5:3]};

endmodule

`default_nettype wire
