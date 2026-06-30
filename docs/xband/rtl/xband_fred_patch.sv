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
// What this module implements:
//   * Per-vector table walk (modelled). The vtable entries live in the XBAND
//     SRAM (doc 07/09). When the access falls inside the patched range and a
//     vector is armed, the engine fetches that vector's entry -- a 2-byte
//     little-endian target offset at vtable_base + index*VTABLE_ENTRY_BYTES --
//     over the dedicated SRAM read port, and redirects into the safe-RAM bank
//     at the fetched offset. (Entry width per doc 07; the integration point for
//     a real game patch.)
//   * Trans-address remap: with ktransAddrEnable armed, a contiguous source
//     window beginning at range_base is redirected linearly into tr_base.
//   * Zero-page remap: when kzeroPageEnable is set, $00xx accesses are relocated
//     into the safe-RAM page so the injected code's zero-page variables live in
//     XBAND SRAM.
//   * Safe-RAM containment: range/trans redirects are only produced when the
//     destination lands inside [saferam_base, saferam_base + saferam_bounds).
//
// Priority: zero-page > vector-table walk > trans-address. (Injected code's
// variables must always resolve to SRAM, and an armed vector is a precise
// per-address redirect that wins over the coarse trans-address window.)
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

    // dedicated SRAM read port for the per-vector table walk
    output logic                              vtable_rd,
    output logic [XBAND_SRAM_ADDR_BITS-1:0]   vtable_addr,
    input  logic [7:0]                        vtable_data,

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
  wire [10:0] vectors      = {vectors_hi, vectors_lo};     // Vector10..Vector0
  wire        any_vector   = |vectors;

  // -------------------------------------------------------------------------
  // Source-window test: range_base .. range_base+saferam_bounds. saferam_bounds
  // doubles as the size of the injected-code window (a downloaded patch programs
  // both together).
  // -------------------------------------------------------------------------
  wire [23:0] range_off    = cpu_addr - range_base;
  wire        in_range     = cpu_active
                           & (cpu_addr >= range_base)
                           & (range_off < saferam_bounds);

  // Lowest armed vector index (priority encoder over the 11 enables).
  logic [3:0] vec_index;
  always_comb begin
    vec_index = 4'd0;
    for (int i = XBAND_NUM_VECTORS-1; i >= 0; i--)
      if (vectors[i]) vec_index = i[3:0];
  end

  // -------------------------------------------------------------------------
  // Per-vector table walk: fetch the selected vector's 2-byte target offset
  // from SRAM at vtable_base + index*VTABLE_ENTRY_BYTES. Small fetch FSM; the
  // redirect lags the request by the fetch latency (documented model).
  // -------------------------------------------------------------------------
  wire [XBAND_SRAM_ADDR_BITS-1:0] vtable_entry =
        vtable_base[XBAND_SRAM_ADDR_BITS-1:0]
      + (vec_index * VTABLE_ENTRY_BYTES[3:0]);

  typedef enum logic [2:0] {
    V_IDLE, V_LO_ADDR, V_LO_CAP, V_HI_ADDR, V_HI_CAP, V_DONE
  } vstate_e;
  vstate_e    vstate;
  logic [7:0] vtarget_lo, vtarget_hi;
  logic       vector_active;            // a vector redirect is in effect

  wire        vector_start = in_range & any_vector;
  wire [23:0] vector_dest  = {saferam_base[23:16], vtarget_hi, vtarget_lo};

  // Per-vector table walk FSM. The SRAM read port has 1-cycle latency, so each
  // byte takes an "address" cycle (drive vtable_addr/vtable_rd) followed by a
  // "capture" cycle (sample vtable_data).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      vstate        <= V_IDLE;
      vtable_rd     <= 1'b0;
      vtable_addr   <= '0;
      vtarget_lo    <= 8'h00;
      vtarget_hi    <= 8'h00;
      vector_active <= 1'b0;
    end else begin
      vtable_rd <= 1'b0;
      case (vstate)
        V_IDLE: begin
          vector_active <= 1'b0;
          if (vector_start) begin
            vtable_addr <= vtable_entry;
            vtable_rd   <= 1'b1;
            vstate      <= V_LO_ADDR;
          end
        end
        V_LO_ADDR: begin               // mem[entry] becomes valid next cycle
          vtable_addr <= vtable_entry;
          vtable_rd   <= 1'b1;
          vstate      <= V_LO_CAP;
        end
        V_LO_CAP: begin
          vtarget_lo  <= vtable_data;  // low byte arrived
          vtable_addr <= vtable_entry + 1'b1;
          vtable_rd   <= 1'b1;
          vstate      <= V_HI_ADDR;
        end
        V_HI_ADDR: begin               // mem[entry+1] becomes valid next cycle
          vtable_addr <= vtable_entry + 1'b1;
          vtable_rd   <= 1'b1;
          vstate      <= V_HI_CAP;
        end
        V_HI_CAP: begin
          vtarget_hi    <= vtable_data; // high byte arrived
          vector_active <= 1'b1;
          vstate        <= V_DONE;
        end
        V_DONE: begin
          // Hold the redirect while the access is still in range and armed;
          // otherwise release and re-arm for the next patched access.
          if (!(in_range & any_vector)) begin
            vector_active <= 1'b0;
            vstate        <= V_IDLE;
          end
        end
        default: vstate <= V_IDLE;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // Trans-address remap (coarse, linear): range_base.. -> tr_base.. contained
  // in safe RAM. Only used when ktransAddrEnable is armed.
  // -------------------------------------------------------------------------
  wire [23:0] range_dest   = tr_base + range_off;
  wire [23:0] saferam_off  = range_dest - saferam_base;
  wire        dest_in_sram = (range_dest >= saferam_base)
                           & (saferam_off < saferam_bounds);
  wire        trans_hit    = transaddr_en & in_range & dest_in_sram;

  // -------------------------------------------------------------------------
  // Zero-page remap.
  // -------------------------------------------------------------------------
  wire        zp_hit       = cpu_active & zeropage_en & (cpu_addr[15:8] == 8'h00);
  wire [23:0] zp_dest      = {saferam_base[23:8], cpu_addr[7:0]};

  // -------------------------------------------------------------------------
  // Registered result (priority: zero-page > vector walk > trans-address).
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      redirect      <= 1'b0;
      redirect_addr <= 24'h000000;
    end else if (zp_hit) begin
      redirect      <= 1'b1;
      redirect_addr <= zp_dest;
    end else if (vector_active) begin
      redirect      <= 1'b1;
      redirect_addr <= vector_dest;
    end else if (trans_hit) begin
      redirect      <= 1'b1;
      redirect_addr <= range_dest;
    end else begin
      redirect      <= 1'b0;
      redirect_addr <= cpu_addr;
    end
  end

  wire _unused_ok = &{1'b0, enable_hi[5:3], vtable_base[23:16]};

endmodule

`default_nettype wire
