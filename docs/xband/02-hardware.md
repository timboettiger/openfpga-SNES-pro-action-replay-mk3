# 02 — Hardware

This page describes the XBAND hardware blocks. The authoritative source for the
register-level detail is Catapult's own diagnostic code
(`catapult.tar.gz → Catapult/Box-16bit-Feb96/Tools/ModemTester/`), and the
block topology comes from the schematics in `Pocky_XBAND.pdf` (transcribed in
[03-schematics.md](03-schematics.md)). The exhaustive FRED register table lives
in [07-fred-register-map.md](07-fred-register-map.md).

## Block diagram (logical)

```
        SNES / Genesis cartridge edge
                    │  (address, data, /RD, /WR, /RESET, CS, A0, clocks, H/VSYNC)
                    ▼
   ┌─────────────────────────────────────────────────────────┐
   │                        FRED ASIC                         │
   │  • cartridge-bus arbitration ("Here"/Kill, RomHi, etc.)  │
   │  • ~10 patch vectors + zero-page / trans-address remap   │
   │  • memory-mapped modem/serial FIFOs (Tx/Rx)              │
   │  • LED port, address/status read-back, vblank counters   │
   └───┬───────────────┬───────────────┬──────────────┬───────┘
       │               │               │              │
       ▼               ▼               ▼              ▼
 ┌──────────┐   ┌─────────────┐  ┌───────────┐  ┌──────────────┐
 │ Game ROM │   │ Batt. SRAM  │  │ XBAND ROM │  │ Rockwell modem│
 │ (passthru│   │  64 KB      │  │ (BIOS)    │  │  2400 baud +  │
 │  socket) │   │             │  │ 512KB/1MB │  │  DAA (phone)  │
 └──────────┘   └─────────────┘  └───────────┘  └──────┬───────┘
                                                        │
                                  ┌─────────────────────┴───────┐
                                  │ Smart-card connector (billing│
                                  │  / activation, on dev boards) │
                                  └──────────────────────────────┘
```

## FRED — the custom ASIC

"FRED" is Catapult's gate array. It is the heart of XBAND and the thing you must
model to build an XBAND core. From the diagnostics it provides at least:

- **Cartridge bus arbitration.** A *control register* and a *kill register*
  decide whether FRED or the pass-through cartridge drives the bus, whether the
  ROM is mapped high, whether "safe ROM"/"two RAM" modes are on, and whether
  SNES vs. Sega exception handling is enabled. The "**Here**" bit means *the
  cartridge cannot be seen* (FRED owns the bus).
- **Patch engine.** ~**10 patch vectors** (Vector0…Vector9/A in the source) each
  with a low/high enable bit, plus *zero-page* and *trans-address* enables, a
  vector table base, and "safe RAM"/"safe ROM" range registers. This is how a
  downloaded patch redirects specific game addresses into Catapult code in SRAM
  — conceptually the same trick as Game Genie/Pro Action Replay, but
  programmable and able to vector into whole injected subroutines.
- **Memory-mapped modem/serial.** Tx and Rx FIFOs (`kTxBuff`/`kRxBuff`), modem
  status registers, a bit-rate derived from the video counters (see below).
- **Housekeeping.** An LED data/enable port (front-panel LEDs), address-status
  read-back registers (for diagnostics / floating-pin detection), and vblank /
  serial-vcount counters.

The FRED base address in the dev environment is `kFredBase = 0x003bc001`; on the
retail SNES box it is mapped into the cartridge address space. See
[07-fred-register-map.md](07-fred-register-map.md) for every register offset.

### Clocking the modem from the video counters (important!)

FRED does **not** have an independent UART baud-rate generator in the usual
sense — the modem bit timing is derived from the **video** timebase. From
`defines.h`:

- `ReadSerialVCnt` is the **top 8 bits of a 19-bit counter** clocked by the
  input clock; it increments once per **2048 clocks** (≈85.33 µs at 24 MHz).
- **1 modem bit = 1/2400 s ≈ 417 µs ≈ 5 `VCnt` ticks** (`kVCntsPerModemBit = 5`).
- Equivalently **≈7 horizontal lines per modem bit** (`kLinesPerModemBit = 7`).
- `ReadMVSyncHigh` ranges 0…$61 and equals `ReadSerialVCnt/2`; it is ≈$5C at the
  start of vblank.

The practical consequence for an emulator/RTL: the modem path is **coupled to
the SNES video timing**. A faithful core has to drive the serial sampling from
the same pixel/line clock the PPU uses, which is *exactly* why XBAND switched
between interlaced/non-interlaced modes to throttle the faster console.

## The Rockwell modem + DAA

A standard **Rockwell 2400-baud** modem chipset with a Catapult **DAA**
(Data Access Arrangement) — the analog phone-line interface: line transformer,
ring detect, off-hook relay, varistor/overvoltage protection, opto-isolation.
Schematic page "Rockwell DAA design" (see [03](03-schematics.md), page 8) shows
the `1N748A` zeners, a `V150LA10A` varistor, a `4N25` opto-coupler, a
`RELAY, 1 FORM A` off-hook relay and a `TAMURA/MIDCOM` line transformer.

On the **debug** boards the modem is also reachable through standard **16550
UARTs** and a dual serial port (the "Pocky - SNES/Genesis Dual Serial Port
Board", and the 16550 on `STORM_REV2`). That is the access path `xbsega.go`
uses — it drives the box through a host serial port with plain **AT commands**:

```
AT          → expect "OK"     (probe)
AT&F        → factory defaults
ATQ0        → enable result codes
AT+VCID=1   → enable caller-ID reporting
ATS0=2      → auto-answer on 2nd ring
ATM0        → speaker off
…           → wait for "CONNECT", send CR, then begin the XBAND framing
ATH         → hang up
```

## Battery-backed SRAM

Retail SRAM is **64 KB** (the community Readme says SRAM is 64 KB and "10 KB or
smaller" patches live in it alongside the profile, stats, icons, news and mail).
The schematics show the SRAM as battery-backed with `ROM substitutes for now`
notes on the dev boards (page 10). The free-space accounting is reported back to
the server in the puke (`OS FREE`/`DB FREE` longwords after `msLogin`).

## Smart-card connector

The dev/retail boards carry a **smart-card** interface (`SMARTVCC`, `SMARTDATA`,
`SMARTCLK`, `SMARTVPP`, `SMARTRESET`, `SMARTDTCT`) used for billing/activation
(see [03](03-schematics.md), page 4). Not needed for offline emulation but worth
knowing it exists when reading the OS source.

## The boards in `Pocky_XBAND.pdf`

The PDF actually contains **three** distinct designs (all Catapult, "confidential"):

1. **TYPHOONDEBUG** — an 11-page debug board (rev 6/1/94): FRED, battery-backed
   SRAM, smart-card connector, Rockwell DAA, the SNES/Sega edge + straddle
   connectors and serial.
2. **STORM_REV2** — a 5-page board (rev 5/10/94): octal transceivers, SRAM, a
   16550 (`IS16550`) serial port, `ENWR1/ENWR2` write-enable logic.
3. **Pocky — SNES/Genesis Dual Serial Port Board** (Catapult, 6/05, v1.0, Joe
   Britt): a later adapter exposing **two** serial ports with jumpers that
   "eliminate need for null-modem adapters". This is the board the modern
   `xbsega.go` flow targets.
