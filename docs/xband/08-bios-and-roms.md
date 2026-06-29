# 08 — BIOS & ROMs (and how to supply them)

## What ships in the submodule

`platform/xband/X-Band Modem BIOS (USA).zip` contains a single file:

```
X-Band Modem BIOS (USA).sfc   1,048,576 bytes (1 MB)   dated 1996-12-24
```

This is the **retail SNES XBAND BIOS** dump. (Catapult's dev `defines.h` uses a
512 KB `kRomSize = 0x80000` window with battery-SRAM/ROM substitution; the retail
image is 1 MB.) The submodule also carries:

- `XBAND_Game_Patches.zip` — the surviving `.SEGA` / `.JSNES` game patches
  (see [09-game-patches.md](09-game-patches.md)).
- `catapult.tar.gz`, `XBand Original Compilation.7z`, `catapult (2).zip`,
  `MiscCatapult.zip`, `Keyboard.zip` — recovered **source** trees (these are the
  preferred basis for a clean re-build, see [10-source-tree.md](10-source-tree.md)).

## Copyright — do **not** commit the binary

The XBAND BIOS is **proprietary firmware** (Catapult / its successors). This
repository deliberately follows the same rule it already applies to the Datel
**Pro Action Replay MK3** BIOS: **the binary is not redistributed in the repo.**
See the project `README.md` — the MK3 BIOS must be supplied by the user at
`Assets/snes/timboettiger.Pro Action Replay/…`, and the core ships only the code
that *loads* it.

Therefore:

- ✅ We document the BIOS (size, origin, how it is loaded, how the FRED registers
  behave).
- ✅ We provide the RTL **loader path** so an end user can drop in their own dump.
- ❌ We do **not** copy `X-Band Modem BIOS (USA).sfc` into `docs/` or `rtl/` or a
  release ZIP. The dump stays inside the third-party `platform/xband` submodule,
  which the user already chose to vendor.

## How the existing core loads an add-on BIOS (the template)

The MK3 integration is the blueprint for embedding the XBAND ROM. From
`rtl/main.v` the MK3 BIOS is streamed in over an **asset-slot loader** and then
served back to the SNES cartridge mapper on demand:

```
// PAR MK3 BIOS loader interface (driven by core_top.sv asset slot 100 loader)
input         MK3_BIOS_WE;
input  [16:0] MK3_BIOS_LOAD_ADDR;
input  [7:0]  MK3_BIOS_LOAD_DIN;

// PAR MK3 BIOS read interface. MAIN_SNES redirects the SDRAM read to offset
// BIOS_BASE (8 MB) when MK3_BIOS_READ is asserted; byte returns on MK3_BIOS_DOUT.
output        MK3_BIOS_READ;
output [16:0] MK3_BIOS_READ_ADDR;
input  [7:0]  MK3_BIOS_DOUT;
```

i.e. an Analogue-Pocket **data slot** (defined in the core's `data.json`)
provides the BIOS bytes at load time; the loader writes them into SDRAM at a
fixed base; the mapper asserts a read request with an offset and the byte comes
back. **No ROM is baked into the bitstream.**

## How the XBAND ROM would be embedded (same shape, bigger)

For an XBAND core you replicate that mechanism with XBAND-sized parameters:

| Aspect            | MK3 today          | XBAND                                   |
| ----------------- | ------------------ | --------------------------------------- |
| BIOS size         | 128 KB             | **1 MB** (retail) — 20-bit address      |
| Load address bus  | `[16:0]` (128 KB)  | `[19:0]` (1 MB)                         |
| Save SRAM         | 32 KB cheat SRAM   | **64 KB** battery SRAM (15→16-bit addr) |
| Pocket data slot  | asset slot 100     | a new slot id for `xband.bin`           |
| Pocket save slot  | slot 11 (`mk3sav`) | a new save slot for the 64 KB SRAM      |

The reference skeleton in [`rtl/`](rtl/) parameterises exactly these widths
(`XBAND_ROM_ADDR_BITS = 20`, `XBAND_SRAM_ADDR_BITS = 16`) and exposes the same
`*_WE/*_LOAD_ADDR/*_LOAD_DIN` + `*_READ/*_READ_ADDR/*_DOUT` interface so it can
plug into a `core_top.sv` data-slot loader the way MK3 does.

## Practical instructions for an end user (proposed)

Mirroring the README's MK3 wording:

> Place a verified 1 MB XBAND BIOS dump at
> `Assets/snes/<author>.XBAND/xband-bios.bin`. The BIOS is proprietary and is not
> distributed here. Load any supported SNES ROM through the Pocket UI; the core
> boots the XBAND BIOS with the game in the pass-through slot.

This keeps the project legally aligned with how the MK3 BIOS is already handled.
