//----------------------------------------------------------------------------
// xband_fred_regs.sv -- FRED register file (reference skeleton).
//
// Implements the FRED register map from docs/xband/07-fred-register-map.md
// (transcribed from Catapult's Tools/ModemTester/defines.h). Reset values match
// the self-test invariants in fredtest.c. The modem data registers (Tx/Rx FIFO,
// status) are bridged to a PHY-agnostic byte stream so the actual modem can be a
// tunnel to an ESP32 (see docs/xband/12-link-cable-esp32.md).
//
// Reference skeleton -- NOT wired into the Pocket build.
//----------------------------------------------------------------------------
`default_nettype none

module xband_fred_regs
  import xband_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        sel,
    input  logic [8:0]  offset,
    input  logic        wr,
    input  logic [7:0]  wdata,
    output logic [7:0]  rdata,

    // status counters from xband_modem_timing
    input  logic [7:0]  serial_vcnt,
    input  logic [7:0]  mvsync_high,

    // modem byte stream (to/from xband_modem_uart or external tunnel)
    output logic [7:0]  modem_tx_data,
    output logic        modem_tx_valid,
    input  logic        modem_tx_ready,
    input  logic [7:0]  modem_rx_data,
    input  logic        modem_rx_valid,
    output logic        modem_rx_ready,

    output logic [7:0]  leds
);

  // ---- register storage ---------------------------------------------------
  logic [7:0] r_control, r_kill;
  logic [7:0] r_enable_lo, r_enable_hi;
  logic [7:0] r_led_data, r_led_enable;
  logic [7:0] r_vtable_lo, r_vtable_hi;
  logic [7:0] r_range_lo, r_range_mid, r_range_hi;
  logic [7:0] r_trb_lo, r_trb_hi, r_tr_mid;
  logic [7:0] r_addrstat_low;     // diagnostics read-back (no floating bits)

  // ---- write path ---------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_control      <= 8'h00;
      r_kill         <= 8'h00;
      r_enable_lo    <= 8'h00;
      r_enable_hi    <= 8'h00;
      r_led_data     <= RST_LED_DATA;   // 0x7F : 7 LEDs present
      r_led_enable   <= 8'h00;
      r_vtable_lo    <= 8'h00;
      r_vtable_hi    <= 8'h00;
      r_range_lo     <= 8'h00;
      r_range_mid    <= 8'h00;
      r_range_hi     <= 8'h00;
      r_trb_lo       <= 8'h00;
      r_trb_hi       <= 8'h00;
      r_tr_mid       <= 8'h00;
      r_addrstat_low <= RST_ADDRSTAT_LOW; // 0x00
      modem_tx_valid <= 1'b0;
      modem_tx_data  <= 8'h00;
    end else begin
      modem_tx_valid <= 1'b0;   // single-cycle strobe by default
      if (sel && wr) begin
        unique case (offset)
          REG_CONTROL:     r_control    <= wdata;
          REG_KILL:        r_kill       <= wdata;
          REG_ENABLE_LOW:  r_enable_lo  <= wdata;
          REG_ENABLE_HIGH: r_enable_hi  <= wdata;
          REG_LED_DATA:    r_led_data   <= wdata;
          REG_LED_ENABLE:  r_led_enable <= wdata;
          REG_VTABLE_LOW:  r_vtable_lo  <= wdata;
          REG_VTABLE_HIGH: r_vtable_hi  <= wdata;
          REG_RANGE_LOW:   r_range_lo   <= wdata;
          REG_RANGE_MID:   r_range_mid  <= wdata;
          REG_RANGE_HIGH:  r_range_hi   <= wdata;
          REG_TRB_LOW:     r_trb_lo     <= wdata;
          REG_TRB_HIGH:    r_trb_hi     <= wdata;
          REG_TR_MID:      r_tr_mid     <= wdata;
          REG_TXBUFF: begin
            modem_tx_data  <= wdata;       // push to modem FIFO / tunnel
            modem_tx_valid <= 1'b1;
          end
          default: ; // other offsets are read-only or TODO
        endcase
      end
    end
  end

  // ---- read path ----------------------------------------------------------
  // The modem-idle status (kReadMStatus1 == 0x02) and rx-ready come from the
  // PHY; here we synthesise a minimal status: bit1 = idle/ready base value,
  // plus rx_valid in a spare bit. Confirm exact bit layout against the BIOS.
  wire [7:0] read_mstatus1 = RST_READMSTATUS1 | {6'b0, modem_rx_valid, 1'b0};

  always_comb begin
    rdata          = 8'hFF;
    modem_rx_ready = 1'b0;
    if (sel) begin
      unique case (offset)
        REG_CONTROL:      rdata = r_control;
        REG_KILL:         rdata = r_kill;
        REG_ENABLE_LOW:   rdata = r_enable_lo;
        REG_ENABLE_HIGH:  rdata = r_enable_hi;
        REG_LED_DATA:     rdata = r_led_data;
        REG_LED_ENABLE:   rdata = r_led_enable;
        REG_ADDRSTAT_LOW: rdata = r_addrstat_low;
        REG_READMSTATUS1: rdata = read_mstatus1;
        REG_SERIALVCNT:   rdata = serial_vcnt;
        REG_MVSYNC_HIGH:  rdata = mvsync_high;
        REG_RXBUFF: begin
          rdata          = modem_rx_data;  // pop from modem FIFO / tunnel
          modem_rx_ready = 1'b1;
        end
        default:          rdata = 8'h00;
      endcase
    end
  end

  // Front-panel LEDs reflect r_led_data masked by output-enables.
  assign leds = r_led_data & r_led_enable;

endmodule

`default_nettype wire
