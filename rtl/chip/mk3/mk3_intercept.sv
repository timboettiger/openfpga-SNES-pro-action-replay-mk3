//----------------------------------------------------------------------------
// mk3_intercept.sv
//
// Cheat-code bus interception. On every CPU instruction or data fetch from
// the cartridge, compares the address against each of the 5 user-controllable
// code slots (slots 0-4). On a match, returns the slot's DTA byte to override
// the cartridge data bus.
//
// Slots 5 and 6 are reserved for the NMI vector hook and handled in
// mk3_nmi_hook.sv, not here.
//
// Slot data format (32 bits, packed):
//   bits  7:0  = DTA byte (the value to substitute on match)
//   bits 31:8  = 24-bit hook address
//
// A slot is active if its address is non-zero (the BIOS zeroes inactive slots).
//
// Priority: slot 0 highest, slot 4 lowest.
//----------------------------------------------------------------------------

module mk3_intercept (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         enable,          // 1 when effective_mode == 1 (Cheats Active)

    input  logic [23:0]  cpu_addr,

    input  logic [31:0]  slot0,
    input  logic [31:0]  slot1,
    input  logic [31:0]  slot2,
    input  logic [31:0]  slot3,
    input  logic [31:0]  slot4,

    output logic         hit,             // 1 if any slot matches
    output logic [7:0]   override_byte    // DTA from highest-priority matching slot
);

    // Pack slots into an array for genvar
    logic [31:0] slots [0:4];
    assign slots[0] = slot0;
    assign slots[1] = slot1;
    assign slots[2] = slot2;
    assign slots[3] = slot3;
    assign slots[4] = slot4;

    // Per-slot comparison: address match AND slot non-zero AND interception enabled
    logic [4:0] match;
    logic [7:0] dta   [0:4];

    genvar i;
    generate
        for (i = 0; i < 5; i++) begin : g_slot
            assign match[i] = enable
                            && (cpu_addr == slots[i][31:8])
                            && (slots[i] != 32'h0);
            assign dta[i]   = slots[i][7:0];
        end
    endgenerate

    // Priority encoder: lowest index wins
    always_comb begin
        hit = |match;
        if      (match[0]) override_byte = dta[0];
        else if (match[1]) override_byte = dta[1];
        else if (match[2]) override_byte = dta[2];
        else if (match[3]) override_byte = dta[3];
        else if (match[4]) override_byte = dta[4];
        else               override_byte = 8'h00;
    end

endmodule
