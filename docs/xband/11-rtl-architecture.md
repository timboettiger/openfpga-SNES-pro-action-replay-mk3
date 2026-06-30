# 11 — RTL Architecture & ROM Embedding

This page specifies how to represent XBAND as RTL inside (or alongside) this
Pocket SNES core, and how the BIOS ROM is embedded. A **reference skeleton** that
implements these interfaces lives in [`rtl/`](rtl/). The skeleton is a
*specification in HDL form* — synthesizable module shells with the correct ports,
parameters, register decode and memory blocks. The mapper gating, the FRED
patch-vector datapath and the modem bridge are **implemented as behavioural
models** of the documented register behaviour (they lint clean and pass a
self-checking testbench); the SNES decode is now **confirmed HiROM** against the
real 1 MB BIOS (doc 13), the per-vector table walk and safe-ROM overlay are
modelled, and the only remaining hardware-specific work is the analog modem PHY.
It is
intentionally **not wired into the Pocket build** (`gateware.json` / the `*.qip`
lists are untouched) so it can be lifted into another project — e.g. an
`fxpakpro` XBAND extension — without disturbing this core's bitstream.

## Design goals

1. **Mirror the MK3 add-on pattern.** This repo already models a cartridge-slot
   add-on chip with its own ROM, SRAM and memory-mapped registers under
   `rtl/chip/mk3/`. XBAND is the same shape; reuse that structure
   (mapper + io + sram + top), see [08-bios-and-roms.md](08-bios-and-roms.md).
2. **Faithful FRED register decode.** Implement the register map from
   [07-fred-register-map.md](07-fred-register-map.md) exactly (offsets, reset
   values, self-test invariants).
3. **Video-locked modem timing.** Derive the serial bit-clock from the SNES
   video timebase (`kVCntsPerModemBit = 5`, `kLinesPerModemBit = 7`), not a free
   baud generator — this is the defining XBAND timing constraint.
4. **Tunnelable modem.** Abstract the modem behind a clean byte FIFO so the PHY
   can be (a) a real Rockwell model, or (b) a serial tunnel to an external
   bridge (ESP32 over the Pocket link port — see
   [12-link-cable-esp32.md](12-link-cable-esp32.md)).
5. **No proprietary binary committed.** The ROM arrives via a Pocket data slot.

## Module decomposition

```
xband_top.sv            top: clocks, reset, wiring, mode select
├── xband_mapper.sv     cartridge-address decode → {BIOS, game ROM, SRAM, FRED regs}
├── xband_fred_regs.sv  FRED register file (control/kill/patch-vectors/LED/modem)
├── xband_fred_patch.sv FRED patch engine: 11 vectors + zero-page/trans-addr remap
├── xband_sram.sv       64 KB battery SRAM (dual-port: SNES side + save channel)
├── xband_modem_uart.sv 16550-style byte interface + Tx/Rx FIFOs (PHY-agnostic)
└── xband_modem_timing.sv  VCnt / VSync counters; video-locked bit clock
```

This maps 1:1 onto the schematic blocks in [03-schematics.md](03-schematics.md)
(FRED, SRAM, Rockwell modem, serial) and onto the MK3 file layout
(`mk3_mapper.sv`, `mk3_io.sv`, `mk3_sram.vhd`, `mk3_snes_top.sv`).

## Memory map (SNES side, HiROM — confirmed against the 1 MB BIOS)

The retail decode has been confirmed by reverse-engineering the real dump (see
[13-rom-memory-map.md](13-rom-memory-map.md)): the cartridge is **HiROM**
(`mapmode 0x31`, 1 MB, 64 KB battery SRAM, checksum-valid).

| SNES address window               | Target                                |
| --------------------------------- | ------------------------------------- |
| `$C0-$FF : $0000-$FFFF`           | XBAND **BIOS** (HiROM, 1 MB mirrored) |
| `$00-$3F / $80-$BF : $8000-$FFFF` | XBAND **BIOS** upper-half (or game ROM via FRED) |
| `$E0 : $0000-$FFFF`               | XBAND **SRAM** (64 KB linear)         |
| `$20-$3F : $6000-$7FFF`           | XBAND **SRAM** small window           |
| FRED register window (cart space) | **FRED registers** (offsets per doc 07)|
| pass-through                      | the **game ROM** in the top socket    |

> Boot: emulation RESET `$FFE0` → `JML $D0:0000` → native-mode init at file 0.
> `kRomHi` swaps the lower-512 KB **code** half ↔ the upper-512 KB **asset** half
> of the 1 MB image. The reference mapper (`rtl/xband_mapper.sv`) implements this
> HiROM decode.

## ROM-embedding interface (matches `rtl/main.v` MK3 style)

```systemverilog
// Load path (driven by a core_top.sv data-slot loader):
input         XBAND_BIOS_WE;
input  [19:0] XBAND_BIOS_LOAD_ADDR;   // 1 MB
input  [7:0]  XBAND_BIOS_LOAD_DIN;
// Read-back path (mapper asserts a request, byte returns next cycle):
output        XBAND_BIOS_READ;
output [19:0] XBAND_BIOS_READ_ADDR;
input  [7:0]  XBAND_BIOS_DOUT;
// 64 KB battery SRAM save channel (independent of the SNES R/W port):
input         XBANDSV_WR;  input  [15:0] XBANDSV_ADDR_IN;  input  [7:0] XBANDSV_DOUT;
input         XBANDSV_RD;  input  [15:0] XBANDSV_ADDR_OUT; output [7:0] XBANDSV_DIN;
```

The BIOS bytes come from a new Pocket **data slot** (declared in the core's
`data.json`), exactly as the MK3 BIOS uses asset slot 100; the SRAM persists via
a new **save slot**, exactly as the MK3 cheat SRAM uses Pocket slot 11. **Nothing
is baked into the bitstream.**

## What is fully specified vs. still open

| Block                  | Status in skeleton                                            |
| ---------------------- | ------------------------------------------------------------- |
| Register decode/offsets| **Specified** — straight from `defines.h` (doc 07)            |
| Reset / self-test values| **Specified** — `fredtest.c` invariants (doc 07)            |
| BIOS load/read iface   | **Specified** — mirrors MK3 (`rtl/main.v`)                    |
| 64 KB SRAM             | **Specified** — dual-port BRAM shell                          |
| Modem byte FIFO + AT   | **Specified** — 16550-style register interface                |
| Mapper BIOS/game gating| **Implemented** — `kHereAssert`/`kRomHi` + patch redirect     |
| Modem PHY (Rockwell)   | **Implemented as bridge** — paced byte tunnel; analog pump external |
| FRED patch datapath    | **Implemented (model)** — range/zero-page remap, enables, safe-RAM bounds, per-vector table walk + safe-ROM |
| SNES decode specifics  | **Confirmed** — HiROM, validated against the 1 MB BIOS (doc 13) |
| Per-vector table walk  | **Implemented (model)** — vtable entries fetched from SRAM      |

## Verification strategy

- Replay the captured `MK_PUKE` / `MK2_PUKE` byte streams (from `xbsega.go`)
  through the modem FIFO and check the handshake/CRC path
  ([04](04-network-protocol.md)).
- Assert the `fredtest.c` reset invariants in a self-checking testbench (doc 07).
- Bring up the LED port first (it has known reset value `0x7F`) — it is the
  simplest observable FRED function and maps to the same on-screen LED OSD the
  MK3 core already renders.
