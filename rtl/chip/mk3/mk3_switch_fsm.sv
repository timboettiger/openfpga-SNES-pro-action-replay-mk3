//----------------------------------------------------------------------------
// mk3_switch_fsm.sv
//
// Tracks menu vs. game and pulses the soft-reset / Control-B-clear on
// transitions.
//
//   State 0 = MK3_MENU       (power-on default, BIOS / PAR UI)
//   State 1 = CHEATS_ACTIVE  (game running, cheats on)
//   State 2 = NO_CHEATS      (game running, cheats off)
//
// Powers on in MK3_MENU and stays until the BIOS launches the game (Control B,
// control_b_pulse). The Cheats/Trainer toggle does not launch; the mapper
// applies it live. The Pro Action Replay action returns to the menu.
//----------------------------------------------------------------------------

module mk3_switch_fsm #(
    parameter int RESET_HOLD_CYCLES = 256   // ~12 µs @ 21.477 MHz
) (
    input  logic         clk,
    input  logic         rst_n,

    input  logic [1:0]   switch_pos,
    input  logic         par_menu,
    input  logic         control_b_pulse,
    input  logic         game_loaded,

    output logic [1:0]   state,
    output logic         snes_soft_reset,
    output logic         force_control_b,
    output logic         clear_control_b
);

    typedef enum logic [1:0] {
        S_MK3_MENU      = 2'd0,
        S_CHEATS_ACTIVE = 2'd1,
        S_NO_CHEATS     = 2'd2
    } state_t;

    state_t state_r;

    // Hold snes_soft_reset for RESET_HOLD_CYCLES after a return-to-menu so the
    // pulse spans the downstream reset synchronisers.
    localparam int CTR_W = $clog2(RESET_HOLD_CYCLES + 1);
    logic [CTR_W-1:0] reset_counter;

    logic force_cb_r;
    logic clear_cb_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r       <= S_MK3_MENU;
            reset_counter <= '0;
            force_cb_r    <= 1'b0;
            clear_cb_r    <= 1'b0;
        end else begin
            if (|reset_counter) reset_counter <= reset_counter - 1'b1;
            force_cb_r <= 1'b0;
            clear_cb_r <= 1'b0;

            // Pro Action Replay: return to the menu.
            if (par_menu) begin
                if (state_r != S_MK3_MENU) begin
                    state_r       <= S_MK3_MENU;
                    reset_counter <= RESET_HOLD_CYCLES[CTR_W-1:0];
                    clear_cb_r    <= 1'b1;
                end
            end
            // BIOS "Start Game" (Control B set): record in-game state; the
            // mapper switches mode from Control B directly.
            else if (control_b_pulse) begin
                state_r <= (switch_pos == 2'd0) ? S_NO_CHEATS : S_CHEATS_ACTIVE;
            end
        end
    end

    assign state           = state_r;
    assign snes_soft_reset = |reset_counter;
    assign force_control_b = force_cb_r;
    assign clear_control_b = clear_cb_r;

endmodule
