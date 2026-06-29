//----------------------------------------------------------------------------
// xband_modem_timing.sv -- video-locked modem bit clock (reference skeleton).
//
// The XBAND modem is NOT clocked by a free-running baud generator: FRED derives
// the modem bit rate from the SNES video timebase. From Catapult's modem code:
//
//   kVCntsPerModemBit = 5    (5 ReadSerialVCnt ticks per modem bit)
//   kLinesPerModemBit = 7    (~7 horizontal lines per modem bit)
//   modem bit period  ~ 1/2400 s (~417 us)
//
// This module reproduces that relationship: it counts video events and emits a
// one-cycle modem_bit_ce, and exposes the running counters the BIOS polls
// (kReadSerialVCnt, kMVSyncHigh). See docs/xband/07-fred-register-map.md and
// docs/xband/11-rtl-architecture.md.
//
// Reference skeleton -- NOT wired into the Pocket build.
//----------------------------------------------------------------------------
`default_nettype none

module xband_modem_timing
  import xband_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,

    input  logic       hsync,        // rising edge = new horizontal line
    input  logic       vsync,        // frame sync
    input  logic       pixel_ce,     // pixel-clock enable (sampling clock)

    output logic [7:0] serial_vcnt,  // kReadSerialVCnt read-back
    output logic [7:0] mvsync_high,  // kMVSyncHigh read-back
    output logic       modem_bit_ce  // one-cycle strobe, one per modem bit
);

  // edge detect on hsync/vsync (sampled in pixel_ce domain)
  logic hsync_d, vsync_d;
  wire  hsync_rise = pixel_ce & hsync & ~hsync_d;
  wire  vsync_rise = pixel_ce & vsync & ~vsync_d;

  logic [3:0] line_cnt;   // counts horizontal lines toward kLinesPerModemBit

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hsync_d      <= 1'b0;
      vsync_d      <= 1'b0;
      line_cnt     <= 4'd0;
      serial_vcnt  <= 8'd0;
      mvsync_high  <= 8'd0;
      modem_bit_ce <= 1'b0;
    end else begin
      if (pixel_ce) begin
        hsync_d <= hsync;
        vsync_d <= vsync;
      end

      modem_bit_ce <= 1'b0;

      // free-running vertical-position counter the BIOS polls
      if (hsync_rise) begin
        serial_vcnt <= serial_vcnt + 8'd1;

        // accumulate lines; one modem bit every kLinesPerModemBit lines
        if (line_cnt == LINES_PER_MODEM_BIT - 1) begin
          line_cnt     <= 4'd0;
          modem_bit_ce <= 1'b1;
        end else begin
          line_cnt <= line_cnt + 4'd1;
        end
      end

      // reset vertical counter each frame; count frames in mvsync_high
      if (vsync_rise) begin
        serial_vcnt <= 8'd0;
        mvsync_high <= mvsync_high + 8'd1;
      end
    end
  end

endmodule

`default_nettype wire
