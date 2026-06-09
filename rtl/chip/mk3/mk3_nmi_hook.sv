//----------------------------------------------------------------------------
// mk3_nmi_hook.sv
//
// Substitutes the SNES native-mode NMI vector ($00:FFEA/FFEB) with the MK3
// handler address from slots 5/6 while cheats are active, so the CPU enters
// MK3 code ahead of the game's handler. Only the vector reads are hooked; the
// handler itself lives in MK3 SRAM. The emulation-mode vector ($00:FFFA) is
// not hooked (MK3 enables NMI only in native mode).
//
// This module also tracks whether the CPU is currently *inside* the PAR-NMI
// handler, via the `in_par_nmi` latch. The mapper uses it to open the BIOS
// window at $AE12-$B3F6 only while the handler runs, so the BIOS never
// shadows the game ROM during normal gameplay (see mk3_mapper.sv).
//
//   SET   on the NMI vector low-byte read ($00:FFEA) when the hook is armed:
//         that read is the unambiguous "NMI is dispatching to $AE12" signal.
//   CLEAR on the read of $00:6180, which in the entire handler ($AE12-$B3F6)
//         happens exactly once -- the final `jmp ($6180)` at $B09D that hands
//         control back to the game's own NMI handler. Verified against the
//         BIOS disassembly: $6180 is touched by nothing else in range, and
//         the handler never accesses direct-page $80 (DP base $6100 would
//         alias it to $6180), so this edge is unique and exact.
//----------------------------------------------------------------------------

module mk3_nmi_hook (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         enable,          // 1 when effective_mode == 1 (Cheats Active)

    input  logic [23:0]  cpu_addr,

    input  logic [31:0]  slot5,           // bits 7:0 = NMI handler LSB byte
    input  logic [31:0]  slot6,           // bits 7:0 = NMI handler MSB byte

    output logic         hit,
    output logic [7:0]   override_byte,

    output logic         in_par_nmi       // 1 while the CPU is inside the PAR-NMI handler
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

    // PAR-NMI presence latch. SET wins over CLEAR (they target different
    // addresses, so they never collide, but the priority is explicit anyway).
    logic in_par_nmi_r;
    wire  par_nmi_enter = is_nmi_lo;                     // $00:FFEA read, hook armed
    wire  par_nmi_leave = (cpu_addr == 24'h00_6180);     // final jmp ($6180) at $B09D

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)              in_par_nmi_r <= 1'b0;
        else if (par_nmi_enter)  in_par_nmi_r <= 1'b1;
        else if (par_nmi_leave)  in_par_nmi_r <= 1'b0;
        // Safety net: if the hook is disabled (left Cheats Active), drop the
        // latch so a stale value can't keep the window open.
        else if (!enable)        in_par_nmi_r <= 1'b0;
    end

    assign in_par_nmi = in_par_nmi_r;

endmodule
