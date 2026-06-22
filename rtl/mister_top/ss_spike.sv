// =============================================================================
// ss_spike.sv  --  savestate RAM walker (VRAM + WRAM + ARAM).
// =============================================================================
//
// Serializes the SNES RAM state to/from the APF save_state_controller. Walks a
// flat byte address space and packs 8 consecutive bytes into each 64-bit ss word
// (little-endian within the word); word 0 is a header (magic + version).
//
//   flat byte range      size     backing store         access path
//   -----------------    -------  --------------------  ------------------------
//   0x00000..0x0FFFF      64 KB    VRAM (block RAM)      port B, 1-cycle (clk_sys)
//   0x10000..0x2FFFF     128 KB    WRAM (PSRAM cram0)    ss_psram_dma, bank 0
//   0x30000..0x3FFFF      64 KB    ARAM (PSRAM cram1)    ss_psram_dma, bank 1
//
// The SNES core is frozen (SS_PAUSE) for the whole transfer, so these reads/writes
// see a stopped machine. This still does NOT capture chip registers (CPU/PPU/SMP/
// DSP) -- those come with the register-chain increments -- so a restore is not yet
// a complete machine state. RAM is the bulk of a savestate; registers are next.
//
// Protocol contract (save_state_controller.sv, clk_sys domain):
//   SAVE: on ss_save, raise ss_busy; per word drive ss_din, pulse ss_req, wait
//         ss_ack; after the last word drop ss_busy.
//   LOAD: on ss_load, raise ss_busy; per word pulse ss_req, wait ss_ack, capture
//         ss_dout; after the last word drop ss_busy.
// =============================================================================

module ss_spike #(
    // Register region: REG_BYTES bytes (must be a multiple of 8 so the flat space
    // stays 8-byte aligned). 24 bytes = 192 bits covers the 65C816 architectural
    // registers serialized so far (A/X/Y/SP/D/T/DR/P/PBR/DBR); padded.
    parameter integer REG_BYTES = 24,
    parameter integer REG_BITS  = REG_BYTES * 8
) (
    input  wire        clk,            // clk_sys_21_48

    // APF savestate bus (save_state_controller)
    input  wire        ss_save,
    input  wire        ss_load,
    output reg         ss_busy,
    output reg         ss_req,
    input  wire        ss_ack,
    output reg  [63:0] ss_din,
    input  wire [63:0] ss_dout,
    output wire [25:0] ss_addr,
    output wire        ss_rnw,
    output wire [7:0]  ss_be,

    // VRAM port-B tap (block RAM, muxed in SNES.sv)
    output reg  [14:0] ss_vram_addr,
    output reg         ss_vram_sel2,   // 0 = vram1, 1 = vram2
    output reg         ss_vram_wren,
    output reg  [7:0]  ss_vram_wdata,
    input  wire [7:0]  vram1_q,
    input  wire [7:0]  vram2_q,

    // PSRAM byte DMA handshake (ss_psram_dma, clk_sys side)
    output reg         dma_req,
    output reg         dma_rnw,        // 1 = read, 0 = write
    output reg         dma_bank,       // 0 = WRAM, 1 = ARAM
    output reg  [16:0] dma_addr,       // byte address within the bank
    output reg  [7:0]  dma_wdata,
    input  wire        dma_done,
    input  wire [7:0]  dma_rdata,

    // Chip register state (flat vector; layout defined by the chips). Captured
    // as the last bytes of the flat space. On load, ss_reg_di is filled byte by
    // byte and ss_reg_load pulses once afterwards so the chips latch it (while the
    // core is still paused). clk_sys domain, no CDC.
    input  wire [REG_BITS-1:0] ss_reg_do,
    output reg  [REG_BITS-1:0] ss_reg_di,
    output reg                 ss_reg_load
);

  // Flat byte map (8 bytes per ss word; word 0 is a header):
  //   VRAM 0x00000..0x0FFFF | WRAM 0x10000..0x2FFFF | ARAM 0x30000..0x3FFFF
  //   | chip registers 0x40000..(0x40000+REG_BYTES-1)
  localparam [18:0] VRAM_END  = 19'h10000;  // end of VRAM / start of WRAM
  localparam [18:0] WRAM_END  = 19'h30000;  // end of WRAM / start of ARAM
  localparam [18:0] REG_START = 19'h40000;  // start of the chip-register region
  localparam [15:0] LAST_WORD = 16'h8000 + 16'(REG_BYTES / 8);  // total bytes / 8
  localparam [63:0] SS_MAGIC  = 64'h5350_494B_4533_0001;  // "SPIKE3" + version 1

  // The controller ignores these; drive constants so they never float.
  assign ss_addr = 26'd0;
  assign ss_rnw  = 1'b1;
  assign ss_be   = 8'hFF;

  localparam [3:0]
      IDLE       = 4'd0,
      S_EMIT     = 4'd1,   // SAVE: present word, pulse ss_req
      S_EMIT_ACK = 4'd2,   // SAVE: wait ss_ack
      S_DISP     = 4'd3,   // SAVE: dispatch byte read (VRAM or DMA)
      S_VWAIT    = 4'd4,   // SAVE: VRAM read latency, capture
      S_DWAIT    = 4'd5,   // SAVE: wait DMA read done, capture
      S_DREL     = 4'd6,   // SAVE: release DMA handshake
      S_NEXT     = 4'd7,   // SAVE: next byte / emit word
      L_REQ      = 4'd8,   // LOAD: request word, pulse ss_req
      L_ACK      = 4'd9,   // LOAD: wait ss_ack, capture ss_dout
      L_DISP     = 4'd10,  // LOAD: dispatch byte write (VRAM or DMA)
      L_VWR      = 4'd11,  // LOAD: VRAM write settle
      L_DWAIT    = 4'd12,  // LOAD: wait DMA write done
      L_DREL     = 4'd13,  // LOAD: release DMA handshake
      L_NEXT     = 4'd14;  // LOAD: next byte / pull next word

  reg [3:0]  st;
  reg [15:0] word_idx;     // 0..32768
  reg [2:0]  byte_idx;     // 0..7 within the current word
  reg [1:0]  wait_cnt;     // VRAM read latency
  reg [63:0] wbuf;         // word assembly / disassembly buffer

  reg prev_save, prev_load;

  // Flat byte address of the current (word, byte). Payload words are 1..LAST_WORD,
  // so the byte base is (word_idx-1)*8.
  wire [15:0] payload_word = word_idx - 16'd1;
  wire [18:0] base_byte    = {payload_word, 3'd0};
  wire [18:0] gbyte        = base_byte + {16'd0, byte_idx};

  // Region decode (valid only while gathering/scattering a payload byte)
  wire        in_vram    = gbyte < VRAM_END;
  wire        in_reg     = gbyte >= REG_START;
  wire        in_aram    = (gbyte >= WRAM_END) && (gbyte < REG_START);  // else WRAM
  wire [16:0] local_addr = in_aram ? (gbyte[16:0] - WRAM_END[16:0])
                                   : (gbyte[16:0] - VRAM_END[16:0]);
  wire [4:0]  reg_off    = gbyte[4:0];  // 0..REG_BYTES-1 (REG_START low bits are 0)

  always @(posedge clk) begin
    prev_save <= ss_save;
    prev_load <= ss_load;

    // default one-cycle strobes
    ss_req       <= 1'b0;
    ss_vram_wren <= 1'b0;
    ss_reg_load  <= 1'b0;

    case (st)
      IDLE: begin
        ss_busy  <= 1'b0;
        byte_idx <= 3'd0;
        if (ss_save && ~prev_save) begin
          ss_busy  <= 1'b1;
          word_idx <= 16'd0;          // header word first
          ss_din   <= SS_MAGIC;
          st       <= S_EMIT;
        end else if (ss_load && ~prev_load) begin
          ss_busy  <= 1'b1;
          word_idx <= 16'd0;          // pull & discard header word first
          st       <= L_REQ;
        end
      end

      // ---------------- SAVE ----------------
      S_EMIT: begin
        ss_req <= 1'b1;
        st     <= S_EMIT_ACK;
      end
      S_EMIT_ACK: begin
        if (ss_ack) begin
          if (word_idx == LAST_WORD) begin
            ss_busy <= 1'b0;
            st      <= IDLE;
          end else begin
            word_idx <= word_idx + 16'd1;
            byte_idx <= 3'd0;
            st       <= S_DISP;
          end
        end
      end
      S_DISP: begin
        if (in_vram) begin
          ss_vram_addr <= gbyte[14:0];
          ss_vram_sel2 <= gbyte[15];
          wait_cnt     <= 2'd0;
          st           <= S_VWAIT;
        end else if (in_reg) begin
          // chip register byte: combinational, no wait
          wbuf[byte_idx*8 +: 8] <= ss_reg_do[reg_off*8 +: 8];
          st <= S_NEXT;
        end else begin
          dma_req  <= 1'b1;
          dma_rnw  <= 1'b1;
          dma_bank <= in_aram;
          dma_addr <= local_addr;
          st       <= S_DWAIT;
        end
      end
      S_VWAIT: begin
        if (wait_cnt == 2'd1) begin
          wbuf[byte_idx*8 +: 8] <= ss_vram_sel2 ? vram2_q : vram1_q;
          st <= S_NEXT;
        end
        wait_cnt <= wait_cnt + 2'd1;
      end
      S_DWAIT: begin
        if (dma_done) begin
          wbuf[byte_idx*8 +: 8] <= dma_rdata;
          dma_req <= 1'b0;
          st      <= S_DREL;
        end
      end
      S_DREL: begin
        if (~dma_done) st <= S_NEXT;
      end
      S_NEXT: begin
        if (byte_idx == 3'd7) begin
          ss_din <= wbuf;
          st     <= S_EMIT;          // emit the assembled payload word
        end else begin
          byte_idx <= byte_idx + 3'd1;
          st       <= S_DISP;
        end
      end

      // ---------------- LOAD ----------------
      L_REQ: begin
        ss_req <= 1'b1;
        st     <= L_ACK;
      end
      L_ACK: begin
        if (ss_ack) begin
          wbuf <= ss_dout;
          if (word_idx == 16'd0) begin
            word_idx <= 16'd1;        // discard header, pull first payload word
            st       <= L_REQ;
          end else begin
            byte_idx <= 3'd0;
            st       <= L_DISP;
          end
        end
      end
      L_DISP: begin
        if (in_vram) begin
          ss_vram_addr  <= gbyte[14:0];
          ss_vram_sel2  <= gbyte[15];
          ss_vram_wdata <= wbuf[byte_idx*8 +: 8];
          ss_vram_wren  <= 1'b1;
          st            <= L_VWR;
        end else if (in_reg) begin
          // chip register byte: write into ss_reg_di; after the last byte pulse
          // ss_reg_load so the chips latch the whole vector (core still paused).
          ss_reg_di[reg_off*8 +: 8] <= wbuf[byte_idx*8 +: 8];
          if (reg_off == 5'(REG_BYTES - 1)) ss_reg_load <= 1'b1;
          st <= L_NEXT;
        end else begin
          dma_req   <= 1'b1;
          dma_rnw   <= 1'b0;
          dma_bank  <= in_aram;
          dma_addr  <= local_addr;
          dma_wdata <= wbuf[byte_idx*8 +: 8];
          st        <= L_DWAIT;
        end
      end
      L_VWR: begin
        st <= L_NEXT;
      end
      L_DWAIT: begin
        if (dma_done) begin
          dma_req <= 1'b0;
          st      <= L_DREL;
        end
      end
      L_DREL: begin
        if (~dma_done) st <= L_NEXT;
      end
      L_NEXT: begin
        if (byte_idx == 3'd7) begin
          if (word_idx == LAST_WORD) begin
            ss_busy <= 1'b0;
            st      <= IDLE;
          end else begin
            word_idx <= word_idx + 16'd1;
            st       <= L_REQ;        // pull next payload word
          end
        end else begin
          byte_idx <= byte_idx + 3'd1;
          st       <= L_DISP;
        end
      end

      default: st <= IDLE;
    endcase
  end

endmodule
