// =============================================================================
// ss_spike.sv  --  FEASIBILITY SPIKE, not a finished feature.
// =============================================================================
//
// Minimal savestate-bus master for the Pro Action Replay MK3 SNES core. Its only
// purpose is to wire the full Analogue Pocket savestate pipeline end-to-end so
// Quartus can report the resource cost (ALMs/LEs + block-RAM) of the savestate
// infrastructure -- i.e. to answer "does this fit in the FPGA?" before committing
// to the full, multi-chip register serialization.
//
// SCOPE: it serializes ONLY the 64 KB SNES VRAM (vram1 = $0000-$7FFF,
// vram2 = $8000-$FFFF, both block RAM in SNES.sv). It does NOT capture the
// internal flip-flop state of the 65C816 CPU, the SPC700, the PPU, the S-DSP or
// any enhancement chip. A restored state therefore will NOT resume into a running
// machine -- that is expected and fine: the spike measures *fit*, not playability.
//
// PROTOCOL CONTRACT (mirrors save_state_controller.sv, same clk domain):
//   SAVE: on an ss_save pulse, raise ss_busy. For each 64-bit word, drive ss_din
//         then pulse ss_req (1 cycle) and wait for ss_ack. After the last word,
//         drop ss_busy -- the controller sees busy 1->0 and finishes.
//   LOAD: on an ss_load pulse, raise ss_busy. For each 64-bit word, pulse ss_req,
//         wait for ss_ack, and capture ss_dout on the ack cycle. After the last
//         word, drop ss_busy.
//
// ss_addr / ss_rnw / ss_be are ignored by the controller; driven to constants.
//
// Word 0 is a header (magic + version). Words 1..8192 each pack 8 consecutive
// VRAM bytes, little-endian within the 64-bit word:
//   ss_din = { byte[base+7], ..., byte[base+1], byte[base+0] },  base = (word-1)*8
//
// VRAM block RAM read latency: address_reg_b="CLOCK1", outdata_reg_b="UNREGISTERED"
// (see bram.vhd) -> q valid 1-2 cycles after the address is presented. We wait a
// fixed 2 cycles before capturing, which is safe either way.
// =============================================================================

module ss_spike (
    input  wire        clk,            // clk_sys_21_48 (same as VRAM + controller)

    // APF savestate bus (connects to save_state_controller in core_top)
    input  wire        ss_save,        // capture trigger (1-cycle pulse)
    input  wire        ss_load,        // restore trigger (1-cycle pulse)
    output reg         ss_busy,        // high while this master is walking state
    output reg         ss_req,         // 1-cycle "word ready / word wanted" pulse
    input  wire        ss_ack,         // controller consumed (save) / provided (load) a word
    output reg  [63:0] ss_din,         // SAVE: word out to controller
    input  wire [63:0] ss_dout,        // LOAD: word in from controller
    output wire [25:0] ss_addr,        // unused by controller
    output wire        ss_rnw,         // unused by controller
    output wire [7:0]  ss_be,          // unused by controller

    // VRAM port-B tap (muxed onto the vram1/vram2 dpram in SNES.sv)
    output reg  [14:0] ss_vram_addr,   // in-bank byte address
    output reg         ss_vram_sel2,   // 0 = vram1, 1 = vram2
    output reg         ss_vram_wren,   // 1-cycle write strobe (LOAD)
    output reg  [7:0]  ss_vram_wdata,  // write byte (LOAD)
    input  wire [7:0]  vram1_q,        // vram1 port-B read data
    input  wire [7:0]  vram2_q         // vram2 port-B read data
);

  // 64 KB VRAM => 8192 payload words. Index 0 is the header, 1..8192 the payload.
  localparam [13:0] LAST_WORD = 14'd8192;
  localparam [63:0] SS_MAGIC  = 64'h5350_494B_4531_0001;  // "SPIKE1" + version 1

  // The controller ignores these; drive constants so they never float.
  assign ss_addr = 26'd0;
  assign ss_rnw  = 1'b1;
  assign ss_be   = 8'hFF;

  localparam [3:0]
      IDLE        = 4'd0,
      S_ADDR      = 4'd1,   // SAVE: present byte address
      S_WAIT      = 4'd2,   // SAVE: wait out RAM read latency
      S_CAP       = 4'd3,   // SAVE: capture byte into wbuf
      S_REQ_LATCH = 4'd4,   // SAVE: latch assembled word, pulse ss_req
      S_REQ       = 4'd5,   // SAVE: header word path, pulse ss_req
      S_ACK       = 4'd6,   // SAVE: wait for ss_ack
      L_REQ       = 4'd7,   // LOAD: request word, pulse ss_req
      L_ACK       = 4'd8,   // LOAD: wait for ss_ack, latch ss_dout
      L_WR        = 4'd9;   // LOAD: scatter 8 bytes into VRAM

  reg [3:0]  st;
  reg [13:0] word_idx;     // 0..8192
  reg [2:0]  byte_idx;     // 0..7 byte within the current word
  reg [1:0]  wait_cnt;     // RAM read-latency counter
  reg [63:0] wbuf;         // word assembly / disassembly buffer

  reg prev_save, prev_load;

  // Byte address of the current (word,byte). For word_idx 1..8192 the payload
  // base is (word_idx-1)*8; cur_byte spans 0..65535 across both VRAM halves.
  wire [13:0] payload_word = word_idx - 14'd1;            // 0..8191 for word 1..8192
  wire [15:0] base_byte    = {payload_word[12:0], 3'd0};  // payload_word << 3 (16 bits)
  wire [15:0] cur_byte     = base_byte + {13'd0, byte_idx};

  always @(posedge clk) begin
    prev_save <= ss_save;
    prev_load <= ss_load;

    // default deasserts (one-cycle strobes)
    ss_req       <= 1'b0;
    ss_vram_wren <= 1'b0;

    case (st)
      // ----------------------------------------------------------------
      IDLE: begin
        ss_busy  <= 1'b0;
        byte_idx <= 3'd0;
        wait_cnt <= 2'd0;
        if (ss_save && ~prev_save) begin
          ss_busy  <= 1'b1;
          word_idx <= 14'd0;        // emit the header word first
          ss_din   <= SS_MAGIC;
          st       <= S_REQ;
        end else if (ss_load && ~prev_load) begin
          ss_busy  <= 1'b1;
          word_idx <= 14'd0;        // consume (and discard) the header word first
          st       <= L_REQ;
        end
      end

      // ---- SAVE: gather 8 bytes, then hand the word to the controller ----
      S_ADDR: begin
        ss_vram_addr <= cur_byte[14:0];
        ss_vram_sel2 <= cur_byte[15];
        wait_cnt     <= 2'd0;
        st           <= S_WAIT;
      end
      S_WAIT: begin
        if (wait_cnt == 2'd1) st <= S_CAP;   // 2 cycles after address presented
        wait_cnt <= wait_cnt + 2'd1;
      end
      S_CAP: begin
        wbuf[byte_idx*8 +: 8] <= ss_vram_sel2 ? vram2_q : vram1_q;
        if (byte_idx == 3'd7) begin
          byte_idx <= 3'd0;
          st       <= S_REQ_LATCH;
        end else begin
          byte_idx <= byte_idx + 3'd1;
          st       <= S_ADDR;
        end
      end
      S_REQ_LATCH: begin
        // wbuf now holds all 8 bytes (last byte committed this cycle)
        ss_din <= wbuf;
        ss_req <= 1'b1;
        st     <= S_ACK;
      end
      S_REQ: begin
        // header path (ss_din already loaded in IDLE)
        ss_req <= 1'b1;
        st     <= S_ACK;
      end
      S_ACK: begin
        if (ss_ack) begin
          if (word_idx == LAST_WORD) begin
            ss_busy <= 1'b0;
            st      <= IDLE;
          end else begin
            word_idx <= word_idx + 14'd1;
            st       <= S_ADDR;     // gather next payload word
          end
        end
      end

      // ---- LOAD: pull each word, scatter 8 bytes into VRAM ----
      L_REQ: begin
        ss_req <= 1'b1;
        st     <= L_ACK;
      end
      L_ACK: begin
        if (ss_ack) begin
          wbuf <= ss_dout;
          if (word_idx == 14'd0) begin
            // header word: discard, move to first payload word
            word_idx <= 14'd1;
            st       <= L_REQ;
          end else begin
            byte_idx <= 3'd0;
            st       <= L_WR;
          end
        end
      end
      L_WR: begin
        ss_vram_addr  <= cur_byte[14:0];
        ss_vram_sel2  <= cur_byte[15];
        ss_vram_wdata <= wbuf[byte_idx*8 +: 8];
        ss_vram_wren  <= 1'b1;
        if (byte_idx == 3'd7) begin
          byte_idx <= 3'd0;
          if (word_idx == LAST_WORD) begin
            ss_busy <= 1'b0;
            st      <= IDLE;
          end else begin
            word_idx <= word_idx + 14'd1;
            st       <= L_REQ;
          end
        end else begin
          byte_idx <= byte_idx + 3'd1;
        end
      end

      default: st <= IDLE;
    endcase
  end

endmodule
