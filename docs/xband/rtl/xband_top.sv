//----------------------------------------------------------------------------
// xband_top.sv  -- top-level wiring for the XBAND reference skeleton.
//
// Mirrors the add-on-chip structure used by rtl/chip/mk3 (mapper + regs + sram
// + modem). See docs/xband/11-rtl-architecture.md. Reference skeleton only --
// NOT wired into the Pocket build.
//----------------------------------------------------------------------------
`default_nettype none

module xband_top
  import xband_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // ---- SNES cartridge bus (from the SNES core) ------------------------
    input  logic [23:0]  cpu_addr,
    input  logic [7:0]   cpu_din,        // SNES -> XBAND (writes)
    output logic [7:0]   cpu_dout,       // XBAND -> SNES (reads)
    input  logic         cpu_rd,
    input  logic         cpu_wr,

    // video timebase (the modem bit-clock is derived from this; see doc 07)
    input  logic         hsync,
    input  logic         vsync,
    input  logic         pixel_ce,

    // ---- BIOS load + read-back (driven by a Pocket data-slot loader) -----
    input  logic         bios_we,
    input  logic [XBAND_ROM_ADDR_BITS-1:0] bios_load_addr,
    input  logic [7:0]   bios_load_din,
    output logic         bios_read,
    output logic [XBAND_ROM_ADDR_BITS-1:0] bios_read_addr,
    input  logic [7:0]   bios_dout,      // byte back from external ROM store

    // ---- 64 KB battery SRAM save channel (independent of SNES R/W) -------
    input  logic         sav_wr,
    input  logic [XBAND_SRAM_ADDR_BITS-1:0] sav_addr_in,
    input  logic [7:0]   sav_din,
    input  logic         sav_rd,
    input  logic [XBAND_SRAM_ADDR_BITS-1:0] sav_addr_out,
    output logic [7:0]   sav_dout,

    // ---- modem transport (tunnel to ESP32 / server; see doc 12) ----------
    output logic [7:0]   modem_tx_data,
    output logic         modem_tx_valid,
    input  logic         modem_tx_ready,
    input  logic [7:0]   modem_rx_data,
    input  logic         modem_rx_valid,
    output logic         modem_rx_ready,

    // ---- front-panel LEDs (drive the same OSD the MK3 core renders) ------
    output logic [7:0]   leds
);

  // ---- internal nets ------------------------------------------------------
  logic        sel_bios, sel_game, sel_sram, sel_reg;
  logic [XBAND_SRAM_ADDR_BITS-1:0] sram_off;
  logic [8:0]  reg_off;
  logic [7:0]  reg_rdata, sram_rdata;

  logic [7:0]  serial_vcnt, mvsync_high;
  logic        modem_bit_ce;

  // ---- address decode -----------------------------------------------------
  xband_mapper u_mapper (
      .clk(clk), .rst_n(rst_n),
      .cpu_addr(cpu_addr),
      .sel_bios(sel_bios), .sel_game(sel_game),
      .sel_sram(sel_sram), .sel_reg(sel_reg),
      .sram_offset(sram_off), .reg_offset(reg_off),
      .bios_read(bios_read), .bios_read_addr(bios_read_addr)
  );

  // ---- FRED register file -------------------------------------------------
  xband_fred_regs u_regs (
      .clk(clk), .rst_n(rst_n),
      .sel(sel_reg), .offset(reg_off),
      .wr(cpu_wr), .wdata(cpu_din), .rdata(reg_rdata),
      .serial_vcnt(serial_vcnt), .mvsync_high(mvsync_high),
      .modem_tx_data(modem_tx_data), .modem_tx_valid(modem_tx_valid),
      .modem_tx_ready(modem_tx_ready),
      .modem_rx_data(modem_rx_data), .modem_rx_valid(modem_rx_valid),
      .modem_rx_ready(modem_rx_ready),
      .leds(leds)
  );

  // ---- 64 KB battery SRAM (dual port: SNES side + save channel) -----------
  xband_sram u_sram (
      .clk(clk),
      .a_addr(sram_off), .a_wr(sel_sram & cpu_wr), .a_din(cpu_din), .a_dout(sram_rdata),
      .b_wr(sav_wr), .b_waddr(sav_addr_in), .b_din(sav_din),
      .b_rd(sav_rd), .b_raddr(sav_addr_out), .b_dout(sav_dout)
  );

  // ---- video-locked modem timebase ----------------------------------------
  xband_modem_timing u_timing (
      .clk(clk), .rst_n(rst_n),
      .hsync(hsync), .vsync(vsync), .pixel_ce(pixel_ce),
      .serial_vcnt(serial_vcnt), .mvsync_high(mvsync_high),
      .modem_bit_ce(modem_bit_ce)
  );

  // ---- read mux -----------------------------------------------------------
  always_comb begin
    unique case (1'b1)
      sel_bios: cpu_dout = bios_dout;
      sel_sram: cpu_dout = sram_rdata;
      sel_reg:  cpu_dout = reg_rdata;
      default:  cpu_dout = 8'hFF;   // sel_game handled by the base core mapper
    endcase
  end

  // BIOS write-back path into the external ROM store is handled by the loader;
  // bios_we/bios_load_* are consumed by the top-level data-slot bridge.
  // (Left visible here so the interface matches docs/xband/08-bios-and-roms.md.)
  wire _unused_ok = &{1'b0, bios_we, bios_load_addr, bios_load_din,
                      sel_game, modem_bit_ce};

endmodule

`default_nettype wire
