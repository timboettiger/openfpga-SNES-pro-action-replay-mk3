//----------------------------------------------------------------------------
// xband_tb.sv -- self-checking testbench for the XBAND reference skeleton.
//
// Exercises the documented behaviour and the items confirmed/closed against the
// real 1 MB BIOS dump (docs/xband/13-rom-memory-map.md):
//   * FRED register reset/self-test invariants (doc 07 / fredtest.c).
//   * HiROM address decode: BIOS / SRAM / safe-ROM / register window.
//   * FRED patch engine: zero-page remap, trans-address remap, and the
//     per-vector table walk (entries fetched from SRAM).
//   * Modem bridge pacing to the video-locked bit strobe.
//
// Run:  verilator --binary --timing -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
//         -Wno-WIDTHEXPAND --top-module xband_tb <all .sv> && ./obj_dir/Vxband_tb
// (see run-tb.sh). Prints "ALL TESTS PASSED" on success; $error/$fatal on any
// mismatch.
//----------------------------------------------------------------------------
`default_nettype none

module xband_tb
  import xband_pkg::*;
;
  // ---- clock / reset ------------------------------------------------------
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  integer errors = 0;
  task automatic check(input logic cond, input string msg);
    if (!cond) begin
      errors = errors + 1;
      $error("CHECK FAILED: %s", msg);
    end
  endtask

  // =========================================================================
  // DUT 1: FRED register file
  // =========================================================================
  logic        r_sel, r_wr;
  logic [8:0]  r_off;
  logic [7:0]  r_wdata, r_rdata;
  logic [7:0]  tb_serial_vcnt = 8'h00, tb_mvsync_high = 8'h00;
  logic [7:0]  mtx_data; logic mtx_valid; logic mtx_ready = 1'b1;
  logic [7:0]  mrx_data = 8'h00; logic mrx_valid = 1'b0; logic mrx_ready;
  logic [7:0]  control_reg, kill_reg, enable_lo, enable_hi, leds;
  logic [23:0] range_base, tr_base, vtable_base, saferam_base, saferam_bounds;
  logic [23:0] saferom_base, saferom_bounds;

  xband_fred_regs u_regs (
    .clk(clk), .rst_n(rst_n),
    .sel(r_sel), .offset(r_off), .wr(r_wr), .wdata(r_wdata), .rdata(r_rdata),
    .serial_vcnt(tb_serial_vcnt), .mvsync_high(tb_mvsync_high),
    .modem_tx_data(mtx_data), .modem_tx_valid(mtx_valid), .modem_tx_ready(mtx_ready),
    .modem_rx_data(mrx_data), .modem_rx_valid(mrx_valid), .modem_rx_ready(mrx_ready),
    .control_reg(control_reg), .kill_reg(kill_reg),
    .enable_lo(enable_lo), .enable_hi(enable_hi),
    .range_base(range_base), .tr_base(tr_base), .vtable_base(vtable_base),
    .saferam_base(saferam_base), .saferam_bounds(saferam_bounds),
    .saferom_base(saferom_base), .saferom_bounds(saferom_bounds),
    .leds(leds)
  );

  task automatic reg_write(input logic [8:0] off, input logic [7:0] data);
    @(posedge clk); r_sel <= 1'b1; r_wr <= 1'b1; r_off <= off; r_wdata <= data;
    @(posedge clk); r_sel <= 1'b0; r_wr <= 1'b0;
  endtask
  function automatic logic [7:0] reg_read_comb(input logic [8:0] off);
    // combinational read: drive and sample after a settle
    reg_read_comb = 8'hxx;
  endfunction

  // =========================================================================
  // DUT 2: address mapper (combinational)
  // =========================================================================
  logic [23:0] m_addr;
  logic [7:0]  m_ctrl, m_kill;
  logic [23:0] m_srom_base, m_srom_bnd;
  logic        m_predir; logic [23:0] m_predir_addr;
  logic        m_sel_bios, m_sel_game, m_sel_sram, m_sel_reg;
  logic [XBAND_SRAM_ADDR_BITS-1:0] m_sram_off;
  logic [8:0]  m_reg_off;
  logic        m_bios_read; logic [XBAND_ROM_ADDR_BITS-1:0] m_bios_addr;

  xband_mapper u_map (
    .clk(clk), .rst_n(rst_n),
    .cpu_addr(m_addr), .control_reg(m_ctrl), .kill_reg(m_kill),
    .saferom_base(m_srom_base), .saferom_bounds(m_srom_bnd),
    .patch_redirect(m_predir), .patch_redirect_addr(m_predir_addr),
    .sel_bios(m_sel_bios), .sel_game(m_sel_game),
    .sel_sram(m_sel_sram), .sel_reg(m_sel_reg),
    .sram_offset(m_sram_off), .reg_offset(m_reg_off),
    .bios_read(m_bios_read), .bios_read_addr(m_bios_addr)
  );

  // =========================================================================
  // DUT 3: patch engine + SRAM (per-vector table walk)
  // =========================================================================
  logic [7:0]  p_en_lo, p_en_hi;
  logic [23:0] p_range, p_tr, p_vtable, p_sr_base, p_sr_bnd;
  logic [23:0] p_addr; logic p_active;
  logic        p_vt_rd; logic [XBAND_SRAM_ADDR_BITS-1:0] p_vt_addr; logic [7:0] p_vt_data;
  logic        p_redir; logic [23:0] p_redir_addr;

  // SRAM: port A for preloading vtable entries, port C for the walk.
  logic [XBAND_SRAM_ADDR_BITS-1:0] sa_addr; logic sa_wr; logic [7:0] sa_din, sa_dout;
  xband_sram u_sr (
    .clk(clk),
    .a_addr(sa_addr), .a_wr(sa_wr), .a_din(sa_din), .a_dout(sa_dout),
    .b_wr(1'b0), .b_waddr('0), .b_din('0), .b_rd(1'b0), .b_raddr('0), .b_dout(),
    .c_rd(p_vt_rd), .c_raddr(p_vt_addr), .c_dout(p_vt_data)
  );

  xband_fred_patch u_patch (
    .clk(clk), .rst_n(rst_n),
    .enable_lo(p_en_lo), .enable_hi(p_en_hi),
    .range_base(p_range), .tr_base(p_tr), .vtable_base(p_vtable),
    .saferam_base(p_sr_base), .saferam_bounds(p_sr_bnd),
    .cpu_addr(p_addr), .cpu_active(p_active),
    .vtable_rd(p_vt_rd), .vtable_addr(p_vt_addr), .vtable_data(p_vt_data),
    .redirect(p_redir), .redirect_addr(p_redir_addr)
  );

  task automatic sram_poke(input logic [15:0] a, input logic [7:0] d);
    @(posedge clk); sa_addr <= a[XBAND_SRAM_ADDR_BITS-1:0]; sa_wr <= 1'b1; sa_din <= d;
    @(posedge clk); sa_wr <= 1'b0;
  endtask

  // =========================================================================
  // DUT 4: modem bridge pacing
  // =========================================================================
  logic       um_bit_ce;
  logic [7:0] um_tx_data; logic um_tx_valid; logic um_tx_ready;
  logic [7:0] um_rx_data; logic um_rx_valid; logic um_rx_ready = 1'b0;
  logic [7:0] um_phy_tx_data; logic um_phy_tx_valid; logic um_phy_tx_ready = 1'b1;
  logic [7:0] um_phy_rx_data = 8'h00; logic um_phy_rx_valid = 1'b0; logic um_phy_rx_ready;
  logic       um_tx_empty, um_rx_empty;

  xband_modem_uart u_modem (
    .clk(clk), .rst_n(rst_n), .modem_bit_ce(um_bit_ce),
    .tx_data(um_tx_data), .tx_valid(um_tx_valid), .tx_ready(um_tx_ready),
    .rx_data(um_rx_data), .rx_valid(um_rx_valid), .rx_ready(um_rx_ready),
    .phy_tx_data(um_phy_tx_data), .phy_tx_valid(um_phy_tx_valid), .phy_tx_ready(um_phy_tx_ready),
    .phy_rx_data(um_phy_rx_data), .phy_rx_valid(um_phy_rx_valid), .phy_rx_ready(um_phy_rx_ready),
    .tx_fifo_empty(um_tx_empty), .rx_fifo_empty(um_rx_empty)
  );

  // =========================================================================
  // Stimulus
  // =========================================================================
  integer i;
  logic [7:0] phy_seen;
  initial begin
    // defaults
    r_sel=0; r_wr=0; r_off=0; r_wdata=0;
    m_addr=0; m_ctrl=0; m_kill=0; m_srom_base=0; m_srom_bnd=0; m_predir=0; m_predir_addr=0;
    p_en_lo=0; p_en_hi=0; p_range=0; p_tr=0; p_vtable=0; p_sr_base=0; p_sr_bnd=0;
    p_addr=0; p_active=0;
    sa_addr=0; sa_wr=0; sa_din=0;
    um_bit_ce=0; um_tx_data=0; um_tx_valid=0;
    phy_seen=8'h00;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // ---- TEST 1: FRED reset/self-test invariants -------------------------
    // LED data resets to 0x7F (7 LEDs present).
    @(negedge clk); r_sel=1'b1; r_wr=1'b0; r_off=REG_LED_DATA; #1;
    check(r_rdata == RST_LED_DATA, "kLEDData reset != 0x7F");
    r_off=REG_ADDRSTAT_LOW; #1;
    check(r_rdata == RST_ADDRSTAT_LOW, "kAddrStatusLow reset != 0x00");
    r_off=REG_READMSTATUS1; #1;
    check((r_rdata & 8'h02) == RST_READMSTATUS1, "kReadMStatus1 idle bit != 0x02");
    r_sel=1'b0;
    @(posedge clk);

    // ---- TEST 2: register write/read-back + control/kill export ----------
    reg_write(REG_CONTROL, CTL_ROM_HI | CTL_EN_SAFE_ROM);
    reg_write(REG_KILL,    KILL_HERE_ASSERT);
    @(posedge clk);
    check(control_reg == (CTL_ROM_HI | CTL_EN_SAFE_ROM), "control_reg export wrong");
    check(kill_reg == KILL_HERE_ASSERT, "kill_reg export wrong");

    // ---- TEST 3: HiROM decode --------------------------------------------
    // (a) BIOS read when Here asserted, ROM full bank $C0:8000.
    m_kill = KILL_HERE_ASSERT; m_ctrl = 8'h00; m_srom_bnd = 24'h0; #1;
    m_addr = 24'hC0_8000; #1;
    check(m_sel_bios && m_bios_read, "C0:8000 should select BIOS");
    check(m_bios_addr == {1'b0, 3'b000, 16'h8000}, "BIOS addr (lo half) wrong");
    // kRomHi selects the upper 512 KB half (bit 19).
    m_ctrl = CTL_ROM_HI; #1;
    check(m_bios_addr[XBAND_ROM_ADDR_BITS-1] == 1'b1, "kRomHi should set ROM bit19");
    m_ctrl = 8'h00; #1;
    // (b) upper-half window $00:8000 -> BIOS.
    m_addr = 24'h00_8000; #1;
    check(m_sel_bios, "00:8000 upper-half should select BIOS");
    // (c) $00:0000 (WRAM, lower half) is NOT a cart ROM window.
    m_addr = 24'h00_0000; #1;
    check(!m_sel_bios && !m_sel_game, "00:0000 must not select cart ROM");
    // (d) SRAM at bank $E0 linear.
    m_addr = 24'hE0_1234; #1;
    check(m_sel_sram && (m_sram_off == 16'h1234), "E0:1234 should be SRAM off 0x1234");
    // (e) SRAM small window $20:6000.
    m_addr = 24'h20_6000; #1;
    check(m_sel_sram, "20:6000 should select SRAM window");
    // (f) Here clear -> ROM window falls through to the game cart.
    m_kill = 8'h00; m_addr = 24'hC0_8000; #1;
    check(m_sel_game && !m_sel_bios, "Here clear -> game cart");

    // ---- TEST 4: safe-ROM hole -------------------------------------------
    // Program a safe-ROM range [C2_0000, C2_0000+0x10000) and assert Here.
    m_ctrl = CTL_EN_SAFE_ROM; m_kill = KILL_HERE_ASSERT;
    m_srom_base = 24'hC2_0000; m_srom_bnd = 24'h01_0000;
    m_addr = 24'hC2_4000; #1;
    check(m_sel_game && !m_sel_bios, "safe-ROM hole should expose game cart");
    m_addr = 24'hC3_4000; #1;   // outside the safe-ROM range
    check(m_sel_bios, "outside safe-ROM should be BIOS while Here");
    m_ctrl = 8'h00; m_srom_bnd = 24'h0;

    // ---- TEST 5: patch engine -- zero-page remap -------------------------
    p_sr_base = 24'h7F_0000;        // safe-RAM in bank $7F
    p_sr_bnd  = 24'h00_1000;
    p_en_hi   = ENH_ZEROPAGE;       // 0x80
    p_addr    = 24'h12_0044;        // $00xx within bank $12
    p_active  = 1'b1;
    repeat (2) @(posedge clk); #1;
    check(p_redir && (p_redir_addr == {p_sr_base[23:8], 8'h44}),
          "zero-page remap target wrong");
    p_en_hi = 8'h00; p_active = 1'b0; @(posedge clk);

    // ---- TEST 6: patch engine -- trans-address remap ---------------------
    p_range  = 24'h80_0000;
    p_tr     = 24'h7F_0200;
    p_sr_base= 24'h7F_0000;
    p_sr_bnd = 24'h00_1000;
    p_en_hi  = ENH_TRANSADDR;       // 0x40
    p_addr   = 24'h80_0010;
    p_active = 1'b1;
    repeat (2) @(posedge clk); #1;
    check(p_redir && (p_redir_addr == 24'h7F_0210), "trans-address remap target wrong");
    p_en_hi = 8'h00; p_active = 1'b0; @(posedge clk);

    // ---- TEST 7: patch engine -- per-vector table walk -------------------
    // Vector0 entry at vtable_base(=0): bytes {lo=0x34, hi=0x12} -> dest $7F:1234.
    p_vtable = 24'h00_0000;
    p_sr_base= 24'h7F_0000;
    p_sr_bnd = 24'h00_4000;
    p_range  = 24'h81_0000;
    sram_poke(16'h0000, 8'h34);
    sram_poke(16'h0001, 8'h12);
    @(posedge clk);
    p_en_lo  = 8'h01;               // Vector0 armed
    p_en_hi  = 8'h00;
    p_addr   = 24'h81_0020;
    p_active = 1'b1;
    // allow the fetch FSM + registered redirect to settle
    repeat (9) @(posedge clk); #1;
    check(p_redir, "vector walk should redirect");
    check(p_redir_addr == 24'h7F_1234, "vector walk target should be $7F:1234");
    p_en_lo = 8'h00; p_active = 1'b0; @(posedge clk);

    // ---- TEST 8: modem bridge pacing -------------------------------------
    // Push one byte; it must only appear on the PHY when modem_bit_ce ticks.
    @(posedge clk); #1; um_tx_data = 8'hA5; um_tx_valid = 1'b1;
    @(posedge clk); #1; um_tx_valid = 1'b0;
    // Without a bit strobe, phy_tx_valid stays low for a while.
    um_bit_ce = 1'b0;
    repeat (4) @(posedge clk);
    check(um_phy_tx_valid == 1'b0, "phy_tx_valid must be gated by modem_bit_ce");
    // Now strobe: the byte is presented and accepted.
    @(posedge clk); #1; um_bit_ce = 1'b1;
    #1;
    check(um_phy_tx_valid && (um_phy_tx_data == 8'hA5), "byte must appear on bit strobe");
    @(posedge clk); #1; um_bit_ce = 1'b0;
    repeat (2) @(posedge clk);
    check(um_tx_empty, "tx FIFO should drain after the paced byte");

    // ---- done ------------------------------------------------------------
    repeat (2) @(posedge clk);
    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $fatal(1, "%0d CHECK(S) FAILED", errors);
    $finish;
  end

  // safety timeout
  initial begin
    #20000;
    $fatal(1, "TIMEOUT");
  end

endmodule

`default_nettype wire
