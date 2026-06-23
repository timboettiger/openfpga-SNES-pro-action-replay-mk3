module main #(
    parameter reg USE_CX4 = 1'b0,
    parameter reg USE_SDD1 = 1'b0,
    parameter reg USE_GSU = 1'b0,
    parameter reg USE_SA1 = 1'b0,
    parameter reg USE_DSPn = 1'b0,
    parameter reg USE_SPC7110 = 1'b0,
    parameter reg USE_BSX = 1'b0,
    parameter reg USE_MSU = 1'b0
) (
    input RESET_N,

    // SPIKE/savestate: when high, freeze the whole SNES (gates the core ENABLE).
    // Clean clock-enable pause: every compute block (CPU/PPU/WRAM/DSP, and SMP
    // via the DSP-generated SMP_CE which is itself ENABLE-gated) stops advancing
    // while registers/RAM hold, so a savestate captures/restores a stopped core.
    input SS_PAUSE,

    // Savestate: aggregated chip register vector pass-through (SNES.vhd <-> ss_spike)
    output [1087:0] SS_REG_DO,
    input  [1087:0] SS_REG_DI,
    input           SS_REG_LOAD,

    input MCLK,
    input ACLK,

    input [ 7:0] ROM_TYPE,
    input [23:0] ROM_MASK,
    input [23:0] RAM_MASK,

    output reg [23:0] ROM_ADDR,
    output reg [15:0] ROM_D,
    input      [15:0] ROM_Q,
    output reg        ROM_CE_N,
    output reg        ROM_OE_N,
    output reg        ROM_WE_N,
    output reg        ROM_WORD,

    output reg [19:0] BSRAM_ADDR,
    output reg [ 7:0] BSRAM_D,
    input      [ 7:0] BSRAM_Q,
    output reg        BSRAM_CE_N,
    output reg        BSRAM_OE_N,
    output reg        BSRAM_WE_N,

    output [16:0] WRAM_ADDR,
    output [ 7:0] WRAM_D,
    input  [ 7:0] WRAM_Q,
    output        WRAM_CE_N,
    output        WRAM_OE_N,
    output        WRAM_WE_N,

    output [15:0] VRAM1_ADDR,
    input  [ 7:0] VRAM1_DI,
    output [ 7:0] VRAM1_DO,
    output        VRAM1_WE_N,
    output [15:0] VRAM2_ADDR,
    input  [ 7:0] VRAM2_DI,
    output [ 7:0] VRAM2_DO,
    output        VRAM2_WE_N,
    output        VRAM_OE_N,

    output [15:0] ARAM_ADDR,
    output [ 7:0] ARAM_D,
    input  [ 7:0] ARAM_Q,
    output        ARAM_CE_N,
    output        ARAM_OE_N,
    output        ARAM_WE_N,

    output GSU_ACTIVE,
    input  GSU_TURBO,

    input        BLEND,
    input        PAL,
    output       HIGH_RES,
    output       FIELD,
    output       INTERLACE,
    output       DOTCLK,
    output [7:0] R,
    output [7:0] G,
    output [7:0] B,
    output       HBLANKn,
    output       VBLANKn,
    output       HSYNC,
    output       VSYNC,

    input  [1:0] JOY1_DI,
    input  [1:0] JOY2_DI,
    output       JOY_STRB,
    output       JOY1_CLK,
    output       JOY2_CLK,
    output       JOY1_P6,
    output       JOY2_P6,
    input        JOY2_P6_in,

    input [64:0] EXT_RTC,

    input          GG_EN,
    input  [128:0] GG_CODE,
    input          GG_RESET,
    output         GG_AVAILABLE,

    input SPC_MODE,

    input [16:0] IO_ADDR,
    input [15:0] IO_DAT,
    input        IO_WR,

    input [4:0] DBG_BG_EN,
    input       DBG_CPU_EN,

    input  TURBO,
    output TURBO_ALLOW,

    output [15:0] MSU_TRACK_NUM,
    output        MSU_TRACK_REQUEST,
    input         MSU_TRACK_MOUNTING,
    input         MSU_TRACK_MISSING,
    output [ 7:0] MSU_VOLUME,
    input         MSU_AUDIO_STOP,
    output        MSU_AUDIO_REPEAT,
    output        MSU_AUDIO_PLAYING,
    output [31:0] MSU_DATA_ADDR,
    input  [ 7:0] MSU_DATA,
    input         MSU_DATA_ACK,
    output        MSU_DATA_SEEK,
    output        MSU_DATA_REQ,
    input         MSU_ENABLE,

    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,

    // PAR MK3 SNES control signals (synchronized in core_top.sv to MCLK domain)
    input  [1:0] MK3_SWITCH_POS,
    input        MK3_PAR_TOGGLE,
    input        MK3_SOFT_RESET_REQ,
    input        MK3_RESET_CORE,         // 1 while the "Reset Core" (0x50) reset window is active
    input        MK3_GAME_LOADED,        // 1 = all required dataslots loaded
    output [1:0] MK3_LEDS,               // {right LED, left LED} status
    output [1:0] MK3_EFF_MODE,           // effective mapper mode (0=Menu,1=Cheats,2=NoCheats)
    output       MK3_EFF_PAL,            // latched region (1=PAL/50Hz, 0=NTSC/60Hz)

    // PAR MK3 BIOS loader interface (driven by core_top.sv asset slot 100 loader)
    input         MK3_BIOS_WE,
    input  [16:0] MK3_BIOS_LOAD_ADDR,
    input  [7:0]  MK3_BIOS_LOAD_DIN,

    // PAR MK3 BIOS read interface. MAIN_SNES redirects the SDRAM read to offset
    // BIOS_BASE (8 MB) when MK3_BIOS_READ is asserted; byte returns on MK3_BIOS_DOUT.
    output        MK3_BIOS_READ,
    output [16:0] MK3_BIOS_READ_ADDR,
    input  [7:0]  MK3_BIOS_DOUT,

    // PAR MK3 second save channel: persists the 32 KB cheat SRAM (Pocket slot 11)
    // via dual-port mk3_sram port B. Independent of port A (SNES cheat-write path).
    input         MK3SV_WR,         // 1 = restoring SRAM (write into port B)
    input         MK3SV_RD,         // 1 = saving SRAM (read back via port B)
    input  [14:0] MK3SV_ADDR_IN,    // restore (write) byte address
    input  [14:0] MK3SV_ADDR_OUT,   // save (read) byte address
    input  [7:0]  MK3SV_DOUT,       // byte to write into SRAM on restore
    output [7:0]  MK3SV_DIN         // SRAM byte read back on save
);

  parameter USE_DLH = 1'b1;

  wire [23:0] CA;
  wire [23:0] CA_RAW;   // PAR MK3: pre-mirror CPU address ($00-$3F:0000-1FFF not remapped to $7E)
  wire        CPURD_N;
  wire        CPUWR_N;
  reg  [ 7:0] DI;
  wire [ 7:0] DO;
  wire        RAMSEL_N;
  wire        ROMSEL_N;
  reg         IRQ_N;
  wire [ 7:0] PA;
  wire        PARD_N;
  wire        PAWR_N;
  wire        SYSCLKF_CE;
  wire        SYSCLKR_CE;
  wire        REFRESH;

  wire [ 5:0] MAP_ACTIVE;

  // PAR MK3 combined reset. SNES is held in reset when any of: base RESET_N,
  // the switch FSM soft-reset pulse (mk3_soft_reset_pulse, declared below), or
  // the Pocket UI soft-reset request (MK3_SOFT_RESET_REQ).
  //
  // MK3_SOFT_RESET_REQ is a short pulse (core_top.sv self-clears it). Too brief
  // to reset the CPU/PPU/APU reset-sync chains, so we edge-detect and stretch it
  // to ~256 MCLK (the switch FSM width).
  reg  [8:0]  mk3_srst_ctr = 9'd0;
  reg         mk3_srst_req_d = 1'b0;
  always @(posedge MCLK or negedge RESET_N) begin
    if (!RESET_N) begin
      mk3_srst_ctr   <= 9'd0;
      mk3_srst_req_d <= 1'b0;
    end else begin
      mk3_srst_req_d <= MK3_SOFT_RESET_REQ;
      // Rising edge arms the stretch counter.
      if (MK3_SOFT_RESET_REQ && !mk3_srst_req_d) begin
        mk3_srst_ctr <= 9'd256;
      end else if (mk3_srst_ctr != 9'd0) begin
        mk3_srst_ctr <= mk3_srst_ctr - 9'd1;
      end
    end
  end
  wire        mk3_soft_reset_stretched = (mk3_srst_ctr != 9'd0);

  wire        mk3_soft_reset_pulse;
  wire        snes_reset_combined = RESET_N & ~(mk3_soft_reset_pulse | mk3_soft_reset_stretched);

  // PAR MK3 runtime PAL/NTSC region override.
  //
  // The MK3 OPTIONS region menu writes control_a[7:6] at game launch ($80=PAL,
  // $40=NTSC, $00=neither). control_a is snooped by mk3_io and exposed here as
  // mk3_control_a_dbg. Priority: bit7 forces PAL, bit6 forces NTSC, neither keeps
  // the boot-time PAL flag.
  //
  // effective_pal feeds the SNES core .pal() input. The PPU consumes PAL
  // combinationally per frame (PPU.vhd ~line 807 picks NTSC 262 / PAL 312 line
  // counts), so flipping it re-times the frame at the next vertical wrap with no
  // reset and no PLL change. SNES.sv's new_vmode reg is unused here.
  //
  // We latch the last real region write because the BIOS reuses control_a for the
  // ROM-peek ($80:A578 header read writes $00/$10 at $80:A59C), which would
  // otherwise clear the region bits a few frames after launch. Falls back to the
  // boot PAL flag until the BIOS sets a region at least once.
  reg eff_region_pal  = 1'b0;
  reg eff_region_seen = 1'b0;
  always @(posedge MCLK) begin
    if (mk3_control_a_dbg[7]) begin
      eff_region_pal  <= 1'b1;   // PAL  selected
      eff_region_seen <= 1'b1;
    end else if (mk3_control_a_dbg[6]) begin
      eff_region_pal  <= 1'b0;   // NTSC selected
      eff_region_seen <= 1'b1;
    end
    // control_a $00/$10 (peek/clear): hold the latched region, don't revert.
  end
  wire effective_pal = eff_region_seen ? eff_region_pal : PAL;

  // Expose region + mapper mode to MAIN_SNES for the LED overlay gate + P/N
  // indicator, and via MAIN_SNES to core_top for the menu read-back.
  assign MK3_EFF_PAL  = effective_pal;
  assign MK3_EFF_MODE = mk3_eff_mode_dbg;

  SNES SNES (
      .mclk  (MCLK),
      .dspclk(ACLK),

      .rst_n (snes_reset_combined),
      .enable(~SS_PAUSE),  // savestate: hold the whole core while ss_busy

      .ca(CA),
      .ca_raw(CA_RAW),
      .cpurd_n(CPURD_N),
      .cpuwr_n(CPUWR_N),

      .pa(PA),
      .pard_n(PARD_N),
      .pawr_n(PAWR_N),
      .di(DI),
      .do(DO),

      .ramsel_n(RAMSEL_N),
      .romsel_n(ROMSEL_N),

      .sysclkf_ce(SYSCLKF_CE),
      .sysclkr_ce(SYSCLKR_CE),

      .refresh(REFRESH),

      .irq_n(IRQ_N),

      .wsram_addr(WRAM_ADDR),
      .wsram_d(WRAM_D),
      .wsram_q(WRAM_Q),
      .wsram_ce_n(WRAM_CE_N),
      .wsram_oe_n(WRAM_OE_N),
      .wsram_we_n(WRAM_WE_N),

      .vram_addra(VRAM1_ADDR),
      .vram_addrb(VRAM2_ADDR),
      .vram_dai  (VRAM1_DI),
      .vram_dbi  (VRAM2_DI),
      .vram_dao  (VRAM1_DO),
      .vram_dbo  (VRAM2_DO),
      .vram_rd_n (VRAM_OE_N),
      .vram_wra_n(VRAM1_WE_N),
      .vram_wrb_n(VRAM2_WE_N),

      .aram_addr(ARAM_ADDR),
      .aram_d(ARAM_D),
      .aram_q(ARAM_Q),
      .aram_ce_n(ARAM_CE_N),
      .aram_oe_n(ARAM_OE_N),
      .aram_we_n(ARAM_WE_N),

      .joy1_di(JOY1_DI),
      .joy2_di(JOY2_DI),
      .joy_strb(JOY_STRB),
      .joy1_clk(JOY1_CLK),
      .joy2_clk(JOY2_CLK),
      .joy1_p6(JOY1_P6),
      .joy2_p6(JOY2_P6),
      .joy2_p6_in(JOY2_P6_in),

      .blend(BLEND),
      .pal(effective_pal),   // PAR MK3 runtime region override
      .high_res(HIGH_RES),
      .field_out(FIELD),
      .interlace(INTERLACE),
      .dotclk(DOTCLK),

      .rgb_out({B, G, R}),
      .hde(HBLANKn),
      .vde(VBLANKn),
      .hsync(HSYNC),
      .vsync(VSYNC),

      .gg_en(GG_EN),
      .gg_code(GG_CODE),
      .gg_reset(GG_RESET),
      .gg_available(GG_AVAILABLE),

      .spc_mode(SPC_MODE),

      .io_addr(IO_ADDR),
      .io_dat (IO_DAT),
      .io_wr  (IO_WR),

      .DBG_BG_EN (DBG_BG_EN),
      .DBG_CPU_EN(DBG_CPU_EN),

      .turbo(TURBO),

      .audio_l(AUDIO_L),
      .audio_r(AUDIO_R),

      .ss_reg_do(SS_REG_DO),
      .ss_reg_di(SS_REG_DI),
      .ss_reg_load(SS_REG_LOAD)
  );

  // PAR MK3 SNES wrapper instantiation.
  // Bridge path: Pocket UI bridge_wr, core_top mk3_switch_pos, synch_3 to clk_sys,
  // MAIN_SNES, main.v MK3_SWITCH_POS, then mk3_snes_top here.
  //
  // PAR MK3 BIOS, addressed via SDRAM (see below).
  // Write port: asset slot 100 loader in core_top.sv feeds the MK3_BIOS_* ports
  // through MAIN_SNES. Read port: mk3_snes_top's bios_read_addr; byte returns one
  // cycle later on bios_dout.
  wire [16:0] mk3_bios_read_addr;
  wire [7:0]  mk3_bios_dout = MK3_BIOS_DOUT;
  // sel_mk3_bios from mk3_snes_top flags a BIOS read; forward it up as
  // MK3_BIOS_READ so MAIN_SNES can drive the SDRAM port.
  wire        mk3_sel_mk3_bios_out;
  assign      MK3_BIOS_READ      = mk3_sel_mk3_bios_out;
  assign      MK3_BIOS_READ_ADDR = mk3_bios_read_addr;

  // MK3 cart-data override; wins over every chip's _DO selection. Driven
  // combinationally by mk3_snes_top, priority nmi_hook > intercept > sel_mk3_bios
  // > sel_mk3_sram > fall-through. Handles cheats, NMI redirect, BIOS and SRAM reads.
  wire        mk3_cart_override_hit;
  wire [7:0]  mk3_cart_override_data;

  // MK3 SRAM (32 KB block-RAM, emulates the HY62256A on the original MK3 PCB).
  // Kept in main.v so the cart-data path can reach it independently of mk3_snes_top.
  wire [14:0] mk3_sram_addr;
  wire        mk3_sram_ce;
  wire        mk3_sram_we;
  wire [7:0]  mk3_sram_din;
  wire [7:0]  mk3_sram_dout;

  // Port B = Pocket save engine (slot 11). One address bus: write address while
  // restoring (MK3SV_WR), read address while saving. Independent of port A, so
  // simultaneous save-read + cheat-write is safe.
  wire [14:0] mk3_sram_sv_addr = MK3SV_WR ? MK3SV_ADDR_IN : MK3SV_ADDR_OUT;

  // Restore the saved 32 KB image verbatim. The $ABCD warm-boot cookie is stamped
  // into the image only after the BIOS cold-init runs (see the stamper below), so
  // a valid save already carries it; injecting it on restore would warm-boot an
  // uninitialised, all-zero list.
  wire [7:0] mk3_sram_sv_din = MK3SV_DOUT;

  // MK3SV_RD (save-engine read strobe) is unused: port B presents sv_q every
  // cycle with no read-enable. Kept on the interface for symmetry; tie it off.
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_mk3sv_rd = MK3SV_RD;
  /* verilator lint_on UNUSEDSIGNAL */

  mk3_sram u_mk3_sram (
      .clk  (MCLK),
      .rst_n(RESET_N),
      // Port A: SNES cartridge bus (unregistered async read)
      .ce   (mk3_sram_ce),
      .we   (mk3_sram_we),
      .addr (mk3_sram_addr),
      .din  (mk3_sram_din),
      .dout (mk3_sram_dout),
      // Port B: shared by the Pocket save/restore engine and the warm-boot cookie
      // stamper. Save engine has priority; when idle the stamper writes $ABCD into $6194.
      .sv_addr(mk3_pb_addr),
      .sv_din (mk3_pb_din),
      .sv_wren(mk3_pb_wren),
      .sv_q   (MK3SV_DIN)
  );

  // Warm-boot cookie stamper (event-based persistence).
  // The MK3 BIOS keeps the $6300 parameter list across boots only if DP $94
  // ($6194) == $ABCD; otherwise the cold path ($80:90B2) zeroes the list. That
  // cookie is written only by the factory self-test ($80:9668), so without help
  // every boot is cold.
  //
  // We stamp $6194=$ABCD so the save carries it, but not before the BIOS runs its
  // cold/warm check ($80:8247) and cold-init ($80:90B2), else it warm-boots an
  // uninitialised list. A fixed timer can't guarantee the ordering (the 128 KB
  // BIOS + ROM stream delays boot unpredictably), so trigger on the BIOS writing
  // the list: $90B2 fills the 100x7-byte records at $6300..$65BB (flat offset
  // $0300..$05BB), which happens only after $8247. Stamp once per boot when the
  // save engine is idle. A genuine warm boot skips $90B2, so no list write and no
  // re-stamp. Re-arms on every reset; port A is untouched.
  reg [2:0]  magic_st;            // 0 wait-reset, 1 armed, 2 write $194, 3 write $195, 4 done
  reg        magic_we;
  reg [14:0] magic_addr;
  reg [7:0]  magic_din;
  wire       sv_busy    = MK3SV_WR | MK3SV_RD;
  // CPU write into the cheat-list region means $90B2 ran (or the user edited a
  // cheat). Either way the list is real, so it's safe to mark the image warm-bootable.
  wire       list_write = mk3_sram_ce & mk3_sram_we &
                          (mk3_sram_addr >= 15'h0300) & (mk3_sram_addr <= 15'h05BB);
  always @(posedge MCLK) begin
    magic_we <= 1'b0;
    case (magic_st)
      3'd0: if (RESET_N)    magic_st <= 3'd1;       // arm once the SNES leaves reset
      3'd1: if (list_write) magic_st <= 3'd2;       // list got written
      3'd2: if (~sv_busy) begin magic_addr <= 15'h0194; magic_din <= 8'hCD; magic_we <= 1'b1; magic_st <= 3'd3; end
      3'd3: if (~sv_busy) begin magic_addr <= 15'h0195; magic_din <= 8'hAB; magic_we <= 1'b1; magic_st <= 3'd4; end
      3'd4: if (~RESET_N)   magic_st <= 3'd0;        // re-arm after reset
      default: magic_st <= 3'd0;
    endcase
  end

  // Port-B arbitration: save engine wins; otherwise the cookie stamper drives it.
  wire        mk3_pb_wren = sv_busy ? MK3SV_WR        : magic_we;
  wire [14:0] mk3_pb_addr = sv_busy ? mk3_sram_sv_addr: magic_addr;
  wire [7:0]  mk3_pb_din  = sv_busy ? mk3_sram_sv_din : magic_din;

  // Warm-boot read override.
  // The cold path $80:90B2 wipes the $6300 list and is gated by the $6194 cookie
  // ($8247/$813D/$81B6 all do lda $94 / cmp #$ABCD). Relying on the cookie
  // surviving in the saved image proved unreliable on HW. So once a real save has
  // been restored this power-cycle, force the CPU read of $6194/$6195 to $CD/$AB
  // (little-endian $ABCD); the BIOS then always takes the warm path.
  //
  // $94 is only read at the cookie checks, so overriding its read is safe. Only
  // the CPU read port (sram_dout) is overridden; the save read-back (port B) is
  // untouched. A first-ever boot with no save is not overridden.
  reg mk3_save_restored = 1'b0;
  always @(posedge MCLK)
    if (MK3SV_WR & (MK3SV_DOUT != 8'h00)) mk3_save_restored <= 1'b1;

  // "Reset Core" forces a cold boot (fresh cheat list).
  // The user-facing "Reset Core" action (bridge $50) holds MK3_RESET_CORE high
  // for its reset window. While a cold boot is pending we override the cookie
  // read the OTHER way -- $6194/$6195 read as $00 (!= $ABCD) -- so the BIOS
  // takes the cold path ($80:90B2) and wipes the $6300 list itself, exactly
  // like a factory-fresh cartridge. This beats the warm override above.
  //
  // Latched, not a pulse: MK3_RESET_CORE is asserted while the SNES is held in
  // reset (no list_write possible then); the latch persists through the BIOS
  // re-boot until $90B2 runs and writes the list region (list_write), which is
  // the same event the stamper keys off. Once cleared, the stamper re-stamps
  // $ABCD into the now-empty list, so the cleared state persists as warm-boot.
  reg mk3_force_cold = 1'b0;
  always @(posedge MCLK) begin
    if (MK3_RESET_CORE)  mk3_force_cold <= 1'b1;   // Reset Core pressed -> arm cold boot
    else if (list_write) mk3_force_cold <= 1'b0;   // BIOS cold-init ran, list wiped
  end

  wire [7:0] mk3_sram_dout_eff =
      (mk3_force_cold    & mk3_sram_ce & (mk3_sram_addr == 15'h0194)) ? 8'h00 :
      (mk3_force_cold    & mk3_sram_ce & (mk3_sram_addr == 15'h0195)) ? 8'h00 :
      (mk3_save_restored & mk3_sram_ce & (mk3_sram_addr == 15'h0194)) ? 8'hCD :
      (mk3_save_restored & mk3_sram_ce & (mk3_sram_addr == 15'h0195)) ? 8'hAB :
      mk3_sram_dout;

  // BIOS lives in SDRAM, addressed via MK3_BIOS_READ / MK3_BIOS_READ_ADDR up to
  // MAIN_SNES, byte back on MK3_BIOS_DOUT. MK3_BIOS_WE / MK3_BIOS_LOAD_* flow in
  // from the core_top.sv asset slot 100 loader and propagate up through MAIN_SNES.

  /* verilator lint_off PINMISSING */
  mk3_snes_top u_mk3_snes_top (
      .clk_sys           (MCLK),
      .rst_n             (RESET_N),

      .bridge_switch_pos (MK3_SWITCH_POS),  // from Pocket bridge via MAIN_SNES
      .bridge_par_toggle (MK3_PAR_TOGGLE),  // "Pro Action Replay" action toggle bit
      .bridge_leds       (MK3_LEDS),        // out to core_top.sv bridge_rd 0x308
      .bridge_game_loaded(MK3_GAME_LOADED), // dataslot_allcomplete

      // mk3_snes_top's own bios_we/load_* inputs are unused: the asset loader
      // writes the SDRAM BIOS directly. We only feed the read result back so the
      // wrapper's internal mapper sees the BIOS bytes.
      .bios_we           (1'b0),
      .bios_load_addr    (17'd0),
      .bios_load_din     (8'd0),
      .bios_dout         (mk3_bios_dout),         // from the SDRAM BIOS
      .bios_read_addr    (mk3_bios_read_addr),    // to the SDRAM BIOS

      .sram_dout         (mk3_sram_dout_eff),     // from u_mk3_sram (+ warm-boot $6194 read override)
      .sram_addr         (mk3_sram_addr),         // to u_mk3_sram
      .sram_ce           (mk3_sram_ce),
      .sram_we_out       (mk3_sram_we),
      .sram_din          (mk3_sram_din),

      // Use the pre-mirror address. The MK3 IO registers live at bank $10
      // ($10001C control-A, $100000-1B cheat slots), which the SNES core remaps to
      // WRAM $7E:00xx (CPU.vhd:407) before CA. The real PCB sees the un-mirrored
      // edge-connector address, so snoop CA_RAW. CA_RAW == CA except in
      // $00-$3F:0000-1FFF, which the MK3 mapper never decodes for SRAM/ROM.
      .cpu_addr          (CA_RAW),
      .cpu_we            (~CPUWR_N),        // active-high from active-low strobe
      .cpu_din           (DO),
      .cpu_sysclkf_ce    (SYSCLKF_CE),      // single-cycle write-commit strobe

      .cart_override_hit (mk3_cart_override_hit),    // DI mux at end of module
      .cart_override_data(mk3_cart_override_data),
      .sel_mk3_bios      (mk3_sel_mk3_bios_out),     // MAIN_SNES SDRAM mux trigger
      .sel_game_rom      (),                          //  (unused)
      .sel_mk3_sram      (),                          //  (cart_override folds it in)
      .sram_offset       (),
      .bios_offset       (),
      .game_offset       (),
      .dbg_control_a     (mk3_control_a_dbg),        // region latch (load-bearing)
      .dbg_effective_mode(mk3_eff_mode_dbg),         // mode read-back (load-bearing)

      .snes_soft_reset   (mk3_soft_reset_pulse)   // OR'd into snes_reset_combined above
  );
  wire [7:0]  mk3_control_a_dbg;
  wire [1:0]  mk3_eff_mode_dbg;

  /* verilator lint_on PINMISSING */

  wire [7:0] MSU_DO;
  wire       MSU_SEL;

  generate
    if (USE_MSU == 1'b1) begin
      MSU MSU (
          .CLK(MCLK),
          .RST_N(RESET_N),
          .ENABLE(MSU_ENABLE),

          .RD_N(CPURD_N),
          .WR_N(CPUWR_N),
          .SYSCLKF_CE(SYSCLKF_CE),

          .ADDR(CA),
          .DIN(DO),
          .DOUT(MSU_DO),
          .MSU_SEL(MSU_SEL),

          .data_addr(MSU_DATA_ADDR),
          .data(MSU_DATA),
          .data_ack(MSU_DATA_ACK),
          .data_seek(MSU_DATA_SEEK),
          .data_req(MSU_DATA_REQ),

          .track_num(MSU_TRACK_NUM),
          .track_request(MSU_TRACK_REQUEST),
          .track_mounting(MSU_TRACK_MOUNTING),

          .status_track_missing(MSU_TRACK_MISSING),
          .status_audio_repeat(MSU_AUDIO_REPEAT),
          .status_audio_playing(MSU_AUDIO_PLAYING),
          .audio_stop(MSU_AUDIO_STOP),

          .volume(MSU_VOLUME)
      );
    end else begin
      assign MSU_DO = 0;
      assign MSU_SEL = 0;
      assign MSU_TRACK_NUM = 0;
      assign MSU_TRACK_REQUEST = 0;
      assign MSU_VOLUME = 0;
      assign MSU_AUDIO_REPEAT = 0;
      assign MSU_AUDIO_PLAYING = 0;
    end
  endgenerate

  wire [ 7:0] DLH_DO;
  wire        DLH_IRQ_N;
  wire [23:0] DLH_ROM_ADDR;
  wire        DLH_ROM_CE_N;
  wire        DLH_ROM_OE_N;
  wire        DLH_ROM_WORD;
  wire [19:0] DLH_BSRAM_ADDR;
  wire [ 7:0] DLH_BSRAM_D;
  wire        DLH_BSRAM_CE_N;
  wire        DLH_BSRAM_OE_N;
  wire        DLH_BSRAM_WE_N;

  generate
    if (USE_DLH == 1'b1) begin

      DSP_LHRomMap #(
          .USE_DSPn(USE_DSPn)
      ) DSP_LHRomMap (
          .mclk (MCLK),
          .rst_n(RESET_N),

          .ca(CA),
          .di(DO),
          .do(DLH_DO),
          .cpurd_n(CPURD_N),
          .cpuwr_n(CPUWR_N),

          .pa(PA),
          .pard_n(PARD_N),
          .pawr_n(PAWR_N),

          .romsel_n(ROMSEL_N),
          .ramsel_n(RAMSEL_N),

          .sysclkf_ce(SYSCLKF_CE),
          .sysclkr_ce(SYSCLKR_CE),
          .refresh(REFRESH),

          .irq_n(DLH_IRQ_N),

          .rom_addr(DLH_ROM_ADDR),
          .rom_q(ROM_Q),
          .rom_ce_n(DLH_ROM_CE_N),
          .rom_oe_n(DLH_ROM_OE_N),
          .rom_word(DLH_ROM_WORD),

          .bsram_addr(DLH_BSRAM_ADDR),
          .bsram_d(DLH_BSRAM_D),
          .bsram_q(BSRAM_Q),
          .bsram_ce_n(DLH_BSRAM_CE_N),
          .bsram_oe_n(DLH_BSRAM_OE_N),
          .bsram_we_n(DLH_BSRAM_WE_N),

          .map_ctrl  (ROM_TYPE),
          .rom_mask  (ROM_MASK),
          .bsram_mask(RAM_MASK),

          .ext_rtc(EXT_RTC)
      );
    end else begin
      assign DLH_DO = 0;
      assign DLH_IRQ_N = 1;
      assign DLH_ROM_ADDR = 0;
      assign DLH_ROM_CE_N = 1;
      assign DLH_ROM_OE_N = 1;
      assign DLH_BSRAM_ADDR = 0;
      assign DLH_BSRAM_D = 0;
      assign DLH_BSRAM_CE_N = 1;
      assign DLH_BSRAM_OE_N = 1;
      assign DLH_BSRAM_WE_N = 1;
      assign DLH_ROM_WORD = 0;
    end
  endgenerate

  wire [ 7:0] CX4_DO;
  wire        CX4_IRQ_N;
  wire [22:0] CX4_ROM_ADDR;
  wire        CX4_ROM_CE_N;
  wire        CX4_ROM_OE_N;
  wire        CX4_ROM_WORD;
  wire [19:0] CX4_BSRAM_ADDR;
  wire [ 7:0] CX4_BSRAM_D;
  wire        CX4_BSRAM_CE_N;
  wire        CX4_BSRAM_OE_N;
  wire        CX4_BSRAM_WE_N;

  generate
    if (USE_CX4 == 1'b1) begin

      CX4Map CX4Map (
          .mclk (MCLK),
          .rst_n(RESET_N),

          .ca(CA),
          .di(DO),
          .do(CX4_DO),
          .cpurd_n(CPURD_N),
          .cpuwr_n(CPUWR_N),

          .pa(PA),
          .pard_n(PARD_N),
          .pawr_n(PAWR_N),

          .romsel_n(ROMSEL_N),
          .ramsel_n(RAMSEL_N),

          .sysclkf_ce(SYSCLKF_CE),
          .sysclkr_ce(SYSCLKR_CE),
          .refresh(REFRESH),

          .irq_n(CX4_IRQ_N),

          .rom_addr(CX4_ROM_ADDR),
          .rom_q(ROM_Q),
          .rom_ce_n(CX4_ROM_CE_N),
          .rom_oe_n(CX4_ROM_OE_N),
          .rom_word(CX4_ROM_WORD),

          .bsram_addr(CX4_BSRAM_ADDR),
          .bsram_d(CX4_BSRAM_D),
          .bsram_q(BSRAM_Q),
          .bsram_ce_n(CX4_BSRAM_CE_N),
          .bsram_oe_n(CX4_BSRAM_OE_N),
          .bsram_we_n(CX4_BSRAM_WE_N),

          .map_active(MAP_ACTIVE[0]),
          .map_ctrl  (ROM_TYPE),
          .rom_mask  (ROM_MASK),
          .bsram_mask(RAM_MASK)
      );
    end else assign MAP_ACTIVE[0] = 0;
  endgenerate

  wire [ 7:0] SDD_DO;
  wire        SDD_IRQ_N;
  wire [22:0] SDD_ROM_ADDR;
  wire        SDD_ROM_CE_N;
  wire        SDD_ROM_OE_N;
  wire        SDD_ROM_WORD;
  wire [19:0] SDD_BSRAM_ADDR;
  wire [ 7:0] SDD_BSRAM_D;
  wire        SDD_BSRAM_CE_N;
  wire        SDD_BSRAM_OE_N;
  wire        SDD_BSRAM_WE_N;

  generate
    if (USE_SDD1 == 1'b1) begin

      SDD1Map SDD1Map (
          .mclk (MCLK),
          .rst_n(RESET_N),

          .ca(CA),
          .di(DO),
          .do(SDD_DO),
          .cpurd_n(CPURD_N),
          .cpuwr_n(CPUWR_N),

          .pa(PA),
          .pard_n(PARD_N),
          .pawr_n(PAWR_N),

          .romsel_n(ROMSEL_N),
          .ramsel_n(RAMSEL_N),

          .sysclkf_ce(SYSCLKF_CE),
          .sysclkr_ce(SYSCLKR_CE),
          .refresh(REFRESH),

          .irq_n(SDD_IRQ_N),

          .rom_addr(SDD_ROM_ADDR),
          .rom_q(ROM_Q),
          .rom_ce_n(SDD_ROM_CE_N),
          .rom_oe_n(SDD_ROM_OE_N),
          .rom_word(SDD_ROM_WORD),

          .bsram_addr(SDD_BSRAM_ADDR),
          .bsram_d(SDD_BSRAM_D),
          .bsram_q(BSRAM_Q),
          .bsram_ce_n(SDD_BSRAM_CE_N),
          .bsram_oe_n(SDD_BSRAM_OE_N),
          .bsram_we_n(SDD_BSRAM_WE_N),

          .map_active(MAP_ACTIVE[1]),
          .map_ctrl  (ROM_TYPE),
          .rom_mask  (ROM_MASK),
          .bsram_mask(RAM_MASK)
      );
    end else assign MAP_ACTIVE[1] = 0;
  endgenerate

  wire [ 7:0] GSU_DO;
  wire        GSU_IRQ_N;
  wire [22:0] GSU_ROM_ADDR;
  wire        GSU_ROM_CE_N;
  wire        GSU_ROM_OE_N;
  wire        GSU_ROM_WORD;
  wire [19:0] GSU_BSRAM_ADDR;
  wire [ 7:0] GSU_BSRAM_D;
  wire        GSU_BSRAM_CE_N;
  wire        GSU_BSRAM_OE_N;
  wire        GSU_BSRAM_WE_N;

  generate
    if (USE_GSU == 1'b1) begin

      GSUMap GSUMap (
          .mclk (MCLK),
          .rst_n(RESET_N),

          .ca(CA),
          .di(DO),
          .do(GSU_DO),
          .cpurd_n(CPURD_N),
          .cpuwr_n(CPUWR_N),

          .pa(PA),
          .pard_n(PARD_N),
          .pawr_n(PAWR_N),

          .romsel_n(ROMSEL_N),
          .ramsel_n(RAMSEL_N),

          .sysclkf_ce(SYSCLKF_CE),
          .sysclkr_ce(SYSCLKR_CE),
          .refresh(REFRESH),

          .irq_n(GSU_IRQ_N),

          .rom_addr(GSU_ROM_ADDR),
          .rom_q(ROM_Q),
          .rom_ce_n(GSU_ROM_CE_N),
          .rom_oe_n(GSU_ROM_OE_N),
          .rom_word(GSU_ROM_WORD),

          .bsram_addr(GSU_BSRAM_ADDR),
          .bsram_d(GSU_BSRAM_D),
          .bsram_q(BSRAM_Q),
          .bsram_ce_n(GSU_BSRAM_CE_N),
          .bsram_oe_n(GSU_BSRAM_OE_N),
          .bsram_we_n(GSU_BSRAM_WE_N),

          .map_active(MAP_ACTIVE[2]),
          .map_ctrl  (ROM_TYPE),
          .rom_mask  (ROM_MASK),
          .bsram_mask(RAM_MASK),

          .turbo(GSU_TURBO)
      );
    end else assign MAP_ACTIVE[2] = 0;
  endgenerate

  assign GSU_ACTIVE = MAP_ACTIVE[2];

  wire [ 7:0] SA1_DO;
  wire        SA1_IRQ_N;
  wire [22:0] SA1_ROM_ADDR;
  wire        SA1_ROM_CE_N;
  wire        SA1_ROM_OE_N;
  wire        SA1_ROM_WORD;
  wire [19:0] SA1_BSRAM_ADDR;
  wire [ 7:0] SA1_BSRAM_D;
  wire        SA1_BSRAM_CE_N;
  wire        SA1_BSRAM_OE_N;
  wire        SA1_BSRAM_WE_N;

  generate
    if (USE_SA1 == 1'b1) begin

      SA1Map SA1Map (
          .mclk (MCLK),
          .rst_n(RESET_N),

          .ca(CA),
          .di(DO),
          .do(SA1_DO),
          .cpurd_n(CPURD_N),
          .cpuwr_n(CPUWR_N),

          .pa(PA),
          .pard_n(PARD_N),
          .pawr_n(PAWR_N),

          .romsel_n(ROMSEL_N),
          .ramsel_n(RAMSEL_N),

          .sysclkf_ce(SYSCLKF_CE),
          .sysclkr_ce(SYSCLKR_CE),
          .refresh(REFRESH),

          .pal(PAL),

          .irq_n(SA1_IRQ_N),

          .rom_addr(SA1_ROM_ADDR),
          .rom_q(ROM_Q),
          .rom_ce_n(SA1_ROM_CE_N),
          .rom_oe_n(SA1_ROM_OE_N),
          .rom_word(SA1_ROM_WORD),

          .bsram_addr(SA1_BSRAM_ADDR),
          .bsram_d(SA1_BSRAM_D),
          .bsram_q(BSRAM_Q),
          .bsram_ce_n(SA1_BSRAM_CE_N),
          .bsram_oe_n(SA1_BSRAM_OE_N),
          .bsram_we_n(SA1_BSRAM_WE_N),

          .map_active(MAP_ACTIVE[3]),
          .map_ctrl  (ROM_TYPE),
          .rom_mask  (ROM_MASK),
          .bsram_mask(RAM_MASK)
      );
    end else assign MAP_ACTIVE[3] = 0;
  endgenerate

  wire [ 7:0] SPC7110_DO;
  wire        SPC7110_IRQ_N;
  wire [22:0] SPC7110_ROM_ADDR;
  wire        SPC7110_ROM_CE_N;
  wire        SPC7110_ROM_OE_N;
  wire        SPC7110_ROM_WORD;
  wire [19:0] SPC7110_BSRAM_ADDR;
  wire [ 7:0] SPC7110_BSRAM_D;
  wire        SPC7110_BSRAM_CE_N;
  wire        SPC7110_BSRAM_OE_N;
  wire        SPC7110_BSRAM_WE_N;

  generate
    if (USE_SPC7110 == 1'b1) begin
      SPC7110Map SPC7110Map (
          .mclk (MCLK),
          .rst_n(RESET_N),

          .ca(CA),
          .di(DO),
          .do(SPC7110_DO),
          .cpurd_n(CPURD_N),
          .cpuwr_n(CPUWR_N),

          .pa(PA),
          .pard_n(PARD_N),
          .pawr_n(PAWR_N),

          .romsel_n(ROMSEL_N),
          .ramsel_n(RAMSEL_N),

          .sysclkf_ce(SYSCLKF_CE),
          .sysclkr_ce(SYSCLKR_CE),
          .refresh(REFRESH),

          .irq_n(SPC7110_IRQ_N),

          .rom_addr(SPC7110_ROM_ADDR),
          .rom_q(ROM_Q),
          .rom_ce_n(SPC7110_ROM_CE_N),
          .rom_oe_n(SPC7110_ROM_OE_N),
          .rom_word(SPC7110_ROM_WORD),

          .bsram_addr(SPC7110_BSRAM_ADDR),
          .bsram_d(SPC7110_BSRAM_D),
          .bsram_q(BSRAM_Q),
          .bsram_ce_n(SPC7110_BSRAM_CE_N),
          .bsram_oe_n(SPC7110_BSRAM_OE_N),
          .bsram_we_n(SPC7110_BSRAM_WE_N),

          .map_active(MAP_ACTIVE[4]),
          .map_ctrl  (ROM_TYPE),
          .rom_mask  (ROM_MASK),
          .bsram_mask(RAM_MASK),

          .ext_rtc(EXT_RTC)
      );
    end else assign MAP_ACTIVE[4] = 0;
  endgenerate

  wire [ 7:0] BSX_DO;
  wire        BSX_IRQ_N;
  wire [22:0] BSX_ROM_ADDR;
  wire [ 7:0] BSX_ROM_D;
  wire        BSX_ROM_CE_N;
  wire        BSX_ROM_OE_N;
  wire        BSX_ROM_WE_N;
  wire        BSX_ROM_WORD;
  wire [19:0] BSX_BSRAM_ADDR;
  wire [ 7:0] BSX_BSRAM_D;
  wire        BSX_BSRAM_CE_N;
  wire        BSX_BSRAM_OE_N;
  wire        BSX_BSRAM_WE_N;

  generate
    if (USE_BSX == 1'b1) begin
      BSXMap BSXMap (
          .mclk (MCLK),
          .rst_n(RESET_N),

          .ca(CA),
          .di(DO),
          .do(BSX_DO),
          .cpurd_n(CPURD_N),
          .cpuwr_n(CPUWR_N),

          .pa(PA),
          .pard_n(PARD_N),
          .pawr_n(PAWR_N),

          .romsel_n(ROMSEL_N),
          .ramsel_n(RAMSEL_N),

          .sysclkf_ce(SYSCLKF_CE),
          .sysclkr_ce(SYSCLKR_CE),
          .refresh(REFRESH),

          .irq_n(BSX_IRQ_N),

          .rom_addr(BSX_ROM_ADDR),
          .rom_d(BSX_ROM_D),
          .rom_q(ROM_Q),
          .rom_ce_n(BSX_ROM_CE_N),
          .rom_oe_n(BSX_ROM_OE_N),
          .rom_we_n(BSX_ROM_WE_N),
          .rom_word(BSX_ROM_WORD),

          .bsram_addr(BSX_BSRAM_ADDR),
          .bsram_d(BSX_BSRAM_D),
          .bsram_q(BSRAM_Q),
          .bsram_ce_n(BSX_BSRAM_CE_N),
          .bsram_oe_n(BSX_BSRAM_OE_N),
          .bsram_we_n(BSX_BSRAM_WE_N),

          .map_active(MAP_ACTIVE[5]),
          .map_ctrl  (ROM_TYPE),
          .rom_mask  (ROM_MASK),
          .bsram_mask(RAM_MASK),


          .ext_rtc(EXT_RTC)
      );
    end else assign MAP_ACTIVE[5] = 0;
  endgenerate

  assign TURBO_ALLOW = ~(MAP_ACTIVE[3] | MAP_ACTIVE[1]);

  always @(*) begin
    case (MAP_ACTIVE)
      'b000001: begin
        DI         = CX4_DO;
        IRQ_N      = CX4_IRQ_N;
        ROM_ADDR   = {1'b0, CX4_ROM_ADDR};
        ROM_D      = 7'h00;
        ROM_CE_N   = CX4_ROM_CE_N;
        ROM_OE_N   = CX4_ROM_OE_N;
        ROM_WE_N   = 1;
        BSRAM_ADDR = CX4_BSRAM_ADDR;
        BSRAM_D    = CX4_BSRAM_D;
        BSRAM_CE_N = CX4_BSRAM_CE_N;
        BSRAM_OE_N = CX4_BSRAM_OE_N;
        BSRAM_WE_N = CX4_BSRAM_WE_N;
        ROM_WORD   = CX4_ROM_WORD;
      end

      'b000010: begin
        DI         = SDD_DO;
        IRQ_N      = SDD_IRQ_N;
        ROM_ADDR   = {1'b0, SDD_ROM_ADDR};
        ROM_D      = 7'h00;
        ROM_CE_N   = SDD_ROM_CE_N;
        ROM_OE_N   = SDD_ROM_OE_N;
        ROM_WE_N   = 1;
        BSRAM_ADDR = SDD_BSRAM_ADDR;
        BSRAM_D    = SDD_BSRAM_D;
        BSRAM_CE_N = SDD_BSRAM_CE_N;
        BSRAM_OE_N = SDD_BSRAM_OE_N;
        BSRAM_WE_N = SDD_BSRAM_WE_N;
        ROM_WORD   = SDD_ROM_WORD;
      end

      'b000100: begin
        DI         = GSU_DO;
        IRQ_N      = GSU_IRQ_N;
        ROM_ADDR   = {1'b0, GSU_ROM_ADDR};
        ROM_D      = 7'h00;
        ROM_CE_N   = GSU_ROM_CE_N;
        ROM_OE_N   = GSU_ROM_OE_N;
        ROM_WE_N   = 1;
        BSRAM_ADDR = GSU_BSRAM_ADDR;
        BSRAM_D    = GSU_BSRAM_D;
        BSRAM_CE_N = GSU_BSRAM_CE_N;
        BSRAM_OE_N = GSU_BSRAM_OE_N;
        BSRAM_WE_N = GSU_BSRAM_WE_N;
        ROM_WORD   = GSU_ROM_WORD;
      end

      'b001000: begin
        DI         = SA1_DO;
        IRQ_N      = SA1_IRQ_N;
        ROM_ADDR   = {1'b0, SA1_ROM_ADDR};
        ROM_D      = 7'h00;
        ROM_CE_N   = SA1_ROM_CE_N;
        ROM_OE_N   = SA1_ROM_OE_N;
        ROM_WE_N   = 1;
        BSRAM_ADDR = SA1_BSRAM_ADDR;
        BSRAM_D    = SA1_BSRAM_D;
        BSRAM_CE_N = SA1_BSRAM_CE_N;
        BSRAM_OE_N = SA1_BSRAM_OE_N;
        BSRAM_WE_N = SA1_BSRAM_WE_N;
        ROM_WORD   = SA1_ROM_WORD;
      end

      'b010000: begin
        DI         = SPC7110_DO;
        IRQ_N      = SPC7110_IRQ_N;
        ROM_ADDR   = {1'b0, SPC7110_ROM_ADDR};
        ROM_D      = 7'h00;
        ROM_CE_N   = SPC7110_ROM_CE_N;
        ROM_OE_N   = SPC7110_ROM_OE_N;
        ROM_WE_N   = 1;
        BSRAM_ADDR = SPC7110_BSRAM_ADDR;
        BSRAM_D    = SPC7110_BSRAM_D;
        BSRAM_CE_N = SPC7110_BSRAM_CE_N;
        BSRAM_OE_N = SPC7110_BSRAM_OE_N;
        BSRAM_WE_N = SPC7110_BSRAM_WE_N;
        ROM_WORD   = SPC7110_ROM_WORD;
      end

      'b100000: begin
        DI         = BSX_DO;
        IRQ_N      = BSX_IRQ_N;
        ROM_ADDR   = {1'b0, BSX_ROM_ADDR};
        ROM_D      = BSX_ROM_D;
        ROM_CE_N   = BSX_ROM_CE_N;
        ROM_OE_N   = BSX_ROM_OE_N;
        ROM_WE_N   = BSX_ROM_WE_N;
        BSRAM_ADDR = BSX_BSRAM_ADDR;
        BSRAM_D    = BSX_BSRAM_D;
        BSRAM_CE_N = BSX_BSRAM_CE_N;
        BSRAM_OE_N = BSX_BSRAM_OE_N;
        BSRAM_WE_N = BSX_BSRAM_WE_N;
        ROM_WORD   = BSX_ROM_WORD;
      end

      default: begin
        DI         = DLH_DO;
        IRQ_N      = DLH_IRQ_N;
        ROM_ADDR   = DLH_ROM_ADDR;
        ROM_D      = 7'h00;
        ROM_CE_N   = DLH_ROM_CE_N;
        ROM_OE_N   = DLH_ROM_OE_N;
        ROM_WE_N   = 1;
        BSRAM_ADDR = DLH_BSRAM_ADDR;
        BSRAM_D    = DLH_BSRAM_D;
        BSRAM_CE_N = DLH_BSRAM_CE_N;
        BSRAM_OE_N = DLH_BSRAM_OE_N;
        BSRAM_WE_N = DLH_BSRAM_WE_N;
        ROM_WORD   = DLH_ROM_WORD;
      end
    endcase

    if (MSU_SEL) DI = MSU_DO;

    // PAR MK3 final-stage override (highest priority). On cart_override_hit the
    // MK3 byte wins over the underlying chip's read. Covers cheats during
    // gameplay, NMI vector redirect ($00:FFEA/$FFEB) for slots 5/6, and BIOS
    // bytes in MK3 Menu mode.
    if (mk3_cart_override_hit) DI = mk3_cart_override_data;
  end

endmodule
