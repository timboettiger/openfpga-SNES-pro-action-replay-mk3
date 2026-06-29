# XBAND — Reverse-Engineering & Integration Notes

This folder documents everything we currently know about the **XBAND** online
gaming modem for the SNES (and, where it helps to understand the SNES side, the
Sega Genesis/Mega Drive variant). The goal is to have a single, self-contained,
text-first reference that can be lifted wholesale into another project — in
particular to **extend an `fxpakpro`-style cartridge with XBAND functionality**
and/or to grow an XBAND core out of this Pocket SNES core.

All of this is distilled from the material shipped in the
[`platform/xband`](../../platform/xband) submodule
([Cinghialotto/xband](https://github.com/Cinghialotto/xband)):

| Source file in `platform/xband`            | What it gives us                                              |
| ------------------------------------------ | ------------------------------------------------------------- |
| `Readme.md`                                | High-level description of the hardware and the network model  |
| `xbsega.go`                                | A working handshake + "puke" parser + ADSP/CRC implementation |
| `sample_packets.txt`                       | Hand-crafted, mostly *tested* server→box opcode payloads      |
| `Pocky_XBAND.pdf`                          | Catapult Entertainment **schematics** (image-only scan)       |
| `X-Band Modem BIOS (USA).zip`              | The 1 MB SNES XBAND BIOS dump (proprietary — not used here)    |
| `XBAND_Game_Patches.zip`                   | The handful of surviving `.SEGA` / `.JSNES` game patches       |
| `catapult.tar.gz`                          | The full Catapult Entertainment source tree (box + server)    |
| `Keyboard.zip`, `MiscCatapult.zip`, `*.7z` | Additional recovered sources / compilations                   |

> **Provenance / accuracy.** Where a fact comes straight from Catapult's own
> source (register names, opcode numbers, timing constants) it is authoritative.
> Where it comes from community reverse-engineering (`Readme.md`, `xbsega.go`,
> `sample_packets.txt`) it is marked, and the original "TESTED / NEEDS TESTING"
> qualifiers are preserved. The schematics were OCR'd from an image-only PDF, so
> individual net labels may contain transcription noise — they are meant as a
> map, not as a netlist you can fab from.

## Contents

| Doc                                                  | Topic                                                            |
| ---------------------------------------------------- | --------------------------------------------------------------- |
| [01-overview.md](01-overview.md)                     | What XBAND was, how a session worked, history                   |
| [02-hardware.md](02-hardware.md)                     | FRED, the Rockwell modem, SRAM, smart card, the boards          |
| [03-schematics.md](03-schematics.md)                 | Page-by-page transcription of `Pocky_XBAND.pdf`                 |
| [04-network-protocol.md](04-network-protocol.md)     | ADSP/AppleTalk framing, handshake, headers, CRC-16              |
| [05-opcodes.md](05-opcodes.md)                       | Complete box↔server opcode tables                               |
| [06-sample-packets.md](06-sample-packets.md)         | Annotated, ready-to-send packet examples                        |
| [07-fred-register-map.md](07-fred-register-map.md)   | The FRED ASIC register map (the patch engine + modem I/O)       |
| [08-bios-and-roms.md](08-bios-and-roms.md)           | Which ROMs exist, copyright, how to supply them                 |
| [09-game-patches.md](09-game-patches.md)             | Game-patch (`.mp`) catalogue + how FRED patches games           |
| [10-source-tree.md](10-source-tree.md)               | A map of `catapult.tar.gz` so you can find things fast          |
| [11-rtl-architecture.md](11-rtl-architecture.md)     | How to represent XBAND as RTL + how the ROM is embedded         |
| [12-link-cable-esp32.md](12-link-cable-esp32.md)     | Can this core reach an ESP32 over the link port? (analysis)     |
| [`rtl/`](rtl/)                                        | Reference RTL **skeleton** for the XBAND mapper/modem            |

## Three questions this folder answers

1. **Document the XBAND insights** (visual material included) so they can be
   reused in another repo → docs `01`–`10`.
2. **Represent it as RTL and embed the ROM** → doc `11` + the [`rtl/`](rtl/)
   skeleton. (The proprietary BIOS itself is *not* committed; see `08`.)
3. **Can our core reach the link cable to attach a Wi-Fi ESP32?** → doc `12`.
