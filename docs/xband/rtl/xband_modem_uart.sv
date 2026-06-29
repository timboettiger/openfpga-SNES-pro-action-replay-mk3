//----------------------------------------------------------------------------
// xband_modem_uart.sv -- byte-stream modem bridge (reference skeleton).
//
// The retail XBAND used a Rockwell V.32bis modem behind FRED. For an FPGA core
// the analog PHY is replaced by a byte tunnel: FRED's Tx/Rx FIFOs are exposed as
// a simple valid/ready byte stream that can be routed to the Pocket Link Port
// (to an ESP32 running the XBAND server protocol over Wi-Fi). See
// docs/xband/12-link-cable-esp32.md.
//
// This module provides the FIFO buffering between the FRED register file and the
// external tunnel. The modem_bit_ce input lets a future implementation pace the
// stream to the authentic 2400-baud-derived rate; the skeleton passes bytes
// through as soon as the tunnel accepts them.
//
// Reference skeleton -- NOT wired into the Pocket build.
//----------------------------------------------------------------------------
`default_nettype none

module xband_modem_uart
  import xband_pkg::*;
#(
    parameter int FIFO_DEPTH = 16
)(
    input  logic       clk,
    input  logic       rst_n,

    input  logic       modem_bit_ce,    // video-locked bit strobe (pacing)

    // FRED side (from xband_fred_regs)
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    output logic [7:0] rx_data,
    output logic       rx_valid,
    input  logic       rx_ready,

    // external tunnel side (e.g. Pocket Link Port <-> ESP32)
    output logic [7:0] phy_tx_data,
    output logic       phy_tx_valid,
    input  logic       phy_tx_ready,
    input  logic [7:0] phy_rx_data,
    input  logic       phy_rx_valid,
    output logic       phy_rx_ready
);

  localparam int AW = $clog2(FIFO_DEPTH);

  // ---- TX FIFO : FRED -> PHY ----------------------------------------------
  logic [7:0] tx_mem [0:FIFO_DEPTH-1];
  logic [AW:0] tx_wptr, tx_rptr;
  wire tx_empty = (tx_wptr == tx_rptr);
  wire tx_full  = (tx_wptr[AW-1:0] == tx_rptr[AW-1:0]) && (tx_wptr[AW] != tx_rptr[AW]);

  assign tx_ready     = ~tx_full;
  assign phy_tx_data  = tx_mem[tx_rptr[AW-1:0]];
  assign phy_tx_valid = ~tx_empty;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_wptr <= '0;
      tx_rptr <= '0;
    end else begin
      if (tx_valid && tx_ready) begin
        tx_mem[tx_wptr[AW-1:0]] <= tx_data;
        tx_wptr <= tx_wptr + 1'b1;
      end
      // pace pops to the modem bit clock so the stream matches the real rate
      if (phy_tx_valid && phy_tx_ready && modem_bit_ce)
        tx_rptr <= tx_rptr + 1'b1;
    end
  end

  // ---- RX FIFO : PHY -> FRED ----------------------------------------------
  logic [7:0] rx_mem [0:FIFO_DEPTH-1];
  logic [AW:0] rx_wptr, rx_rptr;
  wire rx_empty = (rx_wptr == rx_rptr);
  wire rx_full  = (rx_wptr[AW-1:0] == rx_rptr[AW-1:0]) && (rx_wptr[AW] != rx_rptr[AW]);

  assign phy_rx_ready = ~rx_full;
  assign rx_data      = rx_mem[rx_rptr[AW-1:0]];
  assign rx_valid     = ~rx_empty;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_wptr <= '0;
      rx_rptr <= '0;
    end else begin
      if (phy_rx_valid && phy_rx_ready) begin
        rx_mem[rx_wptr[AW-1:0]] <= phy_rx_data;
        rx_wptr <= rx_wptr + 1'b1;
      end
      if (rx_valid && rx_ready)
        rx_rptr <= rx_rptr + 1'b1;
    end
  end

endmodule

`default_nettype wire
