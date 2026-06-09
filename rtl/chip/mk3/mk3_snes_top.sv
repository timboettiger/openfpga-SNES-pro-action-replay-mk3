//----------------------------------------------------------------------------
// mk3_snes_top.sv
//
// Top-level MK3 wrapper: instantiates the MK3 sub-modules and exposes one
// interface to the SNES core. Naming: *_in from the core, *_out to the core,
// bridge_* to/from the Pocket bridge.
//----------------------------------------------------------------------------

module mk3_snes_top (
    input  logic         clk_sys,
    input  logic         rst_n,

    // -----------------------------------------------------------------
    // Pocket bridge interface
    // -----------------------------------------------------------------
    input  logic [1:0]   bridge_switch_pos,    // 0=NoCheats 1=CheatsActive 2=MK3Menu
    input  logic         bridge_par_toggle,    // flips on each "Pro Action Replay" action
    output logic [1:0]   bridge_leds,          // to LED indicator in pause menu
    input  logic         bridge_game_loaded,   // 1 once user has loaded a game

    // BIOS storage is in SDRAM (parent): drive the read address, byte returns
    // on bios_dout next cycle. Load ports unused here.
    input  logic         bios_we,
    input  logic [16:0]  bios_load_addr,
    input  logic [7:0]   bios_load_din,
    input  logic [7:0]   bios_dout,            // BIOS byte for bios_read_addr
    output logic [16:0]  bios_read_addr,       // BIOS read address

    // -----------------------------------------------------------------
    // MK3 SRAM access. The 32 KB mk3_sram block lives in the parent; read byte
    // returns on sram_dout next cycle.
    // -----------------------------------------------------------------
    input  logic [7:0]   sram_dout,            // byte FROM external mk3_sram
    output logic [14:0]  sram_addr,            // 15-bit flat addr (= sram_offset below)
    output logic         sram_ce,              // chip-enable to mk3_sram
    output logic         sram_we_out,          // write strobe
    output logic [7:0]   sram_din,             // byte WE want to write

    // -----------------------------------------------------------------
    // CPU bus snoop (read by mk3_io, mk3_intercept, mk3_nmi_hook,
    // mk3_mapper). Connected to the existing SNES CPU bus.
    // -----------------------------------------------------------------
    input  logic [23:0]  cpu_addr,
    input  logic         cpu_we,
    input  logic [7:0]   cpu_din,

    // SYSCLKF_CE: single-cycle CPU write strobe from the base core. cpu_we is a
    // multi-cycle level, so SRAM writes are qualified with this to commit once
    // per CPU write (matching the base core's SWRAM/BSRAM).
    input  logic         cpu_sysclkf_ce,

    // -----------------------------------------------------------------
    // Cartridge data override, muxed by priority into the base cart path:
    //   nmi_hook > intercept > sel_mk3_bios > sel_mk3_sram > base cart data
    // -----------------------------------------------------------------
    output logic         cart_override_hit,
    output logic [7:0]   cart_override_data,

    // -----------------------------------------------------------------
    // Memory routing: where the base core sources the next cart fetch.
    // -----------------------------------------------------------------
    output logic         sel_mk3_bios,
    output logic         sel_game_rom,
    output logic         sel_mk3_sram,
    output logic [14:0]  sram_offset,
    output logic [16:0]  bios_offset,
    output logic [23:0]  game_offset,

    // -----------------------------------------------------------------
    // Soft reset signal to the SNES CPU (ORed with base reset by main.v)
    // -----------------------------------------------------------------
    output logic         snes_soft_reset,

    // State exports for main.v (region bits + resolved mode).
    output logic [7:0]   dbg_control_a,
    output logic [1:0]   dbg_effective_mode
);

    // -----------------------------------------------------------------
    // Internal nets
    // -----------------------------------------------------------------
    logic [31:0] slot0, slot1, slot2, slot3, slot4, slot5, slot6;
    logic [7:0]  control_a;
    logic        control_b;
    logic [7:0]  control_c;
    logic [7:0]  control_d;
    logic [7:0]  leds;
    logic        control_b_just_set;

    logic        io_hit;
    logic [7:0]  io_dout;

    logic [1:0]  effective_mode;
    logic        intercept_enable, nmi_enable;

    logic        intercept_hit;
    logic [7:0]  intercept_data;
    logic        nmi_hit;
    logic [7:0]  nmi_data;
    logic        in_par_nmi;       // 1 while inside the PAR-NMI handler (from nmi_hook)

    logic        force_cb, clear_cb;
    logic [1:0]  fsm_state;

    // -----------------------------------------------------------------
    // IO register bank. Control B can also be set/cleared by the FSM, so
    // those pulses are applied here in the wrapper (below).
    // -----------------------------------------------------------------
    logic cb_external_set;
    logic cb_external_clear;

    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            cb_external_set   <= 1'b0;
            cb_external_clear <= 1'b0;
        end else begin
            cb_external_set   <= force_cb;
            cb_external_clear <= clear_cb;
        end
    end

    // External set/clear of the sticky Control B bit, applied via a mux on
    // the cpu_din path when the FSM pulses are active.
    logic [7:0] effective_cpu_din;
    logic       effective_cpu_we;
    logic [23:0] effective_cpu_addr;

    always_comb begin
        if (cb_external_set) begin
            effective_cpu_addr = 24'h10003C;
            effective_cpu_we   = 1'b1;
            effective_cpu_din  = 8'h01;
        end
        else if (cb_external_clear) begin
            // Control B is cleared by the soft reset that accompanies
            // clear_cb (it resets mk3_io).
            effective_cpu_addr = cpu_addr;
            effective_cpu_we   = cpu_we;
            effective_cpu_din  = cpu_din;
        end
        else begin
            effective_cpu_addr = cpu_addr;
            effective_cpu_we   = cpu_we;
            effective_cpu_din  = cpu_din;
        end
    end

    mk3_io u_io (
        .clk                (clk_sys),
        .rst_n              (rst_n & ~clear_cb),  // clear by reset path
        .cpu_addr           (effective_cpu_addr),
        .cpu_we             (effective_cpu_we),
        .cpu_din            (effective_cpu_din),
        .cpu_dout           (io_dout),
        .cpu_hit            (io_hit),
        .slot0              (slot0),
        .slot1              (slot1),
        .slot2              (slot2),
        .slot3              (slot3),
        .slot4              (slot4),
        .slot5              (slot5),
        .slot6              (slot6),
        .control_a          (control_a),
        .control_b          (control_b),
        .control_c          (control_c),
        .control_d          (control_d),
        .leds               (leds),
        .control_b_just_set (control_b_just_set)
    );

    // -----------------------------------------------------------------
    // Switch FSM
    // -----------------------------------------------------------------
    // Pro Action Replay: edge-detect the bridge toggle into a 1-cycle pulse.
    logic par_toggle_q;
    logic par_menu_pulse;
    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) par_toggle_q <= 1'b0;
        else        par_toggle_q <= bridge_par_toggle;
    end
    assign par_menu_pulse = bridge_par_toggle ^ par_toggle_q;

    mk3_switch_fsm u_fsm (
        .clk              (clk_sys),
        .rst_n            (rst_n),
        .switch_pos       (bridge_switch_pos),
        .par_menu         (par_menu_pulse),
        .control_b_pulse  (control_b_just_set),
        .game_loaded      (bridge_game_loaded),
        .state            (fsm_state),
        .snes_soft_reset  (snes_soft_reset),
        .force_control_b  (force_cb),
        .clear_control_b  (clear_cb)
    );

    // -----------------------------------------------------------------
    // Memory mapper
    // -----------------------------------------------------------------
    mk3_mapper u_map (
        .clk            (clk_sys),
        .rst_n          (rst_n),
        .switch_pos     (bridge_switch_pos),
        .control_b      (control_b),
        .control_a      (control_a),
        .in_par_nmi     (in_par_nmi),
        .cpu_addr       (cpu_addr),
        .sel_mk3_bios   (sel_mk3_bios),
        .sel_game_rom   (sel_game_rom),
        .sel_mk3_sram   (sel_mk3_sram),
        .sram_offset    (sram_offset),
        .bios_offset    (bios_offset),
        .game_offset    (game_offset),
        .effective_mode (effective_mode)
    );

    // -----------------------------------------------------------------
    // Cheat slot interception (slots 0-4)
    // -----------------------------------------------------------------
    assign intercept_enable = (effective_mode == 2'd1);

    mk3_intercept u_int (
        .clk            (clk_sys),
        .rst_n          (rst_n),
        .enable         (intercept_enable),
        .cpu_addr       (cpu_addr),
        .slot0          (slot0),
        .slot1          (slot1),
        .slot2          (slot2),
        .slot3          (slot3),
        .slot4          (slot4),
        .hit            (intercept_hit),
        .override_byte  (intercept_data)
    );

    // -----------------------------------------------------------------
    // NMI vector hook (slots 5-6)
    // -----------------------------------------------------------------
    assign nmi_enable = (effective_mode == 2'd1);

    mk3_nmi_hook u_nmi (
        .clk            (clk_sys),
        .rst_n          (rst_n),
        .enable         (nmi_enable),
        .cpu_addr       (cpu_addr),
        .slot5          (slot5),
        .slot6          (slot6),
        .hit            (nmi_hit),
        .override_byte  (nmi_data),
        .in_par_nmi     (in_par_nmi)
    );

    // -----------------------------------------------------------------
    // Cartridge override priority (highest first):
    //   nmi_hit > intercept_hit > sel_mk3_bios > sel_mk3_sram > fall through
    // bios_dout / sram_dout arrive registered (1 cycle); sel_mk3_* are
    // combinational on cpu_addr.
    // -----------------------------------------------------------------
    always_comb begin
        if (nmi_hit) begin
            cart_override_hit  = 1'b1;
            cart_override_data = nmi_data;
        end
        else if (intercept_hit) begin
            cart_override_hit  = 1'b1;
            cart_override_data = intercept_data;
        end
        else if (sel_mk3_bios) begin
            cart_override_hit  = 1'b1;
            cart_override_data = bios_dout;
        end
        else if (sel_mk3_sram && !cpu_we) begin
            cart_override_hit  = 1'b1;
            cart_override_data = sram_dout;
        end
        else begin
            cart_override_hit  = 1'b0;
            cart_override_data = 8'h00;
        end
    end

    // -----------------------------------------------------------------
    // BIOS ROM: present the mapper's address; byte returns on bios_dout (SDRAM).
    // -----------------------------------------------------------------
    assign bios_read_addr = bios_offset;

    // -----------------------------------------------------------------
    // MK3 SRAM ports: mapper address, chip-enable in the SRAM region, write
    // strobe gated on CPU write.
    // -----------------------------------------------------------------
    assign sram_addr   = sram_offset;
    assign sram_ce     = sel_mk3_sram;
    // Qualify the write with SYSCLKF_CE: one commit per CPU write.
    assign sram_we_out = sel_mk3_sram & cpu_we & cpu_sysclkf_ce;
    assign sram_din    = cpu_din;

    // -----------------------------------------------------------------
    // LED state to Pocket bridge. mk3_io's `leds` register mirrors writes to
    // $00:61FE (the live group/trainer blink the PAR-NMI engine writes each
    // frame; §20.3 / HW-verified §20.4); $086000 is ignored at runtime
    // because the ROM masks its bit0 with `and #$FE`.
    // -----------------------------------------------------------------
    assign bridge_leds = leds[1:0];

    // -----------------------------------------------------------------
    // State exports to main.v: dbg_control_a (live Control A $10001C, bits
    // [7:6] = force PAL/NTSC) and dbg_effective_mode (resolved mode).
    // -----------------------------------------------------------------
    assign dbg_control_a      = control_a;
    assign dbg_effective_mode = effective_mode;

    // -----------------------------------------------------------------
    // control_c ($206000) and control_d ($008000) are latched in mk3_io but
    // currently unused. The PAR-NMI BIOS window in the mapper is gated by
    // in_par_nmi (from mk3_nmi_hook), which spans the whole handler including
    // the exit tail -- a Control C gate would close the window at $B08B,
    // before the exit finishes. control_c/control_d stay exported for debug /
    // future use.
    wire _unused_ctrl = &{1'b0, control_c, control_d};

endmodule
