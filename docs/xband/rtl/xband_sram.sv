//----------------------------------------------------------------------------
// xband_sram.sv -- 64 KB battery-backed SRAM, dual-port (reference skeleton).
//
// Port A: the SNES read/write side (through the FRED-translated bus).
// Port B: an independent save channel that persists the SRAM to a Pocket save
//         slot, exactly like rtl/chip/mk3 persists its 32 KB cheat SRAM via
//         dual-port port B. See docs/xband/08-bios-and-roms.md.
//
// Reference skeleton -- NOT wired into the Pocket build.
//----------------------------------------------------------------------------
`default_nettype none

module xband_sram
  import xband_pkg::*;
#(
    parameter int ADDR_BITS = XBAND_SRAM_ADDR_BITS  // 16 -> 64 KB
)(
    input  logic                 clk,

    // Port A : SNES side
    input  logic [ADDR_BITS-1:0] a_addr,
    input  logic                 a_wr,
    input  logic [7:0]           a_din,
    output logic [7:0]           a_dout,

    // Port B : save/restore channel
    input  logic                 b_wr,
    input  logic [ADDR_BITS-1:0] b_waddr,
    input  logic [7:0]           b_din,
    input  logic                 b_rd,
    input  logic [ADDR_BITS-1:0] b_raddr,
    output logic [7:0]           b_dout
);

  (* ramstyle = "M10K" *) logic [7:0] mem [0:(1<<ADDR_BITS)-1];

  // Port A (read-first behaviour)
  always_ff @(posedge clk) begin
    if (a_wr) mem[a_addr] <= a_din;
    a_dout <= mem[a_addr];
  end

  // Port B (save = read back; restore = write)
  always_ff @(posedge clk) begin
    if (b_wr) mem[b_waddr] <= b_din;
    if (b_rd) b_dout       <= mem[b_raddr];
  end

endmodule

`default_nettype wire
