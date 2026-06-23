# Savestate — verbleibende Arbeit (PPU + DSP)

Stand: **CPU (65C816) + SMP/SPC700 serialisiert, CI-grün, CPU HW-validiert.**
Restore hängt noch (CPU wartet auf nicht-restaurierte PPU/SMP/APU — erwartet).
Es fehlen **PPU** und **S-DSP**. Beide sind größer als CPU/SMP und haben **interne
Block-RAMs**, die — anders als die VRAM-Anzapfung auf SNES.sv-Ebene — durch die
VHDL-Hierarchie angezapft werden müssen.

## Empfohlener Ansatz (Risiko senken)

Bei 60+ PPU- und noch mehr DSP-Registern ist manuelles Bit-Slicing die größte
Fehlerquelle. **Empfehlung:**
1. **VHDL-2008 für PPU.vhd/DSP.vhd aktivieren** (`set_global_assignment -name
   VHDL_INPUT_VERSION VHDL_2008 -to ...` im qip) und **Aggregat-Targets** nutzen:
   - Save: `ss_do <= sigA & sigB & sigC & ...;`
   - Load: `(sigA, sigB, sigC, ...) <= ss_di;` (gleiche Reihenfolge → automatisch
     konsistent, kein Bit-Bookkeeping). Eliminiert die Hauptfehlerquelle.
   - Falls Quartus 21.1 das ablehnt: zurück auf explizite Slices (wie CPU/SMP).
2. **Savestate-Testbench** (Verilator/GHDL): Zustand setzen → einige Takte → Save →
   Vergleich; Save→Load→Save-Roundtrip. Macht funktionale Korrektheit verifizierbar,
   die CI sonst nicht abdeckt.
3. Aggregation-Slices wachsen lassen: `SNES.vhd SS_REG_DO <= dsp & ppu & smp & cpu`;
   `ss_spike` REG_BYTES erhöhen; `core_top` savestate_size anpassen.

## PPU (`rtl/PPU.vhd`, Entity `SPPU`)

**Register (~340 Bit, größtenteils EIN Prozess 338–697; H/V in 832–899):**
Display/Mode: FORCE_BLANK, MB, BG_MODE, BG3PRIO, BG_SIZE, BG_MOSAIC_EN, MOSAIC_SIZE,
BGINTERLACE, OBJINTERLACE, OVERSCAN, PSEUDOHIRES, M7EXTBG.
BG: BG_SC_ADDR(0..3), BG_SC_SIZE(0..3), BG_NBA(0..3), BG_HOFS(0..3), BG_VOFS(0..3).
Mode7: M7SEL, M7A, M7B, M7C, M7D, M7HOFS, M7VOFS, M7X, M7Y.
VRAM: VMADD, VMAIN_ADDRINC, VMAIN_ADDRTRANS, VMADD_INC, VRAMDATA_Prefetch.
Color: CGADD, CGWSEL, CGADSUB, SUBCOLBD.
Window: WH0-3, W12SEL, W34SEL, WOBJSEL, WBGLOG, WOBJLOG, TMW, TSW.
Screen: TM, TS.
OAM-Regs: OBJADDR, OBJNAME, OBJSIZE, OAMADD, OAM_ADDR, OAM_PRIO, OAM_PRIO_INDEX.
H/V (Prozess 832–899): H_CNT, V_CNT, FIELD, IN_HBL, IN_VBL, OPHCT, OPVCT.
Schreib-Latches (nötig für korrekten Write-State): BGOFS_latch, BGHOFS_latch,
M7_latch, CGRAM_Lsb (im CGRAM-Prozess!), OAM_latch, OPHCT_latch, OPVCT_latch, F_LATCH.
Transient (NICHT serialisieren): BG_DATA*, *_PIX_DATA*, MAIN/SUB_*, OUT_X/Y, Mosaic-
Zähler, M7_TEMP/TILE*, SPR_*-Pipeline.

**Interne RAMs (Port-B-Anzapfung wie VRAM, durch SPPU→SNES.vhd→main→MAIN_SNES→ss_spike):**
- CGRAM `dpram(8,15)` @PPU.vhd:318 — 256×15b Palette. **Essenziell.** (15b → als 16b/Wort).
- OAM `dpram_dif(8,16,7,32)` @PPU.vhd:1393 — 256×8 (PortA) Sprites. **Essenziell.**
- HOAM `spram(5,8)` @PPU.vhd:1408 — 32×8 Sprite-Size/Flip/Palette. **Essenziell.**
- SPR_BUF `dpram(8,9)` @PPU.vhd:1648 — Linienpuffer, **transient, NICHT serialisieren.**

## S-DSP (`rtl/DSP.vhd`) — der größte Brocken (~2340 Bit)

Sequencer (STEP/SUBSTEP), Voice-State ×8 (KON, ADSR/Envelope, PITCH, INTERP_POS,
BRR-Decode-Position/Addr/Buf), Gaussian-Interp, **Echo** (POS/ADDR/LEN, FIR/FFC),
Global-Control, Register-File. Interne RAMs: REGRAM `dpram(7,8)` @DSP.vhd:274,
BRR_BUF `dpram(7,16)` @DSP.vhd:504. Echo-Puffer liegt in ARAM (schon serialisiert).
Map analog zu SMP/PPU erstellen (Register→Prozess), dann gleiches Muster.

## Reihenfolge & Test

PPU-Register → PPU-RAMs → **HW-Test** (sollte erstmals Bild beim Wake zeigen, evtl.
ohne Ton) → DSP-Register → DSP-RAMs → HW-Test (Voll-Resume mit Ton). Pro Schritt
CI-Fit; funktionale Verifikation nur auf Hardware (oder via Testbench).
