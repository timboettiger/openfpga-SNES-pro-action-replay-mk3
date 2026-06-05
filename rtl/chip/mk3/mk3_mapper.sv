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
//----------------------------------------------------------------------------

module mk3_mapper (
    input  logic         clk,
    input  logic         rst_n,

    input  logic [1:0]   switch_pos,       // from Pocket bridge: 0=NoCheats 1=CheatsActive 2=MK3Menu
    input  logic         control_b,        // from mk3_io: sticky bit
    input  logic [7:0]   control_a,        // from mk3_io: bit 4 = peek game ROM

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

    logic is_mk3_bios_path;
    logic is_game_path;
    always_comb begin
        if (mode == 2'd0) begin
            // MK3 Menu mode: FastROM always BIOS; LoROM gateable.
            is_mk3_bios_path = is_fastrom_range
                             | (is_lorom_mirror & ~control_a[4]);
            is_game_path     = is_lorom_mirror & control_a[4];
        end else begin
            // game running: all ROM space is game
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
