# Savestate — vollständige Zustands-Inventur

Was für einen frame-genauen Savestate serialisiert werden muss. Treibt die
Inkremente 3–5 (Register-Ketten). RAM dominiert die Größe (~328 KB); die Register
sind in Summe klein (~1 KB), aber über viele Module verstreut.

## RAM-Blöcke (~328 KB) — Inkremente 1–2

| Block | Größe | Typ | Lage / Zugriff |
|---|---|---|---|
| WRAM | 128 KB | PSRAM (cram0) | `SNES.sv` `psram wram` — clk_mem, busy/read_avail-Handshake |
| VRAM | 64 KB | Block-RAM ×2 | `SNES.sv` `vram1`/`vram2` — **erledigt (Spike)** |
| ARAM | 64 KB | PSRAM | `SNES.sv` `psram aram` — clk_mem |
| CGRAM | 512 B (256×15) | Block-RAM | in `PPU.vhd` (Port hochziehen) |
| OAM | 544 B | Dual-Port 16/32 | in `PPU.vhd` |
| HOAM | 32 B | Single-Port | in `PPU.vhd` |
| SPR_BUF | 256×9 | Dual-Port | in `PPU.vhd` (Render-Linienpuffer — evtl. nicht nötig) |

> PSRAM-Zugriff (WRAM/ARAM) ist der knifflige Teil: clk_mem-Domäne + Handshake,
> während der ss-Bus auf clk_sys läuft → Zwei-Domänen-Helfer nötig (Inkr. 2).

## Register pro Modul — Inkremente 3–4

**CPU-Wrapper (`CPU.vhd`, ~1270 bit):** Clock/Timing (P65/DMA/DOT-Counter,
H/V_CNT, FIELD, REFRESH), IO-Regs (NMI/IRQ-Enable+Flags, HTIME/VTIME, WRMPYA/DIV,
RDDIV/RDMPY, Math-State), Joypad-State (JOY1-4_DATA, Poll-Counter), **DMA/HDMA**
(DMAP/BBAD/A1T/A1B/DAS/A2A/NTLR ×8 Kanäle, MDMAEN/HDMAEN, Run/Step-State) ≈ 1088 bit.

**65C816 (`65C816/P65C816.vhd`, ~191 bit):** A/X/Y/D/SP/T (6×16), PBR/DBR (2×8),
P (9), PC (16), IR/STATE/DR, EF/XF/MF, Interrupt-Sync-Flags, SB/DB (2×16).

**PPU (`PPU.vhd`, ~1282 bit):** Display-Control, OBJ-Regs, BG-Scroll/Addr (×4),
Mode7 (M7A-D, HOFS/VOFS/X/Y), Window-Regs, Color-Regs (CGADD, CGWSEL, CGADSUB),
VRAM-Regs (VMADD, Increment), H/V-Counter+Latches, OAM/Sprite-Render-State,
BG-Processing, Mode7-Math, Color-Math.

**SMP (`SMP.vhd`, ~230 bit):** CPUI/CPUO ×4, Timer-State (T0-2 DIV/OUT/CNT,
TM_EN), CLK_SPEED, IPL_EN.

**SPC700 (`SPC700/SPC700.vhd`, ~120 bit):** A/X/Y/SP/PSW/T (6×8), PC (16), IR,
STATE, SB/DB, Interrupt/Jump-Flags, BitMask.

**DSP (`DSP.vhd`, ~2340 bit):** Step/Substep-Sequencer, Voice-State ×8 (KON,
Envelope, ADSR, PITCH), BRR-Decode (Addr/Offs ×8, BUF), Gaussian-Interp, **Echo**
(POS/ADDR/LEN, FIR/FFC-Koeffizienten), Global-Control, Register-File.

## Enhancement-Chips — Inkrement 5 (bedingt)

SA-1 (~20 KB inkl. BWRAM), SuperFX/GSU (~2 KB), CX4/DSPn/SDD1 (~500 bit),
SPC7110/BS-X (~1 KB), MSU-1 (~200 bit), RTC (~40 bit). Strategie: serialisieren
**oder** `savestate_supported` dynamisch auf 0, solange der jeweilige Chip aktiv
ist (ehrliches „kein Sleep" statt korruptem Save).

## Architektur

- **RAMs:** direkter Snapshot via Walker (Block-RAM per Port B; PSRAM per
  clk_mem-Helfer).
- **Register:** Register-Ketten-Bus (analog MiSTer `savestates.vhd`) — jedes Modul
  hängt seine Flipflops an einen adressierten `ss_addr`/`ss_din`/`ss_dout`-Bus,
  ein zentraler Walker läuft die Adressen ab. Schreiben (Restore) erfolgt über den
  Bus unabhängig vom (während Savestate gegateten) Core-Takt.

_Quelle: automatische Inventur über `rtl/` am 2026-06-22._
