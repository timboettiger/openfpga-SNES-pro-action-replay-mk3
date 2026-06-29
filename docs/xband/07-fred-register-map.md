# 07 — FRED Register Map

This is the most valuable single artefact for building an XBAND **core**: the
register map of the FRED ASIC, taken verbatim from Catapult's own diagnostic
sources:

```
catapult.tar.gz → Catapult/Box-16bit-Feb96/Tools/ModemTester/defines.h
                  Catapult/Box-16bit-Feb96/Tools/ModemTester/fredtest.c
```

## Addressing convention

Register offsets in `defines.h` are written as `(<index> << 1)` — i.e. registers
sit on **even byte addresses** (the data bus is 16-bit; each register is one
even-addressed location). The constants below show the raw `index` and the
resulting byte offset `index<<1`.

FRED's base in the dev environment:
```
kFredBase   = 0x003BC001
kRamBase    = 0xE0000000      kRomBase = 0xE1000000
kCartHole   = 0x200           kRomSize = 0x80000  (512 KB)
```
`READ_REG/WRITE_REG` operate at `kFredBase + offset`; the box accesses these
through the cartridge address space.

## Control & kill registers (bus arbitration)

| Name           | index | offset | Purpose                                    |
| -------------- | ----- | ------ | ------------------------------------------ |
| `kKillReg`     | 0x00  | 0x00   | Kill register (must work via WRITE_REG)    |
| `kControlReg`  | 0x01  | 0x02   | Control register (must work via WRITE_REG) |
| `kSoftOffset`  | 0xC0  | 0x180  | "soft" register window offset              |
| `kKillHereSoft`| 0xC0  | 0x180  | soft kill                                  |
| `kCtlRegSoft`  | 0xC1  | 0x182  | soft control                               |

**Control-register bits** (`kControlReg`):

| Bit    | Name              | Meaning                          |
| ------ | ----------------- | -------------------------------- |
| `0x40` | `kEnSegaExcept`   | enable Sega exception handling   |
| `0x20` | `kEnSNESExcept`   | enable SNES exception handling   |
| `0x10` | `kEnFixedInternal`| fixed-internal mapping enable    |
| `0x08` | `kEnInternal`     | internal mapping enable          |
| `0x04` | `kRomHi`          | map ROM high                     |
| `0x02` | `kEnSafeRom`      | enable "safe ROM" range          |
| `0x01` | `kEnTwoRam`       | enable two-RAM mode              |

**Kill-register bits** (`kKillReg`):

| Bit    | Name          | Meaning                                  |
| ------ | ------------- | ---------------------------------------- |
| `0x01` | `kHereAssert` | "Here" — the cartridge **cannot** be seen (FRED owns the bus) |
| `0x04` | `kDecExcept`  | decode exception                          |
| `0x08` | `kForce`      | force                                     |

## Patch / mapping registers (the patch engine)

These define where FRED redirects accesses — the actual game-patching mechanism.

| Name                | index | offset | Purpose                                |
| ------------------- | ----- | ------ | -------------------------------------- |
| `kDefaultInternal`  | 0x1DE000 | —   | default internal region base            |
| `kDefaultControl`   | 0x1DFF00 | —   | default control region base             |
| `kRangeLow/Mid/High`| 0x40/41/42 | 0x80/82/84 | mapped address range                |
| `kTrBLow/High`,`kTrMid` | 0x50/51/52 | 0xA0/A2/A4 | translation base (where the range maps to) |
| `kSafeRamBaseLow/High` | 0x60/61 | 0xC0/C2 | "safe RAM" base                       |
| `kSafeRamBoundsLow/High` | 0x64/65 | 0xC8/CA | "safe RAM" bounds                   |
| `kVTableLow/High`   | 0x68/69 | 0xD0/D2 | patch-vector table base                 |
| `kEnableLow/High`   | 0x6C/6D | 0xD8/DA | per-vector + mode enables (see below)   |
| `kSafeRomBounds`    | 0x70    | 0xE0   | "safe ROM" bounds                       |
| `kSafeRomBase`      | 0x74    | 0xE8   | "safe ROM" base                         |
| `kAddrStatusLow/High` | 0x7C/7D | 0xF8/FA | address-status read-back (diagnostics)|

**Enable bits** (`kEnableHigh:kEnableLow`, 16 bits):

| Reg          | Bit    | Name              |
| ------------ | ------ | ----------------- |
| `kEnableHigh`| `0x80` | `kzeroPageEnable` |
| `kEnableHigh`| `0x40` | `ktransAddrEnable`|
| `kEnableHigh`| `0x04` | `kVectorAEna`     |
| `kEnableHigh`| `0x02` | `kVector9Ena`     |
| `kEnableHigh`| `0x01` | `kVector8Ena`     |
| `kEnableLow` | `0x80` | `kVector7Ena`     |
| `kEnableLow` | `0x40` | `kVector6Ena`     |
| `kEnableLow` | `0x20` | `kVector5Ena`     |
| `kEnableLow` | `0x10` | `kVector4Ena`     |
| `kEnableLow` | `0x08` | `kVector3Ena`     |
| `kEnableLow` | `0x04` | `kVector2Ena`     |
| `kEnableLow` | `0x02` | `kVector1Ena`     |
| `kEnableLow` | `0x01` | `kVector0Ena`     |

So FRED exposes **11 patch vectors** (Vector0…VectorA) plus a **zero-page**
remap and a **trans-address** remap, each independently enabled. A downloaded
patch programs the vector table (`kVTable*`), the source range (`kRange*`), the
destination (`kTr*`), turns on the relevant `kVectorNEna` bits, and arms safe
RAM/ROM bounds so the injected code can run from SRAM.

## LED port

| Name         | index | offset | Purpose                          |
| ------------ | ----- | ------ | -------------------------------- |
| `kLEDData`   | 0xB4  | 0x168  | front-panel LED data (R/W)       |
| `kLEDEnable` | 0xB5  | 0x16A  | LED direction (1 = output)       |

`fredtest.c` confirms behaviour: after reset `READ_REG(kLEDData) & 0xFF == 0x7F`
(7 LEDs), `kReadMStatus1 & 0xFF == 0x02` is the expected modem-status idle value,
and `kAddrStatusLow == 0x00`. These are good RTL reset/self-test invariants.

## Modem / serial registers

| Name              | index | offset | Purpose                                          |
| ----------------- | ----- | ------ | ------------------------------------------------ |
| `kModemBase`      | 0xC0  | 0x180  | modem register window base                       |
| `kTxBuff`         | 0x90  | 0x120  | transmit FIFO                                    |
| `kRxBuff`         | 0x94  | 0x128  | receive FIFO                                     |
| `kReadMStatus1`   | 0xA0  | 0x140  | modem status 1 (idle = 0x02)                     |
| `kReadMStatus2`   | 0x98  | 0x130  | modem status 2                                   |
| `kMStatus1`       | 0x8C  | 0x118  | modem status 1 (write/control side)              |
| `kMStatus2`       | 0xAC  | 0x158  | modem status 2 (write/control side)              |
| `kBCnt`           | 0xA8  | 0x150  | byte count                                       |
| `kGuard`          | 0xA4  | 0x148  | guard                                            |
| `kVSyncWrite`     | 0xB0  | 0x160  | vsync write                                      |
| `kReadMVSyncLow`  | 0x88  | 0x110  | vsync counter low                                |
| `kReadMVSyncHigh` | 0x89  | 0x112  | vsync counter high (0…0x61 = ReadSerialVCnt/2)   |
| `kReadSerialVCnt` | 0x9C  | 0x138  | top 8 bits of a 19-bit clock counter             |
| `kSControl`       | 0x80  | 0x100  | serial control                                   |
| `kSControl2`      | 0x82  | 0x104  | serial control 2                                 |
| `kSStatus`        | 0x84  | 0x108  | serial status                                    |

### Modem timing constants (video-locked!)

```
kVCntsPerModemBit  = 5     // 1 modem bit (1/2400 s ≈ 417 µs) ≈ 5 VCnt ticks
kLinesPerModemBit  = 7     // ≈ 7 horizontal lines per modem bit
kFirstVCnt = 0x5C  kLastVCnt = 0x5B  kMaxVCnt = 0x61  kMinVCnt = 0x00
// ReadSerialVCnt increments once every 2048 input clocks (≈85.33 µs @ 24 MHz)
// ReadMVSyncHigh ≈ 0x5C at start of vblank; ≈0xB8 → 0xC3 then wraps to 0
```

A faithful RTL model **must** derive the modem byte clock from the video
timebase, not a free-running baud generator. This is the central timing fact for
an XBAND core.

### Receive flow (from the `defines.h` comments)

```
// for rx:
//   1. read status until rxready
//   2. read kRxBuff
// note: if the read FIFO is empty, ReadSerialVCnt reads back the value of
//       ReadMVSyncHigh (i.e. half the normal resolution).
```

## Self-test invariants (handy for RTL bring-up)

From `fredtest.c`, immediately after `RESET_CARD`:

| Register                  | Expected | Meaning                       |
| ------------------------- | -------- | ----------------------------- |
| `kReadMStatus1 & 0xFF`    | `0x02`   | modem idle                    |
| `kAddrStatusLow & 0xFF`   | `0x00`   | no floating address bits      |
| `kLEDData & 0xFF`         | `0x7F`   | 7 LEDs present                |
| write `kLEDData=0xFF`, `kLEDEnable=0xFF`, read back | `0x00` after clearing | WR1 path works |

The diagnostic also probes the cartridge by writing `0xDEAD`/`0xF00D` to
`kCartHole` and reading it back — a good model of how FRED arbitrates the
pass-through cart.
