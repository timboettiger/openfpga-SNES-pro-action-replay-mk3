// =============================================================================
// ss_psram_dma.sv  --  savestate byte access to the PSRAM-backed RAMs.
// =============================================================================
//
// WRAM (128 KB, cram0) and ARAM (64 KB, cram1) live in PSRAM on clk_mem_85_9,
// while the savestate walker (ss_spike) runs on clk_sys_21_48. This module is
// the bridge: ss_spike issues a simple clk_sys byte request (read or write) and
// waits for `done`; internally the module crosses into clk_mem, drives the PSRAM
// request/response handshake (busy / read_avail), and crosses the result back.
// All clock-domain crossing is encapsulated here, so ss_spike stays clk_sys-only.
//
// Only valid while the SNES core is paused (SS_PAUSE/ss_busy): SNES.sv muxes this
// module onto the chosen PSRAM and forces the other PSRAM idle.
//
// Handshake (clk_sys): drive rnw/bank/byte_addr/wdata, raise `req`; when `done`
// goes high, `rdata` is valid (for reads); drop `req`; `done` then drops. The
// request inputs must stay stable while `req` is high (they are sampled in the
// clk_mem domain as quasi-static).
//
// PSRAM is 16-bit word addressed with byte enables; a byte read fetches the word
// and selects the half, a byte write uses write_high_byte/write_low_byte.
// =============================================================================

module ss_psram_dma (
    input  wire        clk_sys,
    input  wire        clk_mem,

    // clk_sys request port (ss_spike)
    input  wire        req,         // level: hold high until done observed
    input  wire        rnw,         // 1 = read, 0 = write
    input  wire        bank,        // 0 = WRAM (cram0), 1 = ARAM (cram1)
    input  wire [16:0] byte_addr,   // byte address within the selected bank
    input  wire [ 7:0] wdata,
    output wire        done,        // level (clk_sys): 1 = complete, rdata valid
    output wire [ 7:0] rdata,

    // clk_mem PSRAM port (muxed onto the selected psram in SNES.sv)
    output reg  [15:0] ps_word_addr,
    output reg         ps_rd,
    output reg         ps_wr,
    output reg  [15:0] ps_data_in,
    output reg         ps_whb,      // write high byte
    output reg         ps_wlb,      // write low byte
    input  wire [15:0] ps_data_out,
    input  wire        ps_busy,
    input  wire        ps_read_avail
);

  // --- req: clk_sys -> clk_mem ---
  reg [1:0] req_sync = 0;
  always @(posedge clk_mem) req_sync <= {req_sync[0], req};
  wire req_m = req_sync[1];

  // --- done: clk_mem -> clk_sys ---
  reg m_done = 0;
  reg [1:0] done_sync = 0;
  always @(posedge clk_sys) done_sync <= {done_sync[0], m_done};
  assign done  = done_sync[1];

  // m_rdata is written once (under m_done low) and held while m_done is high, so
  // it is quasi-static across the domain crossing -> safe for clk_sys to sample.
  reg [7:0] m_rdata = 0;
  assign rdata = m_rdata;

  localparam [2:0]
      M_IDLE      = 3'd0,
      M_RD_ISSUED = 3'd1,
      M_RD_WAIT   = 3'd2,
      M_WR_ISSUED = 3'd3,
      M_WR_WAIT   = 3'd4,
      M_DONE      = 3'd5;

  reg [2:0] mstate = M_IDLE;
  reg       m_byte_sel = 0;

  always @(posedge clk_mem) begin
    ps_rd <= 1'b0;
    ps_wr <= 1'b0;

    case (mstate)
      M_IDLE: begin
        m_done <= 1'b0;
        if (req_m && ~ps_busy) begin
          // byte_addr / rnw / bank / wdata are stable while req is held
          ps_word_addr <= byte_addr[16:1];
          m_byte_sel   <= byte_addr[0];
          if (rnw) begin
            ps_rd  <= 1'b1;
            mstate <= M_RD_ISSUED;
          end else begin
            ps_data_in <= {wdata, wdata};
            ps_whb     <= byte_addr[0];
            ps_wlb     <= ~byte_addr[0];
            ps_wr      <= 1'b1;
            mstate     <= M_WR_ISSUED;
          end
        end
      end

      // ---- read ----
      M_RD_ISSUED: begin
        // ps_rd already dropped by the default above; psram latched the request
        mstate <= M_RD_WAIT;
      end
      M_RD_WAIT: begin
        if (ps_read_avail) begin
          m_rdata <= m_byte_sel ? ps_data_out[15:8] : ps_data_out[7:0];
          m_done  <= 1'b1;
          mstate  <= M_DONE;
        end
      end

      // ---- write ----
      M_WR_ISSUED: begin
        // ps_wr dropped; psram is now busy executing the write
        mstate <= M_WR_WAIT;
      end
      M_WR_WAIT: begin
        if (~ps_busy) begin
          m_done <= 1'b1;
          mstate <= M_DONE;
        end
      end

      // ---- complete: hold done until the clk_sys side drops req ----
      M_DONE: begin
        if (~req_m) begin
          m_done <= 1'b0;
          mstate <= M_IDLE;
        end
      end

      default: mstate <= M_IDLE;
    endcase
  end

endmodule
