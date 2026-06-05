//----------------------------------------------------------------------------
// mk3_io.sv
//
// Action Replay MK3 IO register bank. All registers are write-only from the
// SNES CPU; reads return zero (matches real hardware open-bus on those addresses).
// The current register state is exposed to other MK3 modules via output ports.
//
// Register map:
//   $100000-$10001B  Code slots 0-6, 4 bytes each (DTA, ADDR_LO, ADDR_MID, ADDR_HI)
//   $10001C          Control A
//                      bit 4   = enable game ROM read window (BIOS peeks at cart)
//                      bit 6-7 = video region force (01=NTSC, 10=PAL, 00=normal)
//   $10003C          Control B
//                      bit 0   = sticky game-mode latch (write 1, stays set)
//   $206000          Control C
//                      bit 0   = BIOS/PAR-NMI execution vs game execution
//   $008000          Control D (PAR-NMI entry ACK, semantics unclear)
//   $086000          LEDs (bits 0-1 = left/right LED)
//
// Address decode is exact (no mirroring); the SNES CPU writes long-form
// instructions to reach these addresses, so the high byte is always present.
//----------------------------------------------------------------------------

module mk3_io (
    input  logic         clk,
    input  logic         rst_n,

    // CPU bus snoop interface
    input  logic [23:0]  cpu_addr,
    input  logic         cpu_we,           // 1 = CPU is writing this cycle
    input  logic [7:0]   cpu_din,          // CPU's write data
    output logic [7:0]   cpu_dout,         // always 0 (write-only registers)
    output logic         cpu_hit,          // 1 if cpu_addr matches a MK3 IO reg

    // Code slot outputs (packed: byte 0 = DTA, bytes 1-3 = 24-bit address LE)
    output logic [31:0]  slot0,
    output logic [31:0]  slot1,
    output logic [31:0]  slot2,
    output logic [31:0]  slot3,
    output logic [31:0]  slot4,
    output logic [31:0]  slot5,            // reserved: NMI handler LSB byte
    output logic [31:0]  slot6,            // reserved: NMI handler MSB byte

    // Control registers
    output logic [7:0]   control_a,
    output logic         control_b,        // sticky bit 0
    output logic [7:0]   control_c,
    output logic [7:0]   control_d,
    output logic [7:0]   leds,

    // Single-cycle pulse when Control B goes 0 to 1 (BIOS game launch).
    output logic         control_b_just_set
);

    // Internal state
    logic [31:0] slot_r [0:6];
    logic [7:0]  ca_r, cc_r, cd_r, leds_r;
    logic        cb_r;
    logic        cb_pulse;

    // Address decoders (combinational)
    logic is_slot;
    logic is_ca, is_cb, is_cc, is_cd, is_led, is_grp;
    logic [2:0] slot_index;
    logic [1:0] slot_byte;

    always_comb begin
        is_slot = (cpu_addr >= 24'h100000) && (cpu_addr <= 24'h10001B);
        is_ca   = (cpu_addr == 24'h10001C);
        is_cb   = (cpu_addr == 24'h10003C);
        is_cc   = (cpu_addr == 24'h206000);
        is_cd   = (cpu_addr == 24'h008000);
        is_led  = (cpu_addr == 24'h086000);
        // Live LED output ($00:61FE in MK3 SRAM); snooped, not an IO hit.
        is_grp  = (cpu_addr == 24'h0061FE);

        cpu_hit = is_slot | is_ca | is_cb | is_cc | is_cd | is_led;

        // Slot index from address bits [4:2], byte within slot from [1:0]
        slot_index = cpu_addr[4:2];
        slot_byte  = cpu_addr[1:0];
    end

    // Read returns zero (write-only registers, open bus on real HW)
    assign cpu_dout = 8'h00;

    // Register update process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Hard reset clears everything
            for (int i = 0; i < 7; i++) slot_r[i] <= 32'h0;
            ca_r     <= 8'h0;
            cb_r     <= 1'b0;
            cc_r     <= 8'h0;
            cd_r     <= 8'h0;
            leds_r   <= 8'h0;
            cb_pulse <= 1'b0;
        end else begin
            cb_pulse <= 1'b0;  // default low, pulses one cycle on Control B 0->1

            // LED snoop: the live group/trainer blink is at $00:61FE (the
            // $086000 HW reg has bit0 masked at runtime). Mirror it for the
            // overlay; kept out of the IO decode so it never claims cpu_hit.
            if (cpu_we && is_grp) leds_r <= cpu_din;

            if (cpu_we) begin
                if (is_slot) begin
                    // Update byte `slot_byte` of slot `slot_index`
                    case (slot_byte)
                        2'd0: slot_r[slot_index][7:0]   <= cpu_din;
                        2'd1: slot_r[slot_index][15:8]  <= cpu_din;
                        2'd2: slot_r[slot_index][23:16] <= cpu_din;
                        2'd3: slot_r[slot_index][31:24] <= cpu_din;
                    endcase
                end
                else if (is_ca)  ca_r   <= cpu_din;
                else if (is_cb) begin
                    if (cpu_din[0] && !cb_r) begin
                        cb_r     <= 1'b1;
                        cb_pulse <= 1'b1;
                    end
                    // Sticky: once set, cannot be cleared by CPU write.
                    // Only a hard reset or the switch FSM forcing rst_n clears it.
                end
                else if (is_cc)  cc_r   <= cpu_din;
                else if (is_cd)  cd_r   <= cpu_din;
            end
        end
    end

    // Output assignments
    assign slot0   = slot_r[0];
    assign slot1   = slot_r[1];
    assign slot2   = slot_r[2];
    assign slot3   = slot_r[3];
    assign slot4   = slot_r[4];
    assign slot5   = slot_r[5];
    assign slot6   = slot_r[6];
    assign control_a          = ca_r;
    assign control_b          = cb_r;
    assign control_c          = cc_r;
    assign control_d          = cd_r;
    assign leds               = leds_r;
    assign control_b_just_set = cb_pulse;

endmodule
