# 03 — Schematics (transcription of `Pocky_XBAND.pdf`)

`platform/xband/Pocky_XBAND.pdf` is a **17-page, image-only scan** (no text
layer) of Catapult Entertainment schematics. Because the user's intent is to
move the *visual* information into reusable text, every page is transcribed here
to the level the scan allows. Net labels were recovered with OCR and **may
contain minor transcription noise** — treat this as a navigational map of the
hardware, not a fab-ready netlist. The original PDF remains the source of truth
for exact pin numbers.

The PDF contains **three designs**:

| Pages | Design                                            | Title block                                  |
| ----- | ------------------------------------------------- | -------------------------------------------- |
| 1     | Pocky — SNES/Genesis **Dual Serial Port Board**   | Catapult Entertainment, 6/05, v1.0, Joe Britt|
| 2–12  | **TYPHOONDEBUG** (11 logical sheets)              | Catapult Entertainment "confidential", 6/1/94|
| 13–17 | **STORM_REV2** (5 logical sheets)                 | Catapult Entertainment "confidential", 5/10/94|

A recurring `{n,m,…}` annotation next to a net name is Catapult's cross-sheet
reference: it lists the other sheet numbers on which that net also appears.

---

## Page 1 — Pocky Dual Serial Port Board (6/05, v1.0)

A later adapter board that breaks the SNES/Genesis serial out to **two** DB-style
serial ports. Key transcribed features:

- Two serial channels built around level-shifter/driver parts with charge-pump
  capacitors (MAX-232-class: `C1+/C1-/C2+/C2-`, `T1OUT/R1IN/T2OUT/R2IN`,
  `TROUT/TRIN/RECIN/RECOUT`, radial-characteristic decoupling caps).
- Explicit handshake pins broken out: `CTS`, `RTS`.
- Bus signals tapped from the cart edge: `SNES_WR`, `SNES_RD`, `SNES_RESET`,
  `SNES_A0`, `SEGA_CS`, with the `6850`-style ACIA references (`D0…D7`).
- Repeated note: **"Jumpers eliminate need for null-modem adapters"** — the board
  can swap TX/RX so you can connect straight-through.
- Note: **"For Software Debug Use"**.
- Title block: *"Pocky - SNES/Genesis Dual Serial Port Board, Catapult
  Entertainment, 6/05, Version 1.0, Joe Britt."*

This is the board the modern `xbsega.go` AT-command flow expects on the host
side.

---

## TYPHOONDEBUG (pages 2–12, rev 6/1/94)

The full debug platform. Sheets are labelled "Page *n* of 11".

### Page 2 — Sega edge connector (sheet 1/11)
The Sega cartridge **edge** connector. Buses broken out: `DATA[15:0]`,
`ADDR[22:0]`, write strobes `WR1_`/`WR2_`, `CE_`, `OE_`, clocks `CK`/`CKI`,
`AS`, `RESET_`, `DTCK`, and `HSYNC`/`VSYNC`. The `{2,3,5,7,10,11}` style tags on
each net show where the same signal re-appears on other sheets.

### Page 3 — Sega straddle connector (sheet 2/11)
The Sega **straddle** (pass-through) connector that the game cartridge plugs
into, mirroring the same `DATA[15:0]`/`ADDR[22:0]`/`WR1_`/`WR2_` set, plus the
cartridge selects `SSCART_` / `OECART_`. Decoupling caps `0.01 µF` shown.

### Page 4 — Battery-backed SRAM (sheet 3/11)
The save SRAM. Address/data buses appear as the **`TRAD0…TRAD14`** "translated
address/data" lines (FRED's post-mapping bus). Two banks selected by
`PCS_`, `OE_`, `WR1_`/`WR2_`. Protection parts on the supply: `1N5817` Schottky,
`1N4153`, `MMBT-5134` transistor for battery switch-over. Net `CSRAM_`.

### Page 5 — Smart-card connector (sheet 4/11)
The smart-card socket: `SMARTVCC_`, `SMARTDATA`, `SMARTCLK`, `SMARTVPP`,
`SMARTRESET`, and detect `SMARTDTCT`. A `T1530`-class transistor on the data
line; standard `VCC/GND` with `DTO/DTW` routing.

### Page 6 — FRED (sheet 5/11)  ← the important one
The **FRED ASIC** itself. Transcribed connections:

- A **24.000 MHz** crystal (`Y1`, with `39 pF`/`18 pF` load caps, `1K`) — the
  master timebase the modem bit-clock is derived from.
- Game/Sega address in: `ADDR0…ADDR13` → FRED, producing the translated bus
  `TRADR0…TRADR18` out (`TRAD0…TRAD18`).
- Data bus `DATA[7:0]` in/out, `VSYNC` in, cart selects `CSCART_`, `OECART_`,
  and a `HERE` output (the "Here" / cart-not-visible signal).
- A net labelled **`DEFAULT`** and **`FRED`** in the title area; sheet marked
  "Page 5 of 11".

This sheet is the physical counterpart to the register map in
[07-fred-register-map.md](07-fred-register-map.md).

### Page 7 — Serial ports (sheet 6/11)
Two serial data paths `SD1`/`SD2`, `SC1`/`SC2`, connectors `J3/J4/J5`, MAX-232
class charge-pump (`C19/C21`, `1 µF`), `MRXD`/`RXD`/`TXD` routing. Note:
*"please place the mod && ser labels as shown"* and a hand-note
*"this one REALLY is supposed to be + to gnd"*.

### Page 8 — Rockwell modem core (sheet 7/11)
The **Rockwell modem** device. Transcribed pins/nets: `FAX MODE`, `MODE0/MODE1`,
`RSTO`, `TSTB0/TSTB1`, `EYEX/EYEY`, `TDACO`, data bus `DATA[7:0]`, register
selects `RS0…RS4`, `READ`/`WRITE`, `CS` (`CSMODEM_`), `RESET_`, `TXD`/`RXD`,
clocks `XTCLK/TXCK/RXCK/BRDCLK/MODEMCLK`, `AGCIN`, `RFILO`, `RING_`, `SPKR`,
`SLEEP`. Outputs to the DAA: `MODOUTM`/`MODOUTP`, `RADVR`/`RBDVR`. Supplies split
analog/digital (`+5VA/+5VD`, `AGND/DGND`).

### Page 9 — Rockwell DAA design (sheet 8/11)
The **phone-line interface (DAA)**. Transcribed parts: line transformer
(`TAMURA TTC143` / `MIDCOM 671-8215` / `MICROTRAN T9311` alternates),
`1N748A` zeners (`VR0`), `V150LA10A` varistor, `47 µF 250 V` cap, `1N966B`
zeners, `4N25` opto-coupler (`U5`), `1N4148`, a **`RELAY, 1 FORM A`** off-hook
relay, ring pins `RINGX`/`RING`, drivers `MODOUTM`/`MODOUTP`, receive `RADVR`.

### Page 10 — LED bank (sheet 9/11)
Front-panel **LED** bank: seven LEDs `D1…D7` each with a `330 Ω` resistor
(`R13…R19`) and `308-T1-RED` LED parts. These are the status LEDs the box (and
this Pocket core's MK3 OSD analog) light up.

### Page 11 — Battery-backed SRAM / ROM substitute (sheet 10/11)
Two SRAM devices on the `TRAD0…TRAD16` bus driving `DATA[15:0]`, selected by
`CSROM_`/`CSRAM_`, `WR1_`/`WR2_`, `OE_`. Hand-note: **"Battery backed SRAM…
ROM substitutes for now…"** — i.e. on the dev board, ROM stands in where retail
uses battery SRAM.

### Page 12 — Connector / jumper field (sheet 11/11)
A large header/jumper block tying every cross-sheet net together: the full
`ADDR`/`DATA`/`TRAD` buses, `SMART*` lines, `RXCK/TXCK/RXD/TXD`, `CSMODEM_`,
`MODEMCLK`, `CSROM_`/`CSRAM_`, `OECART_`/`CSCART_`, `HERE`, `DEFAULT`, `SPKR`,
`PCS_`. Effectively the board's patch-panel / option-select.

---

## STORM_REV2 (pages 13–17, rev 5/10/94)

An earlier/parallel board variant. Sheets labelled "Page *n* of 5".

### Page 13 — Edge connector (sheet 1/5)
`DATA[15:0]`/`ADDR`/control to the cart edge, much like TYPHOONDEBUG page 2;
clocks `CK/CK1`, `AS`, `RESET_`, `DTCK`.

### Page 14 — Octal transceivers (sheet 2/5)
Two **octal '245-class transceivers** (`U6`, `U7`, "OCTAL TS TRANSCEIVER")
buffering `DATA[15:0]` to the address-mapped bus, with `CARDOE_`, `ENWR1_`/
`ENWR2_`, `OE_`, `CE_` controls.

### Page 15 — SRAM (sheet 3/5)
Two SRAMs on `ADDR[22:0]`/`DATA[15:0]` selected by `CSROM_`/`CSSER_`, `OE_`,
`WR1_`/`WR2_`. `0.01 µF` decoupling.

### Page 16 — 16550 serial port (sheet 4/5)
An **`IS16550`** UART (`U5`) — `SIN`/`SOUT`, `RTS`/`CTS`, register selects
`A0…A2`, chip selects `CS0/CS1/CS2` from `CSSER_`, `ADS*`, `DISTR*/DOSTR*`
strobes, `WR1_`, `RESET_`. A MAX-232-class charge pump (`C19`, `1 µF`,
`+/-AVEC`) drives the RS-232 levels. This is the "real UART" access path.

### Page 17 — Connector / jumper field (sheet 5/5)
STORM's patch-panel: `ADDR[*]`, `ENWR1_/ENWR2_`, `CSROM_`, `CSSER_`, `OE_`,
`RESET_`, transceiver enables — the cross-sheet tie-point block.

---

## What to take away for RTL

- The **bus** XBAND sits on is the standard SNES/Genesis cartridge bus
  (address, data, /RD, /WR, /RESET, CS, A0, clocks, **HSYNC/VSYNC**). HSYNC/VSYNC
  being wired into FRED confirms the modem timing is video-locked.
- FRED produces a **translated** address/data bus (`TRAD*`) feeding ROM/SRAM —
  i.e. FRED is a configurable MMU + patch unit, not just glue.
- The **modem** is reachable two ways: the real Rockwell+DAA analog path, *or*
  the **16550 UART** on the debug boards. For a Pocket/ESP32 re-implementation
  you would model the 16550-style byte interface and tunnel it over the link
  port — see [12-link-cable-esp32.md](12-link-cable-esp32.md).
