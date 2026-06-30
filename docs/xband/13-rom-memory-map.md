# 13 — XBAND BIOS ROM: verified memory map

This page is the **reverse-engineered, verified memory map of the retail SNES
XBAND BIOS**. Unlike most of this folder (which is distilled from Catapult's
recovered *source*), everything below was checked directly against the actual
1 MB dump that ships inside the
[`platform/xband`](../../platform/xband) submodule
(`X-Band Modem BIOS (USA).zip`). The binary itself is proprietary and is **not**
committed (see [08-bios-and-roms.md](08-bios-and-roms.md)); only these
*measurements* are.

Every value in the "verified" sections is reproducible with the recipe in
[§7](#7-reproduce-the-verification). The proprietary dump only needs to be
present **temporarily** to re-run it.

## 1. File identity (verified)

| Property            | Value                                            |
| ------------------- | ------------------------------------------------ |
| File name           | `X-Band Modem BIOS (USA).sfc`                     |
| Size                | `1,048,576` bytes (1 MB, no 512-byte copier header) |
| CRC32               | `A8B868A0`                                        |
| MD5                 | `580b6f738cd9d3cfea514b20c4cbb440`                |
| SHA-1               | `3f56b109a05097f09fd8859205ea635453d1cb45`        |
| Date in ZIP         | 1996-12-24                                        |

The image is a raw, headerless SNES mask-ROM dump: `size % 1024 == 0` and there
is no 0x200-byte copier prologue (the internal header lands exactly at `$FFC0`).

## 2. Internal SNES header @ `$FFC0` (verified)

The dump carries a **valid HiROM header** at `$FFC0` and its checksum is
self-consistent, which is the single strongest proof that the mapping below is
correct.

| Field            | Offset  | Raw     | Decoded                                  |
| ---------------- | ------- | ------- | ---------------------------------------- |
| Title (21 bytes) | `$FFC0` | —       | `XBAND VIDEOGAME MODEM` (padded)         |
| Map mode         | `$FFD5` | `0x31`  | **HiROM + FastROM** (`0x30` fast \| `0x01` hi) |
| Cartridge type   | `$FFD6` | `0x02`  | ROM + RAM + **battery**                  |
| ROM size         | `$FFD7` | `0x0A`  | `1 << 10` KB = **1024 KB = 1 MB** ✔ matches file |
| RAM (SRAM) size  | `$FFD8` | `0x06`  | `1 << 6` KB = **64 KB** battery SRAM      |
| Country          | `$FFD9` | `0x01`  | USA / NTSC                                |
| Licensee         | `$FFDA` | `0x33`  | "use extended header at `$FFB0`"          |
| Version          | `$FFDB` | `0x00`  | v1.0                                      |
| Checksum compl.  | `$FFDC` | `0xE5A2`| —                                        |
| Checksum         | `$FFDE` | `0x1A5D`| `compl ^ checksum == 0xFFFF` ✔            |

**Checksum verification.** The 16-bit sum of *all* 1,048,576 bytes is `0x1A5D`,
exactly equal to the stored checksum, and `0x1A5D ^ 0xE5A2 == 0xFFFF`. The ROM is
intact and the header is authoritative.

### Extended header @ `$FFB0` (licensee `0x33`)

| Field           | Offset  | Value    |
| --------------- | ------- | -------- |
| Maker code      | `$FFB0` | `"69"`   |
| Game code       | `$FFB2` | `"XBND"` |
| Expansion RAM   | `$FFBD` | `0x00`   |
| Special version | `$FFBE` | `0x00`   |
| Chipset subtype | `$FFBF` | `0x00`   |

## 3. Address mapping (HiROM, verified)

`mapmode = 0x31` ⇒ standard **HiROM**. The 1 MB image occupies 16 banks of ROM
and mirrors to fill the HiROM ROM space.

```
ROM (1 MB, file offset = (bank & 0x3F) * 0x10000 + offset, HiROM):
  $C0–$FF : $0000–$FFFF   full 64 KB banks → ROM   ($C0=file 0 … $CF=file 0xF0000)
  $00–$3F : $8000–$FFFF   upper half       → ROM   (mirrors $C0–$FF top half)
  $80–$BF : $8000–$FFFF   upper half       → ROM   (FastROM image of the above)

  Because the image is 16 banks (1 MB), banks repeat every 16: $D0–$DF mirrors
  $C0–$CF, $E0–$EF mirrors $C0–$CF again, etc. (subject to FRED overriding the
  SRAM/register region — see below).

SRAM (64 KB, battery-backed):
  The header declares 64 KB. The BIOS reads its work area through bank $E0 (a
  long read `LDA $E0:0000` appears in the very first init routine), i.e. the
  64 KB SRAM is presented linearly at bank $E0 ($E0:0000–$E0:FFFF). The classic
  HiROM SRAM window $20–$3F : $6000–$7FFF is also decoded for the small-window
  accesses. Catapult's dev `defines.h` corroborates the low 24 bits of its RAM
  base (`kRamBase` → `$E0:0000`) and ROM base (`kRomBase` → `$E1:0000`).
```

`kRomHi` (control-register bit `0x04`, see [07](07-fred-register-map.md)) selects
which **512 KB half** of the 1 MB image is exposed in the running code's window.
This is consistent with the dev environment's `kRomSize = 0x80000` (512 KB)
window and with the physical split measured in [§5](#5-region-layout-verified):
the lower 512 KB is the executable BIOS, the upper 512 KB is read-only assets.

## 4. Reset & vector table (verified)

SNES powers on in emulation mode and fetches the **emulation RESET** vector from
`$00:FFFC`.

```
$FFFC  RESET (emu) = $FFE0
  @ $FFE0 : 5C 00 00 D0      JML $D0:0000      ; → bank $D0 (mirror of $C0/file 0)
  @ $D0:0000 (file 0):
        22 25 0A D0          JSL $D0:0A25      ; mode init
  @ $D0:0A25 (file 0x0A25):
        18 FB                CLC : XCE         ; → native (65816) mode
        C2 30                REP #$30          ; 16-bit A/X/Y
        …                                      ; clears, then LDA $E0:0000 (SRAM probe)
```

So the real entry point is **file offset 0** (`$C0:0000`, executed via the
`$D0` mirror); the emulation reset vector is just a `JML` trampoline into it.

### Vector table contents

Emulation vectors (`$FFF4–$FFFF`) are short `JML`-into-`$D0` trampolines living
just below the header (`$FF94–$FFBF`):

| Emu vector | Value   | Trampoline does          |
| ---------- | ------- | ------------------------ |
| RESET      | `$FFE0` | `JML $D0:0000`           |
| COP        | `$FFA0` | `JML $D0:4F87`           |
| ABORT      | `$FFA4` | `JML $D0:500F`           |
| NMI        | `$FFA8` | `JML $D0:4FCB`           |
| IRQ        | `$FFAC` | `JML $D0:4F43`           |

Native vectors (`$FFE4–$FFEF`) split two ways:

| Native vector | Value   | Target                                            |
| ------------- | ------- | ------------------------------------------------- |
| COP           | `$FF94` | `JML $D0:4EC1` (trampoline)                        |
| BRK           | `$FF98` | `JML $D0:4E80` (trampoline)                        |
| ABORT         | `$FF9C` | `JML $D0:4F02` (trampoline)                        |
| NMI           | `$1200` | `$00:1200` — a handler the BIOS **installs in WRAM** |
| IRQ           | `$1204` | `$00:1204` — a handler the BIOS **installs in WRAM** |

The native NMI/IRQ vectors point into low WRAM (`$00:1200/1204`) because the boot
code copies its interrupt handlers into RAM first (the reset routine builds a
`[$01]`=`$00C0F2`-style pointer and writes a RAM trampoline before enabling
interrupts). This is the same "remap into RAM, then jump" pattern Catapult's
`ROM Map` documents for the loader.

## 5. Region layout (verified)

Per-64 KB-bank profile of the image (entropy, %`0xFF`, %ASCII) cleanly separates
three zones:

| Banks      | File range            | Character                     | Contents (inferred)              |
| ---------- | --------------------- | ----------------------------- | -------------------------------- |
| `$C0–$C7`  | `0x000000–0x07FFFF`   | code (entropy ≈ 6.1, low ASCII)| **Executable BIOS** (512 KB)     |
| `$C8–$C9`  | `0x080000–0x09FFFF`   | high ASCII / sparse            | **UI text & string tables**      |
| `$CA–$CC`  | `0x0A0000–0x0CFFFF`   | high `0xFF`, blocky            | fonts / tiles / packed assets    |
| `$CD–$CF`  | `0x0D0000–0x0FFFFF`   | entropy ≈ 7.3                  | **compressed data** (news/graphics) |

The lower 512 KB (`$C0–$C7`) being pure code and the upper 512 KB (`$C8–$CF`)
being data/assets is exactly the `kRomHi` 512 KB split from [§3](#3-address-mapping-hirom-verified):
the BIOS runs from the low half and pages the asset half in when it needs it.

User-visible XBAND strings start at `0x081???` (e.g. `"XBAND VIDEOGAME MODEM"`
also appears as the header title at `$FFC0`, and message text such as
`"Welcome to the XBAND Rental Program!"` lives around `0x0826xx`).

## 6. How FRED overlays this at run time

The static map above is what the SNES sees once FRED has **asserted "Here"**
(`kKillReg` bit `0x01`), i.e. FRED owns the cartridge bus and the XBAND BIOS is
visible. When "Here" is cleared the same ROM windows fall through to the
pass-through game cartridge, and the FRED patch engine ([07](07-fred-register-map.md),
[09](09-game-patches.md)) can redirect individual game addresses into injected
code held in the 64 KB SRAM. The register window itself, the SRAM and the
`kRomHi`/`safe-ROM` overlays are all decoded by FRED on top of this HiROM base —
see the reference RTL in [`rtl/`](rtl/) (`xband_mapper.sv` now implements this
HiROM decode).

## 7. Reproduce the verification

With the submodule populated (`git submodule update --init platform/xband`),
unzip the BIOS to a scratch dir **outside the repo** and run:

```python
import zlib
data = open("X-Band Modem BIOS (USA).sfc", "rb").read()
assert len(data) == 1 << 20
print("CRC32 %08X" % (zlib.crc32(data) & 0xffffffff))         # A8B868A0
print("title", data[0xFFC0:0xFFD5])                            # b'XBAND VIDEOGAME MODEM '
print("mapmode %#04x" % data[0xFFD5])                          # 0x31 (HiROM+Fast)
print("romsize %dKB" % (1 << data[0xFFD7]))                    # 1024
print("ramsize %dKB" % (1 << data[0xFFD8]))                    # 64
chk  = data[0xFFDE] | (data[0xFFDF] << 8)
cmpl = data[0xFFDC] | (data[0xFFDD] << 8)
assert (sum(data) & 0xffff) == chk and (chk ^ cmpl) == 0xffff  # checksum OK
reset = data[0xFFFC] | (data[0xFFFD] << 8)
print("reset $%04X ->" % reset, data[reset:reset+4].hex())     # FFE0 -> 5c0000d0 (JML $D0:0000)
```

Delete the dump afterwards — it must not be committed (see
[08-bios-and-roms.md](08-bios-and-roms.md)).

## 8. Summary for an RTL/emulator implementer

- Treat the cartridge as a **HiROM** device: ROM at `$C0–$FF:$0000–$FFFF` and
  `$00–$3F`/`$80–$BF:$8000–$FFFF`, 1 MB mirrored across 16 banks.
- Provide **64 KB battery SRAM**; the BIOS work area is reached via bank `$E0`
  (and the `$20–$3F:$6000–$7FFF` window).
- Boot = emulation RESET `$FFE0` → `JML $D0:0000` → native-mode init at file 0.
- `kRomHi` swaps the **lower-512 KB code half** ↔ **upper-512 KB asset half**.
- Everything else (register window, patch redirects, safe-ROM/safe-RAM overlays,
  modem FIFOs) is layered by FRED on top of this base.
