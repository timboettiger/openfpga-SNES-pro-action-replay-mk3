//----------------------------------------------------------------------------
// mk3_mapper.sv
//
// Selects which storage answers a given CPU address; outputs drive the
// cartridge-bus muxes in SNES.vhd. Modes (from switch + Control B): MK3_MENU
// shows the BIOS, CHEATS_ACTIVE shows the game with interception on, NO_CHEATS
// with it off. LoROM assumed.
//
// Memory map:
//   $00/02/04/06:$6000-$7FFF  -> MK3 SRAM (15-bit offset)
//   $00-$3F:$8000-$FFFF       -> ROM (BIOS or game)
//   $80-$BF:$8000-$FFFF       -> mirror of $00-$3F
//
// PAR-NMI window: in Cheats Active mode the BIOS is also visible at
// $00/$80:AE12-$B3F6 -- the exact byte range the PAR-NMI handler may fetch.
// The MK3 NMI hook redirects the SNES NMI vector to $80:AE12 (slots 5/6 are
// programmed with #$AE12 at $80:912B); the handler then runs its entry, the
// combo decoder ($AE99+), the per-frame LED engine ($AFD0-$B083), the
// NMI exit ($B083-$B09D), and the cheat-apply / trainer-count helpers
// ($B0A0-$B3F6) that the SRAM trampoline re-enters. ROM addresses outside
// this range (below $AE12 or from $B3F7 onward) belong to unrelated routines
// and stay on the game-ROM path.
//
// Gating: window is open whenever the effective mode is Cheats Active. We do
// NOT additionally gate on Control C bit 0, even though that bit nominally
// indicates "BIOS execution": the ROM writes Control C = 1 at $B08B, but
// $B08F-$B09D still need to fetch BIOS (stack pops + final `jmp ($6180)`).
// A Control C gate would close mid-handler and crash on the exit. Leaving
// the window unconditionally open for the 1509-byte slice is the small price
// for a clean PAR-NMI exit; game ROMs that happen to use this range are
// inherently incompatible with the MK3 anyway.
//
// Full rationale and the per-range breakdown live in §8.2 / §19.6 / §20 of
// the action-replay-mk-iii preservaction documentation.
//----------------------------------------------------------------------------

module mk3_mapper (
    input  logic         clk,
    input  logic         rst_n,

    input  logic [1:0]   switch_pos,       // from Pocket bridge: 0=NoCheats 1=CheatsActive 2=MK3Menu
    input  logic         control_b,        // from mk3_io: sticky bit
    input  logic [7:0]   control_a,        // from mk3_io: bit 4 = peek game ROM
    input  logic [7:0]   control_c,        // from mk3_io: bit 0 = BIOS/PAR-NMI vs game execution

    input  logic [23:0]  cpu_addr,

    output logic         sel_mk3_bios,     // 1 = read from MK3 BIOS ROM block
    output logic         sel_game_rom,     // 1 = read from Game ROM block
    output logic         sel_mk3_sram,     // 1 = read/write MK3 SRAM
    output logic [14:0]  sram_offset,      // 15-bit flat offset into 32 KB SRAM
    output logic [16:0]  bios_offset,      // 17-bit flat offset into 128 KB BIOS
    output logic [23:0]  game_offset,      // 24-bit pass-through to base core mapper

    output logic [1:0]   effective_mode    // 0=MK3_MENU 1=CHEATS_ACTIVE 2=NO_CHEATS
);

    // Control B (BIOS game-launch latch) overrides the switch: set = game
    // running (No Cheats / Cheats Active per switch), clear = follow switch.
    logic [1:0] mode;
    always_comb begin
        if (control_b) begin
            // game running
            mode = (switch_pos == 2'd0) ? 2'd2   // No Cheats
                                        : 2'd1;  // Cheats Active
        end else begin
            // idle / menu
            unique case (switch_pos)
                2'd2:    mode = 2'd0;             // MK3 Menu
                2'd1:    mode = 2'd0;             // Cheats Active (pre-launch = menu)
                2'd0:    mode = 2'd0;             // No Cheats     (pre-launch = menu)
                default: mode = 2'd0;
            endcase
        end
    end
    assign effective_mode = mode;

    // SRAM decode: even banks $00/$02/$04/$06, $6000-$7FFF
    logic bank_eligible;
    always_comb begin
        bank_eligible = (cpu_addr[23:19] == 5'b00000) &&     // banks 00-07
                        (cpu_addr[16] == 1'b0);              // even bank only
    end
    logic sram_window;
    assign sram_window = (cpu_addr[15:13] == 3'b011);        // $6000-$7FFF
    assign sel_mk3_sram = bank_eligible && sram_window;

    // 32 KB SRAM paged by bank, not aliased: page = cpu_addr[18:17], in-page
    // offset = cpu_addr[12:0]. The four even banks are distinct 8 KB pages.
    assign sram_offset  = {cpu_addr[18:17], cpu_addr[12:0]};

    // ROM region decode: bit 15 high means $8000-$FFFF region
    logic rom_region;
    assign rom_region = cpu_addr[15];

    // ROM banks split: $80-$BF (FastROM) is always BIOS in menu mode; the
    // $00-$3F LoROM mirror shows game ROM when control_a[4] is set (cart peek).
    wire is_fastrom_range = (cpu_addr[23:22] == 2'b10);   // banks $80-$BF
    wire is_lorom_mirror  = (cpu_addr[23:22] == 2'b00);   // banks $00-$3F

    // PAR-NMI handler window: exact byte range $xx:AE12-$B3F6, in both the
    // LoROM mirror ($00-$3F) and the FastROM image ($80-$BF). Covers the
    // NMI entry ($AE12), the combo decoder ($AE99+), the per-frame LED engine
    // ($AFD0-$B083), the NMI exit ($B083-$B09D, including the Control C = 1
    // write at $B08B), and the cheat-apply / trainer-count helpers that the
    // SRAM trampoline re-enters ($B0A0-$B3F6).
    wire is_nmi_window = (cpu_addr[15:0] >= 16'hAE12)
                       & (cpu_addr[15:0] <= 16'hB3F6);

    logic is_mk3_bios_path;
    logic is_game_path;
    always_comb begin
        if (mode == 2'd0) begin
            // MK3 Menu mode: FastROM always BIOS; LoROM gateable.
            is_mk3_bios_path = is_fastrom_range
                             | (is_lorom_mirror & ~control_a[4]);
            is_game_path     = is_lorom_mirror & control_a[4];
        end else if (mode == 2'd1) begin
            // Cheats Active: game ROM, but the PAR-NMI handler window
            // ($xx:AE12-$B3F6) always shows BIOS. Control C is NOT used as a
            // gate here: the ROM writes Control C = 1 at $B08B, *before* the
            // NMI exit finishes ($B08F-$B09D still need BIOS bytes -- stack
            // pops and the final `jmp ($6180)`). Gating on Control C would
            // close the window mid-routine and the CPU would read game ROM
            // for the last 18 bytes, crashing the handler. Control C stays
            // available to other consumers (debug / future use); leaving the
            // window permanently open in this small range is the price for
            // a clean NMI exit.
            is_mk3_bios_path = is_nmi_window
                             & (is_fastrom_range | is_lorom_mirror);
            is_game_path     = (is_fastrom_range | is_lorom_mirror)
                             & ~is_mk3_bios_path;
        end else begin
            // No Cheats: all ROM space is game.
            is_mk3_bios_path = 1'b0;
            is_game_path     = is_fastrom_range | is_lorom_mirror;
        end
    end
    assign sel_mk3_bios = rom_region && is_mk3_bios_path;
    assign sel_game_rom = rom_region && is_game_path;

    // BIOS offset: LoROM, 4 x 32 KB = 128 KB. bank = cpu_addr[17:16],
    // offset = cpu_addr[14:0].
    assign bios_offset = {cpu_addr[17:16], cpu_addr[14:0]};

    // Game offset: pass through to the base mapper.
    assign game_offset = cpu_addr;

endmodule
