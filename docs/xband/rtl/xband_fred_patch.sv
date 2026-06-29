//----------------------------------------------------------------------------
// xband_fred_patch.sv -- FRED patch engine (STUB).
//
// FRED exposes 11 patch vectors (Vector0..VectorA) plus a zero-page remap and a
// trans-address remap, each individually enabled via kEnableLow/kEnableHigh, and
// gated by "safe RAM"/"safe ROM" ranges. A downloaded game patch programs the
// vector table (kVTable*), the source range (kRange*), the destination (kTr*),
// arms the enables, then runs injected subroutines from SRAM. See
// docs/xband/07-fred-register-map.md and docs/xband/09-game-patches.md.
//
// This module is intentionally a STUB: the precise compare/redirect datapath is
// still being reverse-engineered. The interface below is the integration point;
// the body returns "no redirect" so the skeleton elaborates and simulates.
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
  // TODO (reverse-engineering): for each enabled vector, compare cpu_addr
  // against the programmed source range/vector entry and produce the SRAM
  // destination (tr_base + offset). Implement zero-page and trans-address
  // remaps when ENH_ZEROPAGE / ENH_TRANSADDR are set. Honour safe RAM/ROM
  // bounds. Until that datapath is verified against a real patch, pass through.
  // -------------------------------------------------------------------------
  assign redirect      = 1'b0;
  assign redirect_addr = cpu_addr;

  wire _unused_ok = &{1'b0, clk, rst_n, enable_lo, enable_hi, range_base,
                      tr_base, vtable_base, saferam_base, saferam_bounds,
                      cpu_active};

endmodule

`default_nettype wire
