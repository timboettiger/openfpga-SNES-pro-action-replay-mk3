//----------------------------------------------------------------------------
// mk3_nmi_hook.sv
//
// Substitutes the SNES native-mode NMI vector ($00:FFEA/FFEB) with the MK3
// handler address from slots 5/6 while cheats are active, so the CPU enters
// MK3 code ahead of the game's handler. Only the vector reads are hooked; the
// handler itself lives in MK3 SRAM. The emulation-mode vector ($00:FFFA) is
// not hooked (MK3 enables NMI only in native mode).
//----------------------------------------------------------------------------

module mk3_nmi_hook (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         enable,          // 1 when effective_mode == 1 (Cheats Active)

    input  logic [23:0]  cpu_addr,

    input  logic [31:0]  slot5,           // bits 7:0 = NMI handler LSB byte
    input  logic [31:0]  slot6,           // bits 7:0 = NMI handler MSB byte

    output logic         hit,
    output logic [7:0]   override_byte
);

    // Slot armed = non-zero. Don't hook the vector for unprogrammed (zero)
    // slots, else the first NMI would jump to $0000.
    logic slot5_armed, slot6_armed;
    assign slot5_armed = (slot5 != 32'h0);
    assign slot6_armed = (slot6 != 32'h0);

    logic is_nmi_lo, is_nmi_hi;

    always_comb begin
        is_nmi_lo = enable && slot5_armed && (cpu_addr == 24'h00_FFEA);
        is_nmi_hi = enable && slot6_armed && (cpu_addr == 24'h00_FFEB);

        hit = is_nmi_lo | is_nmi_hi;
        override_byte = is_nmi_lo ? slot5[7:0] : slot6[7:0];
    end

endmodule
