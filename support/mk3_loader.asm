// =============================================================================
// PAR MK3 SNES chip32 VM loader
// =============================================================================
//
// Based on agg23's vanilla loader.asm, with one addition: open + loadf for the
// MK3 BIOS at slot 100 (and the cheat save at slot 11) before host_init. The
// BIOS/cheat loaders in core_top.sv write their own SDRAM regions, so they
// need no ioctl_download toggle (that only gates the cart's data_loader).
//
// =============================================================================
// chip32 assembler quirks (bass-chip32 from open-fpga/bass-chip32):
//   - Operand separator is comma WITHOUT a trailing space
//     `ld r1,#42` is valid;  `ld r1, #42` breaks parsing.
//   - String literals end with an explicit 0 byte.
//   - align(2) keeps following code word-aligned.
//   - DEBUG=0 strips log_string macros to save instruction memory.
// =============================================================================

architecture chip32.vm
output "loader.bin", create

constant DEBUG = 0

constant rom_dataslot  = 0
constant save_dataslot = 10
constant mk3_save_dataslot = 11      // MK3 cheat-list SRAM (.mk3sav, bridge $40000000)
constant bios_dataslot = 100

constant bios_required_size = 0x20000   // exactly 128 KB

// Host init command (signals Pocket framework "core is ready")
constant host_init = 0x4002

// Scratch RAM addresses (must not collide with chip32 stack/etc.)
constant rom_file_size      = 0x1000
constant header_offset_addr = 0x1004

constant lorom_header_seek   = 0x007FBD
constant hirom_header_seek   = 0x00FFBD
constant exhirom_header_seek = 0x40FFBD

constant lorom_output   = 0x1A00
constant hirom_output   = 0x1A10
constant exhirom_output = 0x1A20

constant romsz_addr = 0x1800

// ===== Vector table (must be at PC 0x00 and 0x02) =====
// chip32 framework jumps to the init vector at PC 0x02 on startup.
// The error vector at PC 0x00 is taken on internal VM faults.

// PC 0x00: error vector
jp error_handler

// PC 0x02: init vector (entry point)
jp start

// ===== Includes =====
// util.asm provides log_string / hex.b / hex.l / seek / read macros,
// plus the seek_err / read_err strings at the bottom of the file.
include "util.asm"
align(2)

// check_header.asm provides the LoROM/HiROM/ExHiROM scoring macro and
// the underlying helper subroutines (load_header_values_into_mem,
// validate_checksum, validate_simple_values, choose_ramsz, choose_chip_type,
// choose_region).
include "check_header.asm"
align(2)

// =============================================================================
// Main flow: open cart, detect SMC header, score Lo/Hi/ExHiROM, send ROM info
// via pmpw, stream cart + save, then (MK3) the BIOS at slot 100 and cheat save
// at slot 11, then host_init.
// =============================================================================

start:
  ld r1,#rom_dataslot                    // populate cart data slot (slot 0)
  open r1,r2

  ld.l (rom_file_size),r2
  and r2,#0x200                          // AND with 0x200: SMC header bit
  jp z, no_header                        // If zero, no header
  log_string("File has header")
  jp store_header

no_header:
  log_string("File doesn't have header")

store_header:
  ld.w (header_offset_addr),r2           // Store header offset (0 or 0x200)

// ----- Calculate romsz (log2 of file size in MB, 15 = max) -----
  ld r1,#15
  ld r2,#0x1000000                       // Max ROM size
  ld.l r3,(rom_file_size)                // ROM file size
  ld.w r4,(header_offset_addr)           // Header offset
  sub r3,r4                              // Remove header from size

rom_size_loop:
  cmp r1,#0
  jp z, finished_rom_size                // If romsz reaches 0
  cmp r2,r3
  jp c, finished_rom_size                // If size > r2 (current max)
  asl r3,#1                              // Else shift size left 1
  sub r1,#1                              // Subtract 1 from rom size
  jp rom_size_loop

finished_rom_size:
  ld.b (romsz_addr),r1
  log_string("Calculated ROM size:")
  hex.b r1

// ----- Score the three possible header locations -----
  check_header(lorom_header_seek, lorom_output)

  ld.l r2,(rom_file_size)
  cmp r2,#0xFFFF
  jp c, finished_checking_headers        // If ROM < 64 KB, skip HiROM check
  check_header(hirom_header_seek, hirom_output)

  ld.l r2,(rom_file_size)
  ld r3,#0x40
  asl r3,#16
  or r3,#0xFFFF                          // r3 = 0x40FFFF
  cmp r2,r3
  jp c, finished_checking_headers        // If ROM < 0x40FFFF, skip ExHiROM check

  check_header(exhirom_header_seek, exhirom_output)

// ----- Compare scores and pick the best -----
finished_checking_headers:
  close                                  // Close cart file (re-open with loadf later)

  ld.b r1,(lorom_output)                 // LoROM score
  ld.b r2,(hirom_output)                 // HiROM score
  ld.b r3,(exhirom_output)               // ExHiROM score
  jp z,compare_scores                    // If ExHiROM has a score
  add r3,#4                              // Weight ExHiROM extra

compare_scores:
  cmp r1,r2                              // r1 - r2
  jp c, check_hirom_score                // jp if HiROM >= LoROM
  cmp r1,r3                              // r1 - r3
  jp c, check_hirom_score                // jp if ExHiROM >= LoROM

  // LoROM wins
  log_string("Choosing LoROM")
  ld.b r1,(lorom_output + 1)             // chip_type
  ld.b r2,(lorom_output + 2)             // RAMSZ
  ld.b r3,(lorom_output + 3)             // PAL
  jp set_core

check_hirom_score:
  cmp r2,r3
  jp c, score_exhi                       // jp if ExHiROM >= HiROM

  log_string("Choosing HiROM")
  ld.b r1,(hirom_output + 1)
  or r1,#1                               // Mark HiROM in chip_type
  ld.b r2,(hirom_output + 2)
  ld.b r3,(hirom_output + 3)
  jp set_core

score_exhi:
  log_string("Choosing ExHiROM")
  ld.b r1,(exhirom_output + 1)
  or r1,#2                               // Mark ExHiROM in chip_type
  ld.b r2,(exhirom_output + 2)
  ld.b r3,(exhirom_output + 3)

// ----- Load the (single) bitstream -----
// One bitstream only; PAL timing is handled at run time via the PAL flag
// (pmpw 0x10), so we never switch cores. PAL games run at NTSC timing.
// Inputs preserved: r1=chip_type, r2=RAMSZ, r3=PAL.
set_core:
  log_string("Setting core (single bitstream)")
  ld r8,#0
  core r8                                // Always load our one bitstream

send_chip:
  log_string("Sending chip type")
  ld r8,#8                               // bridge addr 0x08 = ROM_TYPE
  pmpw r8,r1

  log_string("Sending ROM size")
  ld.b r7,(romsz_addr)
  ld r8,#4                               // bridge addr 0x04 = ROM_SIZE
  pmpw r8,r7

  log_string("Sending RAMSZ")
  ld r8,#0xC                             // bridge addr 0x0C = RAM_SIZE
  pmpw r8,r2

  log_string("Sending PAL")
  ld r8,#0x10                            // bridge addr 0x10 = PAL
  pmpw r8,r3

// ===== Stream the cart ROM bytes =====
  log_string("Booting")
  ld r1,#0                               // bridge addr 0x00 = ioctl_download
  ld r2,#1
  pmpw r1,r2                             // ioctl_download = 1

  ld r1,#rom_dataslot
  ld.w r2,(header_offset_addr)
  adjfo r1,r2                            // Offset file pointer past SMC header
  loadf r1                               // Stream cart bytes through bridge_wr

  ld r1,#0
  ld r2,#0
  pmpw r1,r2                             // ioctl_download = 0

// ===== Stream the save (BSRAM) bytes (agg23 does this unconditionally) =====
  ld r1,#0
  ld r2,#1
  pmpw r1,r2                             // ioctl_download = 1

  ld r1,#save_dataslot
  loadf r1                               // Stream save bytes (may be empty)

  ld r1,#0
  ld r2,#0
  pmpw r1,r2                             // ioctl_download = 0

// ===== Stream the MK3 BIOS bytes (slot 100) =====
// mk3_bios_loader writes its own SDRAM region (BIOS_BASE = 0x800000), so the
// cart's ioctl_download gate does not apply. chip32 won't loadf a slot that's
// still OPEN, so close after the size check and before streaming. Verify the
// 128 KB size first for a clean diagnostic if the BIOS is missing or short.

  log_string("Loading MK3 BIOS")
  ld r1,#bios_dataslot
  open r1,r2                             // r2 = file size, Z flag = success
  jp nz,bios_missing                     // (Z=1 on success, agg23 convention)

  ld r3,#bios_required_size
  cmp r2,r3
  jp nz,bios_wrong_size

  close                                  // MUST close before loadf
  ld r1,#bios_dataslot                   // reload slot id (open clobbered r1? safe to reset)
  loadf r1                               // Stream BIOS bytes into SDRAM @ 0x800000

// ===== Stream the MK3 cheat save (slot 11), the persistence restore =====
// Restores the saved cheat list into MK3 SRAM; without it the BIOS cold-inits
// and wipes the list every boot. mk3_save_data_loader has its own SDRAM region
// ($40000000), so no ioctl_download toggle. Optional slot: a missing .mk3sav
// just streams nothing and the BIOS cold-inits.
  log_string("Loading MK3 cheat save (slot 11)")
  ld r1,#mk3_save_dataslot
  loadf r1                               // Stream .mk3sav back into MK3 SRAM @ $40000000

// ===== Signal "core ready" to Pocket framework =====
  log_string("host_init")
  ld r0,#host_init
  host r0,r0

  exit 0

// ===== Error paths =====
bios_missing:
  ld r14,#bios_missing_msg
  printf r14
  exit 1

bios_wrong_size:
  ld r14,#bios_wrong_size_msg
  printf r14
  hex.l r2
  exit 1

error_handler:
  ld r14,#generic_error_msg
  printf r14
  exit 1

// ===== Strings =====
bios_missing_msg:
  db "Place a verified PAR MK3 BIOS dump (128 KB) at",10
  db "/Assets/snes/timboettiger.Pro Action Replay/",10
  db "snes-pro-action-replay-mk3.bin",10
  db "and re-launch the core.",0
align(2)

bios_wrong_size_msg:
  db "BIOS must be exactly 128 KB (0x20000 bytes). Got 0x",0
align(2)

generic_error_msg:
  db "MK3 loader: unknown error",0
align(2)
