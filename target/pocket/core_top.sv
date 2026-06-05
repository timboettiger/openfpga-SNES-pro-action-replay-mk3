//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

    //
    // physical connections
    //

    ///////////////////////////////////////////////////
    // clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

    input wire clk_74a,  // mainclk1
    input wire clk_74b,  // mainclk1 

    ///////////////////////////////////////////////////
    // cartridge interface
    // switches between 3.3v and 5v mechanically
    // output enable for multibit translators controlled by pic32

    // GBA AD[15:8]
    inout  wire [7:0] cart_tran_bank2,
    output wire       cart_tran_bank2_dir,

    // GBA AD[7:0]
    inout  wire [7:0] cart_tran_bank3,
    output wire       cart_tran_bank3_dir,

    // GBA A[23:16]
    inout  wire [7:0] cart_tran_bank1,
    output wire       cart_tran_bank1_dir,

    // GBA [7] PHI#
    // GBA [6] WR#
    // GBA [5] RD#
    // GBA [4] CS1#/CS#
    //     [3:0] unwired
    inout  wire [7:4] cart_tran_bank0,
    output wire       cart_tran_bank0_dir,

    // GBA CS2#/RES#
    inout  wire cart_tran_pin30,
    output wire cart_tran_pin30_dir,
    // when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
    // the goal is that when unconfigured, the FPGA weak pullups won't interfere.
    // thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
    // and general IO drive this pin.
    output wire cart_pin30_pwroff_reset,

    // GBA IRQ/DRQ
    inout  wire cart_tran_pin31,
    output wire cart_tran_pin31_dir,

    // infrared
    input  wire port_ir_rx,
    output wire port_ir_tx,
    output wire port_ir_rx_disable,

    // GBA link port
    inout  wire port_tran_si,
    output wire port_tran_si_dir,
    inout  wire port_tran_so,
    output wire port_tran_so_dir,
    inout  wire port_tran_sck,
    output wire port_tran_sck_dir,
    inout  wire port_tran_sd,
    output wire port_tran_sd_dir,

    ///////////////////////////////////////////////////
    // cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

    output wire [21:16] cram0_a,
    inout  wire [ 15:0] cram0_dq,
    input  wire         cram0_wait,
    output wire         cram0_clk,
    output wire         cram0_adv_n,
    output wire         cram0_cre,
    output wire         cram0_ce0_n,
    output wire         cram0_ce1_n,
    output wire         cram0_oe_n,
    output wire         cram0_we_n,
    output wire         cram0_ub_n,
    output wire         cram0_lb_n,

    output wire [21:16] cram1_a,
    inout  wire [ 15:0] cram1_dq,
    input  wire         cram1_wait,
    output wire         cram1_clk,
    output wire         cram1_adv_n,
    output wire         cram1_cre,
    output wire         cram1_ce0_n,
    output wire         cram1_ce1_n,
    output wire         cram1_oe_n,
    output wire         cram1_we_n,
    output wire         cram1_ub_n,
    output wire         cram1_lb_n,

    ///////////////////////////////////////////////////
    // sdram, 512mbit 16bit

    output wire [12:0] dram_a,
    output wire [ 1:0] dram_ba,
    inout  wire [15:0] dram_dq,
    output wire [ 1:0] dram_dqm,
    output wire        dram_clk,
    output wire        dram_cke,
    output wire        dram_ras_n,
    output wire        dram_cas_n,
    output wire        dram_we_n,

    ///////////////////////////////////////////////////
    // sram, 1mbit 16bit

    output wire [16:0] sram_a,
    inout  wire [15:0] sram_dq,
    output wire        sram_oe_n,
    output wire        sram_we_n,
    output wire        sram_ub_n,
    output wire        sram_lb_n,

    ///////////////////////////////////////////////////
    // vblank driven by dock for sync in a certain mode

    input wire vblank,

    ///////////////////////////////////////////////////
    // i/o to 6515D breakout usb uart

    output wire dbg_tx,
    input  wire dbg_rx,

    ///////////////////////////////////////////////////
    // i/o pads near jtag connector user can solder to

    output wire user1,
    input  wire user2,

    ///////////////////////////////////////////////////
    // RFU internal i2c bus 

    inout  wire aux_sda,
    output wire aux_scl,

    ///////////////////////////////////////////////////
    // RFU, do not use
    output wire vpll_feed,


    //
    // logical connections
    //

    ///////////////////////////////////////////////////
    // video, audio output to scaler
    output wire [23:0] video_rgb,
    output wire        video_rgb_clock,
    output wire        video_rgb_clock_90,
    output wire        video_de,
    output wire        video_skip,
    output wire        video_vs,
    output wire        video_hs,

    output wire audio_mclk,
    input  wire audio_adc,
    output wire audio_dac,
    output wire audio_lrck,

    ///////////////////////////////////////////////////
    // bridge bus connection
    // synchronous to clk_74a
    output wire        bridge_endian_little,
    input  wire [31:0] bridge_addr,
    input  wire        bridge_rd,
    output reg  [31:0] bridge_rd_data,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_wr_data,

    ///////////////////////////////////////////////////
    // controller data
    // 
    // key bitmap:
    //   [0]    dpad_up
    //   [1]    dpad_down
    //   [2]    dpad_left
    //   [3]    dpad_right
    //   [4]    face_a
    //   [5]    face_b
    //   [6]    face_x
    //   [7]    face_y
    //   [8]    trig_l1
    //   [9]    trig_r1
    //   [10]   trig_l2
    //   [11]   trig_r2
    //   [12]   trig_l3
    //   [13]   trig_r3
    //   [14]   face_select
    //   [15]   face_start
    // joy values - unsigned
    //   [ 7: 0] lstick_x
    //   [15: 8] lstick_y
    //   [23:16] rstick_x
    //   [31:24] rstick_y
    // trigger values - unsigned
    //   [ 7: 0] ltrig
    //   [15: 8] rtrig
    //
    input wire [31:0] cont1_key,
    input wire [31:0] cont2_key,
    input wire [31:0] cont3_key,
    input wire [31:0] cont4_key,
    input wire [31:0] cont1_joy,
    input wire [31:0] cont2_joy,
    input wire [31:0] cont3_joy,
    input wire [31:0] cont4_joy,
    input wire [15:0] cont1_trig,
    input wire [15:0] cont2_trig,
    input wire [15:0] cont3_trig,
    input wire [15:0] cont4_trig

);

  // not using the IR port, so turn off both the LED, and
  // disable the receive circuit to save power
  assign port_ir_tx              = 0;
  assign port_ir_rx_disable      = 1;

  // bridge endianness
  assign bridge_endian_little    = 0;

  // cart is unused, so set all level translators accordingly
  // directions are 0:IN, 1:OUT
  assign cart_tran_bank3         = 8'hzz;
  assign cart_tran_bank3_dir     = 1'b0;
  assign cart_tran_bank2         = 8'hzz;
  assign cart_tran_bank2_dir     = 1'b0;
  assign cart_tran_bank1         = 8'hzz;
  assign cart_tran_bank1_dir     = 1'b0;
  assign cart_tran_bank0         = 4'hf;
  assign cart_tran_bank0_dir     = 1'b1;
  assign cart_tran_pin30         = 1'b0;  // reset or cs2, we let the hw control it by itself
  assign cart_tran_pin30_dir     = 1'bz;
  assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
  assign cart_tran_pin31         = 1'bz;  // input
  assign cart_tran_pin31_dir     = 1'b0;  // input

  // link port is input only
  assign port_tran_so            = 1'bz;
  assign port_tran_so_dir        = 1'b0;  // SO is output only
  assign port_tran_si            = 1'bz;
  assign port_tran_si_dir        = 1'b0;  // SI is input only
  assign port_tran_sck           = 1'bz;
  assign port_tran_sck_dir       = 1'b0;  // clock direction can change
  assign port_tran_sd            = 1'bz;
  assign port_tran_sd_dir        = 1'b0;  // SD is input and not used

  // tie off the rest of the pins we are not using
  //   assign cram0_a                 = 'h0;
  //   assign cram0_dq                = {16{1'bZ}};
  //   assign cram0_clk               = 0;
  //   assign cram0_adv_n             = 1;
  //   assign cram0_cre               = 0;
  //   assign cram0_ce0_n             = 1;
  //   assign cram0_ce1_n             = 1;
  //   assign cram0_oe_n              = 1;
  //   assign cram0_we_n              = 1;
  //   assign cram0_ub_n              = 1;
  //   assign cram0_lb_n              = 1;

  //   assign cram1_a                 = 'h0;
  //   assign cram1_dq                = {16{1'bZ}};
  //   assign cram1_clk               = 0;
  //   assign cram1_adv_n             = 1;
  //   assign cram1_cre               = 0;
  //   assign cram1_ce0_n             = 1;
  //   assign cram1_ce1_n             = 1;
  //   assign cram1_oe_n              = 1;
  //   assign cram1_we_n              = 1;
  //   assign cram1_ub_n              = 1;
  //   assign cram1_lb_n              = 1;

  //   assign dram_a                  = 'h0;
  //   assign dram_ba                 = 'h0;
  //   assign dram_dq                 = {16{1'bZ}};
  //   assign dram_dqm                = 'h0;
  //   assign dram_clk                = 'h0;
  //   assign dram_cke                = 'h0;
  //   assign dram_ras_n              = 'h1;
  //   assign dram_cas_n              = 'h1;
  //   assign dram_we_n               = 'h1;

  assign sram_a                  = 'h0;
  assign sram_dq                 = {16{1'bZ}};
  assign sram_oe_n               = 1;
  assign sram_we_n               = 1;
  assign sram_ub_n               = 1;
  assign sram_lb_n               = 1;

  assign dbg_tx                  = 1'bZ;
  assign user1                   = 1'bZ;
  assign aux_scl                 = 1'bZ;
  assign vpll_feed               = 1'bZ;


  // for bridge write data, we just broadcast it to all bus devices
  // for bridge read data, we have to mux it
  // add your own devices here
  always @(*) begin
    casex (bridge_addr)
      default: begin
        bridge_rd_data <= 0;
      end
      32'h10xxxxxx: begin
        // example
        bridge_rd_data <= 0;
      end
      32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
      end
      // PAR MK3 LED status read-back. Low 2 bits = {right LED, left LED},
      // driven by the MK3 BIOS via the IO register at $00:6000.
      32'h308: begin
        bridge_rd_data <= {30'b0, mk3_leds_sync1};
      end
      // PAR MK3 "Cheats aktiv" read-back for the menu's Cheats & Trainer check.
      // Reflects the live mapper mode, not the last written value. 1 = active.
      32'h300: begin
        bridge_rd_data <= {31'b0, (mk3_eff_mode_s1 == 2'd1)};
      end
    endcase

    if (bridge_addr[31:28] == 4'h2) begin
      bridge_rd_data <= sd_read_data;
    end

    // PAR MK3 second save channel for the 32 KB cheat SRAM (slot 11, addr
    // 0x40000000). Byte-wide; separate from the cart save at 0x2xxxxxxx.
    if (bridge_addr[31:28] == 4'h4) begin
      bridge_rd_data <= mk3sv_read_data;
    end
  end

  always @(posedge clk_74a) begin
    if (reset_delay > 0) begin
      reset_delay <= reset_delay - 1;
    end

    if (bridge_wr) begin
      casex (bridge_addr)
        32'h0: begin
          ioctl_download <= bridge_wr_data[0];
        end
        32'h4: begin
          rom_size <= bridge_wr_data[3:0];
        end
        32'h8: begin
          rom_type <= bridge_wr_data[7:0];
        end
        32'hC: begin
          ram_size <= bridge_wr_data[3:0];
        end
        32'h10: begin
          PAL <= bridge_wr_data[0];
        end
        32'h50: begin
          reset_delay <= 32'h100000;
        end
        32'h80: begin
          cpu_turbo_enabled <= bridge_wr_data[0];
        end
        32'h84: begin
          gsu_turbo_enabled <= bridge_wr_data[0];
        end
        32'h100: begin
          multitap_enabled <= bridge_wr_data[0];
        end
        32'h104: begin
          lightgun_enabled <= bridge_wr_data[0];
          lightgun_type    <= bridge_wr_data[1];
          mouse_enabled    <= bridge_wr_data[2];
        end
        32'h00000108: begin
          dpad_aim_speed <= bridge_wr_data[7:0];
        end
        32'h0000010C: begin
          joystick_deadzone <= bridge_wr_data[7:0];
        end
        32'h110: begin
          mk3_mouse_port <= bridge_wr_data[0];
        end
        32'h200: begin
          use_square_pixels <= bridge_wr_data[0];
        end
        32'h204: begin
          blend_enabled <= bridge_wr_data[0];
        end
        // PAR MK3 SNES (interact.json addresses 0x300, 0x304).
        32'h300: begin
          mk3_switch_pos <= bridge_wr_data[1:0];
        end
        32'h304: begin
          // MK3 Soft Reset is an interact.json action: it writes 1 with no
          // following 0, so latching it as a level would hold reset forever.
          // Arm a one-shot, self-cleared next cycle; main.v stretches the pulse
          // into a reset window. MK3 SRAM (cheat list) is not cleared by reset.
          mk3_soft_reset_req <= 1'b1;
        end
        32'h30C: begin
          // PAR MK3 LED overlay POSITION (interact.json "Cartridge LED" list):
          // 0 = HIDE, 1..9 = 3x3 grid (TL TM TR / ML CENTER MR / BL BM BR).
          mk3_led_pos <= bridge_wr_data[3:0];
        end
        32'h310: begin
          // PAR MK3 "Pro Action Replay" action (interact.json id 203). Flips a
          // level bit; mk3_snes_top edge-detects it into a 1-cycle par_menu
          // pulse that forces the FSM to MK3 Menu. Works regardless of the
          // Cheats/Trainer toggle at $300.
          mk3_par_toggle <= ~mk3_par_toggle;
        end
      endcase
    end

    // Self-clear the soft-reset one-shot: high for one cycle after the write,
    // then drops. Without this it would stay 1 until the next $304 write.
    if (mk3_soft_reset_req && !(bridge_wr && bridge_addr == 32'h304)) begin
      mk3_soft_reset_req <= 1'b0;
    end
  end


  //
  // host/target command handler
  //
  wire reset_n;  // driven by host commands, can be used as core-wide reset
  wire [31:0] cmd_bridge_rd_data;

  // bridge host commands
  // synchronous to clk_74a
  wire status_boot_done = pll_core_locked;
  wire status_setup_done = pll_core_locked;  // rising edge triggers a target command
  wire status_running = reset_n;  // we are running as soon as reset_n goes high

  wire dataslot_requestread;
  wire [15:0] dataslot_requestread_id;
  wire dataslot_requestread_ack = 1;
  wire dataslot_requestread_ok = 1;

  wire dataslot_requestwrite;
  wire [15:0] dataslot_requestwrite_id;
  wire dataslot_requestwrite_ack = 1;
  wire dataslot_requestwrite_ok = 1;

  wire dataslot_allcomplete;

  wire savestate_supported = 0;
  wire [31:0] savestate_addr;
  wire [31:0] savestate_size;
  wire [31:0] savestate_maxloadsize;

  wire savestate_start;
  wire savestate_start_ack;
  wire savestate_start_busy;
  wire savestate_start_ok;
  wire savestate_start_err;

  wire savestate_load;
  wire savestate_load_ack;
  wire savestate_load_busy;
  wire savestate_load_ok;
  wire savestate_load_err;

  wire osnotify_inmenu;

  wire [31:0] rtc_date;
  wire [31:0] rtc_time;

  // bridge target commands
  // synchronous to clk_74a


  // bridge data slot access

  reg [9:0] datatable_addr;
  reg datatable_wren;
  reg [31:0] datatable_data;
  wire [31:0] datatable_q;

  core_bridge_cmd icb (

      .clk    (clk_74a),
      .reset_n(reset_n),

      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_rd           (bridge_rd),
      .bridge_rd_data      (cmd_bridge_rd_data),
      .bridge_wr           (bridge_wr),
      .bridge_wr_data      (bridge_wr_data),

      .status_boot_done (status_boot_done),
      .status_setup_done(status_setup_done),
      .status_running   (status_running),

      .dataslot_requestread    (dataslot_requestread),
      .dataslot_requestread_id (dataslot_requestread_id),
      .dataslot_requestread_ack(dataslot_requestread_ack),
      .dataslot_requestread_ok (dataslot_requestread_ok),

      .dataslot_requestwrite    (dataslot_requestwrite),
      .dataslot_requestwrite_id (dataslot_requestwrite_id),
      .dataslot_requestwrite_ack(dataslot_requestwrite_ack),
      .dataslot_requestwrite_ok (dataslot_requestwrite_ok),

      .dataslot_allcomplete(dataslot_allcomplete),

      .rtc_date_bcd(rtc_date),
      .rtc_time_bcd(rtc_time),

      .savestate_supported  (savestate_supported),
      .savestate_addr       (savestate_addr),
      .savestate_size       (savestate_size),
      .savestate_maxloadsize(savestate_maxloadsize),

      .savestate_start     (savestate_start),
      .savestate_start_ack (savestate_start_ack),
      .savestate_start_busy(savestate_start_busy),
      .savestate_start_ok  (savestate_start_ok),
      .savestate_start_err (savestate_start_err),

      .savestate_load     (savestate_load),
      .savestate_load_ack (savestate_load_ack),
      .savestate_load_busy(savestate_load_busy),
      .savestate_load_ok  (savestate_load_ok),
      .savestate_load_err (savestate_load_err),

      .osnotify_inmenu(osnotify_inmenu),

      .datatable_addr(datatable_addr),
      .datatable_wren(datatable_wren),
      .datatable_data(datatable_data),
      .datatable_q   (datatable_q)
  );

  reg ioctl_download = 0;
  wire ioctl_wr;
  wire [24:0] ioctl_addr;
  wire [15:0] ioctl_dout;

  reg save_download = 0;
  reg dataslot_allcomplete_prev;

  always @(posedge clk_74a) begin
    dataslot_allcomplete_prev <= dataslot_allcomplete;

    // if (dataslot_requestwrite) ioctl_download <= 1;
    // else if (dataslot_allcomplete) ioctl_download <= 0;

    if (dataslot_requestread || dataslot_requestwrite) save_download <= 1;
    else if (dataslot_allcomplete && ~dataslot_allcomplete_prev) save_download <= 0;
  end

  reg [7:0] rom_type;
  reg [3:0] rom_size;
  reg [3:0] ram_size;
  reg PAL;

  wire save_download_s;

  synch_3 save_s (
      save_download,
      save_download_s,
      clk_sys_21_48
  );

  data_loader #(
      .ADDRESS_MASK_UPPER_4(4'h1),
      .ADDRESS_SIZE(25),
      .WRITE_MEM_CLOCK_DELAY(7),
      .OUTPUT_WORD_SIZE(2)
  ) data_loader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_wr(bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_wr_data(bridge_wr_data),

      .write_en  (ioctl_wr),
      .write_addr(ioctl_addr),
      .write_data(ioctl_dout)
  );

  // PAR MK3 BIOS asset loader (data.json slot 100, addr 0x30000000).
  // Byte-wide: one BIOS byte per write.
  wire        mk3_bios_we;
  wire [16:0] mk3_bios_load_addr;
  wire [7:0]  mk3_bios_load_din;
  data_loader #(
      .ADDRESS_MASK_UPPER_4(4'h3),
      .ADDRESS_SIZE(17),
      .WRITE_MEM_CLOCK_DELAY(7),
      .OUTPUT_WORD_SIZE(1)
  ) mk3_bios_loader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_wr(bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_wr_data(bridge_wr_data),

      .write_en  (mk3_bios_we),
      .write_addr(mk3_bios_load_addr),
      .write_data(mk3_bios_load_din)
  );

  data_loader #(
      .ADDRESS_MASK_UPPER_4(4'h2),
      .ADDRESS_SIZE(17),
      .WRITE_MEM_CLOCK_DELAY(7),
      .OUTPUT_WORD_SIZE(2)
  ) save_data_loader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_wr(bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_wr_data(bridge_wr_data),

      .write_en  (sd_wr),
      .write_addr(sd_buff_addr_in),
      .write_data(sd_buff_dout)
  );

  wire [31:0] sd_read_data;

  wire sd_rd;
  wire sd_wr;

  wire [16:0] sd_buff_addr_in;
  wire [16:0] sd_buff_addr_out;

  // Lowest bit is for byte addressing
  wire [15:0] sd_buff_addr = sd_wr ? sd_buff_addr_in[16:1] : sd_buff_addr_out[16:1];

  wire [15:0] sd_buff_din;
  wire [15:0] sd_buff_dout;

  data_unloader #(
      .ADDRESS_MASK_UPPER_4(4'h2),
      .ADDRESS_SIZE(17),
      .READ_MEM_CLOCK_DELAY(7),
      .INPUT_WORD_SIZE(2)
  ) data_unloader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_rd(bridge_rd),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_rd_data(sd_read_data),

      .read_en  (sd_rd),
      .read_addr(sd_buff_addr_out),
      .read_data(sd_buff_din)
  );

  // ==========================================================================
  // PAR MK3 second save channel for the 32 KB cheat SRAM.
  //
  // Clone of the cart-save channel above (slot 10 at 0x2xxxxxxx), retargeted at
  // slot 11 / addr 0x40000000. Independent: the MK3 SRAM is its own dual-port
  // block (work.dpram port B), so it never touches the cart BSRAM or the SNES
  // cheat-write path (port A).
  //
  // The MK3 SRAM is byte-wide and 32 KB (15-bit address), so this uses byte
  // mode (OUTPUT/INPUT_WORD_SIZE = 1) like the BIOS loader: addresses are byte
  // addresses (no halving) and the 8-bit buses wire straight to mk3_sram port B.
  // ==========================================================================
  wire        mk3sv_wr;            // loader write strobe  (1 = restoring SRAM)
  wire [16:0] mk3sv_addr_in;       // loader byte address  (only [14:0] used)
  wire [7:0]  mk3sv_dout;          // loader byte to write into SRAM

  data_loader #(
      .ADDRESS_MASK_UPPER_4(4'h4),
      .ADDRESS_SIZE(17),
      .WRITE_MEM_CLOCK_DELAY(7),
      .OUTPUT_WORD_SIZE(1)
  ) mk3_save_data_loader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_wr(bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_wr_data(bridge_wr_data),

      .write_en  (mk3sv_wr),
      .write_addr(mk3sv_addr_in),
      .write_data(mk3sv_dout)
  );

  wire [31:0] mk3sv_read_data;     // routed to bridge_rd_data for addr 0x4xxxxxxx

  wire        mk3sv_rd;            // unloader read strobe (1 = saving SRAM)
  wire [16:0] mk3sv_addr_out;      // unloader byte address (only [14:0] used)
  wire [7:0]  mk3sv_din;           // SRAM byte returned to the unloader

  data_unloader #(
      .ADDRESS_MASK_UPPER_4(4'h4),
      .ADDRESS_SIZE(17),
      .READ_MEM_CLOCK_DELAY(7),
      .INPUT_WORD_SIZE(1)
  ) mk3_save_data_unloader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_rd(bridge_rd),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_rd_data(mk3sv_read_data),

      .read_en  (mk3sv_rd),
      .read_addr(mk3sv_addr_out),
      .read_data(mk3sv_din)
  );

  // The datatable tells the Pocket each data slot's size; the framework only
  // writes a slot to disk if its datatable size is non-zero. We publish two
  // sizes by alternating phases:
  //   slot 10 "Save" (index 1, size addr 3): dynamic cart SRAM size (sram_size)
  //   slot 11 "MK3 Cheats" (index 2, size addr 5): fixed 32 KB. Without this
  //   write the Pocket saw size 0 and never created the .mk3sav file.
  reg dt_phase = 1'b0;
  always @(posedge clk_74a or negedge pll_core_locked) begin
    if (~pll_core_locked) begin
      datatable_addr <= 0;
      datatable_data <= 0;
      datatable_wren <= 0;
      dt_phase       <= 1'b0;
    end else begin
      datatable_wren <= 1;
      dt_phase       <= ~dt_phase;
      if (~dt_phase) begin
        // slot 10 (cart save): actual size from ROM config (1024 << sram_size)
        datatable_data <= sram_size ? 32'd1024 << sram_size : 32'h0;
        datatable_addr <= 1 * 2 + 1;   // = 3
      end else begin
        // slot 11 (MK3 cheat SRAM): fixed 32 KB
        datatable_data <= 32'h0000_8000;
        datatable_addr <= 2 * 2 + 1;   // = 5
      end
    end
  end

  wire [15:0] audio_l;
  wire [15:0] audio_r;

  wire [3:0] sram_size;

  wire [31:0] cont1_key_s;
  wire [31:0] cont2_key_s;
  wire [31:0] cont3_key_s;
  wire [31:0] cont4_key_s;
  wire [31:0] cont1_joy_s;
  wire [31:0] cont2_joy_s;
  wire [31:0] cont3_joy_s;
  wire [31:0] cont4_joy_s;
  wire [15:0] cont1_trig_s;
  wire [15:0] cont2_trig_s;
  wire [15:0] cont3_trig_s;
  wire [15:0] cont4_trig_s;

  wire [15:0] cont1_joy_x = cont1_joy_s[7:0];
  wire [15:0] cont1_joy_y = cont1_joy_s[15:8];
  wire [15:0] cont1_joy_dx = cont1_joy_x[7] ? cont1_joy_x[6:0] : 8'd128 - cont1_joy_x[6:0];
  wire [15:0] cont1_joy_dy = cont1_joy_y[7] ? cont1_joy_y[6:0] : 8'd128 - cont1_joy_y[6:0];
  wire [16:0] cont1_joy_total = cont1_joy_dx + cont1_joy_dy;
  wire [15:0] cont1_joy_x_calibrated = cont1_joy_total > joystick_deadzone ? cont1_joy_x : 8'd128;
  wire [15:0] cont1_joy_y_calibrated = cont1_joy_total > joystick_deadzone ? cont1_joy_y : 8'd128;

  synch_3 #(
      .WIDTH(32)
  ) cont1_s (
      cont1_key,
      cont1_key_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) cont2_s (
      cont2_key,
      cont2_key_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) cont3_s (
      cont3_key,
      cont3_key_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) cont4_s (
      cont4_key,
      cont4_key_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) joy1_s (
      cont1_joy,
      cont1_joy_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) joy4_s (
      cont4_joy,
      cont4_joy_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(16)
  ) trig4_s (
      cont4_trig,
      cont4_trig_s,
      clk_sys_21_48
  );

  synch_3 #(.WIDTH(32)) joy2_s  (cont2_joy,  cont2_joy_s,  clk_sys_21_48);
  synch_3 #(.WIDTH(32)) joy3_s  (cont3_joy,  cont3_joy_s,  clk_sys_21_48);
  synch_3 #(.WIDTH(16)) trig1_s (cont1_trig, cont1_trig_s, clk_sys_21_48);
  synch_3 #(.WIDTH(16)) trig2_s (cont2_trig, cont2_trig_s, clk_sys_21_48);
  synch_3 #(.WIDTH(16)) trig3_s (cont3_trig, cont3_trig_s, clk_sys_21_48);

  // Real USB mouse: detect on any Pocket slot (Analogue default is slot 4).
  // The chosen SNES port and the game-running gate are applied below.
  wire mk3_m1 = (cont1_key_s[31:28] == 4'h5);
  wire mk3_m2 = (cont2_key_s[31:28] == 4'h5);
  wire mk3_m3 = (cont3_key_s[31:28] == 4'h5);
  wire mk3_m4 = (cont4_key_s[31:28] == 4'h5);
  wire mk3_mouse_any = mk3_m1 | mk3_m2 | mk3_m3 | mk3_m4;

  // Pick the slot holding the mouse (default-4 priority, then 1, 2, 3).
  wire [31:0] mk3_msel_key  = mk3_m4 ? cont4_key_s  : mk3_m1 ? cont1_key_s  : mk3_m2 ? cont2_key_s  : cont3_key_s;
  wire [31:0] mk3_msel_joy  = mk3_m4 ? cont4_joy_s  : mk3_m1 ? cont1_joy_s  : mk3_m2 ? cont2_joy_s  : cont3_joy_s;
  wire [15:0] mk3_msel_trig = mk3_m4 ? cont4_trig_s : mk3_m1 ? cont1_trig_s : mk3_m2 ? cont2_trig_s : cont3_trig_s;

  // Settings
  reg [31:0] reset_delay = 0;
  wire reset_button = reset_delay > 0;

  reg cpu_turbo_enabled = 0;
  reg gsu_turbo_enabled = 0;

  reg multitap_enabled = 0;
  reg lightgun_enabled = 0;
  reg lightgun_type = 0;
  reg [7:0] dpad_aim_speed = 0;
  reg [7:0] joystick_deadzone;
  reg mouse_enabled;
  reg mk3_mouse_port = 1'b0;  // Mouse Port setting: 0 = SNES port 1, 1 = SNES port 2

  reg use_square_pixels = 0;
  reg blend_enabled = 0;

  // PAR MK3 SNES interaction vars (bridge addrs 0x300/0x304), captured in
  // clk_74a and synced to clk_sys_21_48 below via synch_3.
  reg [1:0] mk3_switch_pos     = 2'd2;  // default: MK3 Menu
  reg       mk3_soft_reset_req = 1'b0;
  reg [3:0] mk3_led_pos = 4'd9;        // default: bottom-right (BR); 0 = hidden
  reg       mk3_par_toggle = 1'b0;     // flips on each "Pro Action Replay" ($310) action

  // PAR MK3 LED status (driven by mk3_snes_top in clk_sys). Crossed back to
  // clk_74a via a 2-FF sync and exposed at bridge addr 0x308 (2 LSBs).
  wire [1:0] mk3_leds_from_core;
  reg  [1:0] mk3_leds_sync0;
  reg  [1:0] mk3_leds_sync1;
  // Live mapper mode (effective_mode), synced clk_sys to clk_74a so the menu
  // can read back the "Cheats aktiv" state (bridge $300).
  wire [1:0] mk3_eff_mode_core;
  reg  [1:0] mk3_eff_mode_s0;
  reg  [1:0] mk3_eff_mode_s1;
  always @(posedge clk_74a) begin
    mk3_leds_sync0 <= mk3_leds_from_core;
    mk3_leds_sync1 <= mk3_leds_sync0;
    mk3_eff_mode_s0 <= mk3_eff_mode_core;
    mk3_eff_mode_s1 <= mk3_eff_mode_s0;
  end

  // Settings sync
  wire reset_button_s;

  wire cpu_turbo_enabled_s;
  wire gsu_turbo_enabled_s;

  wire multitap_enabled_s;
  wire lightgun_enabled_s;
  wire lightgun_type_s;
  wire [7:0] dpad_aim_speed_s;
  wire [7:0] joystick_deadzone_s;
  wire mouse_enabled_s;

  wire use_square_pixels_s;
  wire blend_enabled_s;

  // PAR MK3 cross-domain synchronized signals (clk_74a to clk_sys_21_48)
  wire [1:0] mk3_switch_pos_s;
  wire       mk3_soft_reset_req_s;
  wire       mk3_game_loaded_s;   // = dataslot_allcomplete sync'd into clk_sys
  wire [3:0] mk3_led_pos_s;
  wire       mk3_par_toggle_s;

  synch_3 #(
      .WIDTH(34)   // 28 base + mk3_game_loaded(1) + mk3_led_pos(4) + mk3_par_toggle(1)
  ) settings_s (
      {
        reset_button,
        cpu_turbo_enabled,
        gsu_turbo_enabled,
        multitap_enabled,
        lightgun_enabled,
        lightgun_type,
        dpad_aim_speed,
        joystick_deadzone,
        mouse_enabled,
        use_square_pixels,
        blend_enabled,
        mk3_switch_pos,
        mk3_soft_reset_req,
        dataslot_allcomplete,
        mk3_led_pos,
        mk3_par_toggle
      },
      {
        reset_button_s,
        cpu_turbo_enabled_s,
        gsu_turbo_enabled_s,
        multitap_enabled_s,
        lightgun_enabled_s,
        lightgun_type_s,
        dpad_aim_speed_s,
        joystick_deadzone_s,
        mouse_enabled_s,
        use_square_pixels_s,
        blend_enabled_s,
        mk3_switch_pos_s,
        mk3_soft_reset_req_s,
        mk3_game_loaded_s,
        mk3_led_pos_s,
        mk3_par_toggle_s
      },
      clk_sys_21_48
  );

  // Mouse Port setting (0 = SNES port 1, 1 = SNES port 2), synced to clk_sys.
  wire mk3_mouse_port_s;
  synch_3 #(.WIDTH(1)) mouseport_s (mk3_mouse_port, mk3_mouse_port_s, clk_sys_21_48);

  // Real USB mouse, packed for ioport. Active whenever a mouse is present; the
  // pad is routed to the other SNES port in SNES.sv so both reach the console.
  // [49] right [48] left [47:32] counter [31:16] dy [15:0] dx (LE byte-swapped).
  wire [50:0] mk3_mouse = {
      mk3_mouse_any,
      mk3_msel_joy[17],
      mk3_msel_joy[16],
      {mk3_msel_key[7:0],  mk3_msel_key[15:8]},
      {mk3_msel_trig[7:0], mk3_msel_trig[15:8]},
      {mk3_msel_joy[7:0],  mk3_msel_joy[15:8]}
  };

  reg new_rtc = 0;
  reg [31:0] prev_time = 0;

  always @(posedge clk_74a) begin
    if (rtc_time != prev_time) begin
      prev_time <= rtc_time;
      new_rtc   <= ~new_rtc;
    end
  end

  wire [64:0] rtc = {
    new_rtc,
    8'b0,  // Empty
    8'b1,  // Week day (not supported)
    rtc_date[23:16],  // Year (lower byte)
    rtc_date[15:8],  // Month
    rtc_date[7:0],  // Day
    rtc_time[23:16],  // Hour
    rtc_time[15:8],  // Minute
    rtc_time[7:0]  // Second
  };

  MAIN_SNES snes (
      .clk_mem_85_9 (clk_mem_85_9),
      .clk_sys_21_48(clk_sys_21_48),

      .core_reset(~pll_core_locked || reset_button_s),

      .rtc(rtc),

      // Settings
      .cpu_turbo_enabled(cpu_turbo_enabled_s),
      .gsu_turbo_enabled(gsu_turbo_enabled_s),

      .multitap_enabled(multitap_enabled_s),
      .lightgun_enabled(lightgun_enabled_s),
      .lightgun_type(lightgun_type_s),
      .dpad_aim_speed(dpad_aim_speed_s),
      .mouse_enabled(mouse_enabled_s),

      .blend_enabled(blend_enabled_s),

      // PAR MK3 (synced into clk_sys_21_48)
      .mk3_switch_pos(mk3_switch_pos_s),
      .mk3_soft_reset_req(mk3_soft_reset_req_s),

      // PAR MK3 BIOS loader (in clk_sys_21_48; data_loader handles its own CDC)
      .mk3_bios_we       (mk3_bios_we),
      .mk3_bios_load_addr(mk3_bios_load_addr),
      .mk3_bios_load_din (mk3_bios_load_din),

      // PAR MK3: true once all data slots are loaded (SNES ROM and mk3.bios
      // present). Drives the MK3 FSM's enable-cheats logic.
      .mk3_game_loaded   (mk3_game_loaded_s),
      .mk3_leds          (mk3_leds_from_core),
      .mk3_led_pos(mk3_led_pos_s),
      .mk3_par_toggle(mk3_par_toggle_s),
      .mk3_eff_mode      (mk3_eff_mode_core),

      // Input
      .p1_button_a(cont1_key_s[4]),
      .p1_button_b(cont1_key_s[5]),
      .p1_button_x(cont1_key_s[6]),
      .p1_button_y(cont1_key_s[7]),
      .p1_button_trig_l(cont1_key_s[8]),
      .p1_button_trig_r(cont1_key_s[9]),
      .p1_button_start(cont1_key_s[15]),
      .p1_button_select(cont1_key_s[14]),
      .p1_dpad_up(cont1_key_s[0]),
      .p1_dpad_down(cont1_key_s[1]),
      .p1_dpad_left(cont1_key_s[2]),
      .p1_dpad_right(cont1_key_s[3]),

      .p1_lstick_x(cont1_joy_x_calibrated),
      .p1_lstick_y(cont1_joy_y_calibrated),

      .mk3_mouse(mk3_mouse),
      .mk3_mouse_port(mk3_mouse_port_s),

      .p2_button_a(cont2_key_s[4]),
      .p2_button_b(cont2_key_s[5]),
      .p2_button_x(cont2_key_s[6]),
      .p2_button_y(cont2_key_s[7]),
      .p2_button_trig_l(cont2_key_s[8]),
      .p2_button_trig_r(cont2_key_s[9]),
      .p2_button_start(cont2_key_s[15]),
      .p2_button_select(cont2_key_s[14]),
      .p2_dpad_up(cont2_key_s[0]),
      .p2_dpad_down(cont2_key_s[1]),
      .p2_dpad_left(cont2_key_s[2]),
      .p2_dpad_right(cont2_key_s[3]),

      .p3_button_a(cont3_key_s[4]),
      .p3_button_b(cont3_key_s[5]),
      .p3_button_x(cont3_key_s[6]),
      .p3_button_y(cont3_key_s[7]),
      .p3_button_trig_l(cont3_key_s[8]),
      .p3_button_trig_r(cont3_key_s[9]),
      .p3_button_start(cont3_key_s[15]),
      .p3_button_select(cont3_key_s[14]),
      .p3_dpad_up(cont3_key_s[0]),
      .p3_dpad_down(cont3_key_s[1]),
      .p3_dpad_left(cont3_key_s[2]),
      .p3_dpad_right(cont3_key_s[3]),

      .p4_button_a(cont4_key_s[4]),
      .p4_button_b(cont4_key_s[5]),
      .p4_button_x(cont4_key_s[6]),
      .p4_button_y(cont4_key_s[7]),
      .p4_button_trig_l(cont4_key_s[8]),
      .p4_button_trig_r(cont4_key_s[9]),
      .p4_button_start(cont4_key_s[15]),
      .p4_button_select(cont4_key_s[14]),
      .p4_dpad_up(cont4_key_s[0]),
      .p4_dpad_down(cont4_key_s[1]),
      .p4_dpad_left(cont4_key_s[2]),
      .p4_dpad_right(cont4_key_s[3]),

      // ROM loading
      .ioctl_download(ioctl_download),
      .ioctl_wr(ioctl_wr),
      .ioctl_addr(ioctl_addr),
      .ioctl_dout(ioctl_dout),

      .rom_type(rom_type),
      .rom_size(rom_size),
      .ram_size(ram_size),
      .PAL(PAL),

      // Save input/output
      .save_download(save_download_s),
      .sd_rd(sd_rd),
      .sd_wr(sd_wr),
      .sd_buff_addr(sd_buff_addr),
      .sd_buff_din(sd_buff_din),
      .sd_buff_dout(sd_buff_dout),

      // PAR MK3 second save channel for the 32 KB cheat SRAM (slot 11).
      // Byte-wide; 15-bit addresses (only [14:0] of the 17-bit bus used).
      .mk3sv_wr      (mk3sv_wr),
      .mk3sv_rd      (mk3sv_rd),
      .mk3sv_addr_in (mk3sv_addr_in[14:0]),
      .mk3sv_addr_out(mk3sv_addr_out[14:0]),
      .mk3sv_dout    (mk3sv_dout),
      .mk3sv_din     (mk3sv_din),

      .sram_size(sram_size),

      // SDRAM
      .dram_a(dram_a),
      .dram_ba(dram_ba),
      .dram_dq(dram_dq),
      .dram_dqm(dram_dqm),
      .dram_clk(dram_clk),
      .dram_cke(dram_cke),
      .dram_ras_n(dram_ras_n),
      .dram_cas_n(dram_cas_n),
      .dram_we_n(dram_we_n),

      // PSRAM
      .cram0_a(cram0_a),
      .cram0_dq(cram0_dq),
      .cram0_wait(cram0_wait),
      .cram0_clk(cram0_clk),
      .cram0_adv_n(cram0_adv_n),
      .cram0_cre(cram0_cre),
      .cram0_ce0_n(cram0_ce0_n),
      .cram0_ce1_n(cram0_ce1_n),
      .cram0_oe_n(cram0_oe_n),
      .cram0_we_n(cram0_we_n),
      .cram0_ub_n(cram0_ub_n),
      .cram0_lb_n(cram0_lb_n),

      .cram1_a(cram1_a),
      .cram1_dq(cram1_dq),
      .cram1_wait(cram1_wait),
      .cram1_clk(cram1_clk),
      .cram1_adv_n(cram1_adv_n),
      .cram1_cre(cram1_cre),
      .cram1_ce0_n(cram1_ce0_n),
      .cram1_ce1_n(cram1_ce1_n),
      .cram1_oe_n(cram1_oe_n),
      .cram1_we_n(cram1_we_n),
      .cram1_ub_n(cram1_ub_n),
      .cram1_lb_n(cram1_lb_n),

      // Video
      .hblank (h_blank),
      .vblank (v_blank),
      .hsync  (video_hs_snes),
      .vsync  (video_vs_snes),
      .video_r(video_rgb_snes[23:16]),
      .video_g(video_rgb_snes[15:8]),
      .video_b(video_rgb_snes[7:0]),

      // Audio
      .audio_l(audio_l),
      .audio_r(audio_r)
  );

  // Video

  wire h_blank;
  wire v_blank;
  wire video_hs_snes;
  wire video_vs_snes;
  wire [23:0] video_rgb_snes;

  assign video_rgb_clock = clk_video_5_37;
  assign video_rgb_clock_90 = clk_video_5_37_90deg;
  assign video_rgb = rgb;
  assign video_de = de;

  reg de;
  reg [23:0] rgb;
  wire [7:0] snap_index;
  wire [23:0] rgb_out;
  wire de_out;

  scanline_filler #(
      .SNAP_COUNT (2),
      .SNAP_POINTS('{240, 224}),
      .HSYNC_DELAY(1)
  ) scanline_filler (
      .clk(clk_video_5_37),

      .hsync_in(video_hs_snes),
      .vsync_in(video_vs_snes),

      .vblank_in(v_blank),
      .hblank_in(h_blank),
      .rgb_in(video_rgb_snes),

      .hsync(video_hs),
      .vsync(video_vs),

      .de (de_out),
      .rgb(rgb_out),

      .snap_index(snap_index)
  );

  reg prev_de;
  reg prev_vs;
  reg [7:0] latched_snap_index;

  always @(posedge clk_video_5_37) begin
    prev_de <= de_out;
    prev_vs <= video_vs;

    de <= 0;

    if (video_vs && ~prev_vs) begin
      latched_snap_index <= snap_index;
    end

    if (~de_out && prev_de) begin
      // Write video slot
      rgb <= {9'b0, ~latched_snap_index[0], use_square_pixels_s, 10'b0, 3'b0};
    end else if (de_out) begin
      de  <= 1;
      rgb <= rgb_out;
    end
  end

  sound_i2s #(
      .CHANNEL_WIDTH(16),
      .SIGNED_INPUT (1)
  ) sound_i2s (
      .clk_74a  (clk_74a),
      .clk_audio(clk_sys_21_48),

      .audio_l(audio_l),
      .audio_r(audio_r),

      .audio_mclk(audio_mclk),
      .audio_lrck(audio_lrck),
      .audio_dac (audio_dac)
  );

  ///////////////////////////////////////////////

  wire clk_mem_85_9;
  wire clk_sys_21_48;
  wire clk_video_5_37;
  wire clk_video_5_37_90deg;

  wire pll_core_locked;

  parameter PAL_PLL = 1'b0;

  generate
    if (PAL_PLL) begin
      mf_pllbase_pal mp1 (
          .refclk(clk_74a),

          .outclk_0(clk_mem_85_9),
          .outclk_1(clk_sys_21_48),
          .outclk_2(clk_video_5_37),
          .outclk_3(clk_video_5_37_90deg),

          .locked(pll_core_locked)
      );
    end else begin
      mf_pllbase mp1 (
          .refclk(clk_74a),

          .outclk_0(clk_mem_85_9),
          .outclk_1(clk_sys_21_48),
          .outclk_2(clk_video_5_37),
          .outclk_3(clk_video_5_37_90deg),

          .locked(pll_core_locked)
      );
    end
  endgenerate

endmodule
