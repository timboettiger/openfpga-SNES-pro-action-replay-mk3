//----------------------------------------------------------------------------
// xband_pkg.sv
//
// Constants for the XBAND reference RTL skeleton. All register offsets and bit
// masks are transcribed from Catapult's own diagnostic source
//   catapult.tar.gz -> Catapult/Box-16bit-Feb96/Tools/ModemTester/defines.h
// and documented in docs/xband/07-fred-register-map.md.
//
// FRED registers live on even byte addresses: defines.h writes them as
// (index << 1). The localparams below store the *byte* offset (index << 1).
//
// NOTE: reference skeleton, not wired into the Pocket build. See docs/xband/.
//----------------------------------------------------------------------------
package xband_pkg;

  // ---- memory sizes (retail box) ------------------------------------------
  localparam int XBAND_ROM_ADDR_BITS  = 20;          // 1 MB BIOS
  localparam int XBAND_ROM_BYTES      = 1 << XBAND_ROM_ADDR_BITS;
  localparam int XBAND_SRAM_ADDR_BITS = 16;          // 64 KB battery SRAM
  localparam int XBAND_SRAM_BYTES     = 1 << XBAND_SRAM_ADDR_BITS;

  // ---- retail SNES decode (HiROM) -----------------------------------------
  // Confirmed against the real 1 MB dump (docs/xband/13-rom-memory-map.md):
  //   header @ $FFC0, mapmode 0x31 (HiROM+FastROM), romsize 0x0A (1 MB),
  //   ramsize 0x06 (64 KB), checksum 0x1A5D verified.
  // HiROM ROM banks: $C0-$FF full + $00-$3F/$80-$BF upper half.
  // 64 KB SRAM is presented linearly at bank $E0 (BIOS reads $E0:0000), with
  // the classic HiROM $20-$3F:$6000-$7FFF small window also decoded.
  localparam logic [7:0] SRAM_BANK       = 8'hE0;    // 64 KB SRAM @ $E0:xxxx
  localparam logic [7:0] ROM_BANK_HI_LO  = 8'hC0;    // first full-bank ROM image
  // kRomHi swaps the 512 KB code half <-> 512 KB asset half (bit 19 of ROM addr).
  localparam int XBAND_ROM_HALF_BIT   = XBAND_ROM_ADDR_BITS - 1; // 19

  // ---- patch-vector table (per-vector entries live in SRAM) ----------------
  // Each armed vector indexes a 2-byte little-endian target offset at
  //   vtable_base + (vector_index * VTABLE_ENTRY_BYTES)
  // inside the SRAM; the fetched offset joins the safe-RAM bank to form the
  // redirect target. (Model; entry width per doc 07/09.)
  localparam int VTABLE_ENTRY_BYTES   = 2;
  localparam int XBAND_NUM_VECTORS    = 11;          // Vector0..VectorA

  // ---- FRED register byte offsets (index << 1) ----------------------------
  // control / kill
  localparam logic [8:0] REG_KILL          = 9'h000; // 0x00<<1
  localparam logic [8:0] REG_CONTROL       = 9'h002; // 0x01<<1
  // patch / mapping
  localparam logic [8:0] REG_RANGE_LOW     = 9'h080; // 0x40<<1
  localparam logic [8:0] REG_RANGE_MID     = 9'h082; // 0x41<<1
  localparam logic [8:0] REG_RANGE_HIGH    = 9'h084; // 0x42<<1
  localparam logic [8:0] REG_TRB_LOW       = 9'h0A0; // 0x50<<1
  localparam logic [8:0] REG_TRB_HIGH      = 9'h0A2; // 0x51<<1
  localparam logic [8:0] REG_TR_MID        = 9'h0A4; // 0x52<<1
  localparam logic [8:0] REG_SAFERAM_BLO   = 9'h0C0; // 0x60<<1
  localparam logic [8:0] REG_SAFERAM_BHI   = 9'h0C2; // 0x61<<1
  localparam logic [8:0] REG_SAFERAM_NLO   = 9'h0C8; // 0x64<<1
  localparam logic [8:0] REG_SAFERAM_NHI   = 9'h0CA; // 0x65<<1
  localparam logic [8:0] REG_VTABLE_LOW    = 9'h0D0; // 0x68<<1
  localparam logic [8:0] REG_VTABLE_HIGH   = 9'h0D2; // 0x69<<1
  localparam logic [8:0] REG_ENABLE_LOW    = 9'h0D8; // 0x6C<<1
  localparam logic [8:0] REG_ENABLE_HIGH   = 9'h0DA; // 0x6D<<1
  localparam logic [8:0] REG_SAFEROM_BND   = 9'h0E0; // 0x70<<1
  localparam logic [8:0] REG_SAFEROM_BASE  = 9'h0E8; // 0x74<<1
  localparam logic [8:0] REG_ADDRSTAT_LOW  = 9'h0F8; // 0x7C<<1
  localparam logic [8:0] REG_ADDRSTAT_HIGH = 9'h0FA; // 0x7D<<1
  // LED port
  localparam logic [8:0] REG_LED_DATA      = 9'h168; // 0xB4<<1
  localparam logic [8:0] REG_LED_ENABLE    = 9'h16A; // 0xB5<<1
  // modem / serial
  localparam logic [8:0] REG_SCONTROL      = 9'h100; // 0x80<<1
  localparam logic [8:0] REG_SCONTROL2     = 9'h104; // 0x82<<1
  localparam logic [8:0] REG_SSTATUS       = 9'h108; // 0x84<<1
  localparam logic [8:0] REG_MVSYNC_LOW    = 9'h110; // 0x88<<1
  localparam logic [8:0] REG_MVSYNC_HIGH   = 9'h112; // 0x89<<1
  localparam logic [8:0] REG_MSTATUS1_W    = 9'h118; // 0x8C<<1
  localparam logic [8:0] REG_TXBUFF        = 9'h120; // 0x90<<1
  localparam logic [8:0] REG_RXBUFF        = 9'h128; // 0x94<<1
  localparam logic [8:0] REG_MSTATUS2_R    = 9'h130; // 0x98<<1
  localparam logic [8:0] REG_SERIALVCNT    = 9'h138; // 0x9C<<1
  localparam logic [8:0] REG_READMSTATUS1  = 9'h140; // 0xA0<<1
  localparam logic [8:0] REG_GUARD         = 9'h148; // 0xA4<<1
  localparam logic [8:0] REG_BCNT          = 9'h150; // 0xA8<<1
  localparam logic [8:0] REG_MSTATUS2_W    = 9'h158; // 0xAC<<1
  localparam logic [8:0] REG_VSYNC_WRITE   = 9'h160; // 0xB0<<1

  // ---- control register bits ----------------------------------------------
  localparam logic [7:0] CTL_EN_SEGA_EXC   = 8'h40;
  localparam logic [7:0] CTL_EN_SNES_EXC   = 8'h20;
  localparam logic [7:0] CTL_EN_FIXED_INT  = 8'h10;
  localparam logic [7:0] CTL_EN_INTERNAL   = 8'h08;
  localparam logic [7:0] CTL_ROM_HI        = 8'h04;
  localparam logic [7:0] CTL_EN_SAFE_ROM   = 8'h02;
  localparam logic [7:0] CTL_EN_TWO_RAM    = 8'h01;

  // ---- kill register bits -------------------------------------------------
  localparam logic [7:0] KILL_HERE_ASSERT  = 8'h01; // cart NOT visible (FRED owns bus)
  localparam logic [7:0] KILL_DEC_EXCEPT   = 8'h04;
  localparam logic [7:0] KILL_FORCE        = 8'h08;

  // ---- enable register bits (kEnableHigh:kEnableLow) -----------------------
  localparam logic [7:0] ENH_ZEROPAGE      = 8'h80;
  localparam logic [7:0] ENH_TRANSADDR     = 8'h40;
  localparam logic [7:0] ENH_VECTOR_A      = 8'h04;
  localparam logic [7:0] ENH_VECTOR_9      = 8'h02;
  localparam logic [7:0] ENH_VECTOR_8      = 8'h01;
  // ENABLE_LOW bits are Vector7..Vector0 = 0x80..0x01

  // ---- reset / self-test invariants (fredtest.c) --------------------------
  localparam logic [7:0] RST_READMSTATUS1  = 8'h02; // modem idle
  localparam logic [7:0] RST_ADDRSTAT_LOW  = 8'h00; // no floating addr bits
  localparam logic [7:0] RST_LED_DATA      = 8'h7F; // 7 LEDs present

  // ---- video-locked modem timing (defines.h) ------------------------------
  localparam int VCNTS_PER_MODEM_BIT = 5;     // 1 modem bit ~= 5 VCnt ticks
  localparam int LINES_PER_MODEM_BIT = 7;     // ~= 7 horizontal lines / bit
  localparam logic [7:0] VCNT_FIRST  = 8'h5C;
  localparam logic [7:0] VCNT_LAST   = 8'h5B;
  localparam logic [7:0] VCNT_MAX    = 8'h61;

endpackage : xband_pkg
