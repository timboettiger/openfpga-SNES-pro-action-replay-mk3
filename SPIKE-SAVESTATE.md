# Savestate / Sleep — Machbarkeits-Spike

> **Status: Spike, kein fertiges Feature.** Dieser Branch beantwortet *eine* Frage:
> **Passt die Savestate-Infrastruktur überhaupt in den FPGA?** Er liefert noch
> kein spielbares Sleep/Wake.

## Worum es geht

Auf der Analogue Pocket ist „Sleep & Wake / Memories" **technisch identisch mit
Savestates**: beim Schlafen wird der FPGA neu geladen, und Resume läuft
ausschließlich über die APF-Host-Befehle `0x00A0` (Savestate Start/Query) und
`0x00A4` (Savestate Load/Query). Es gibt **keinen** RAM-Retention-Schlaf, den man
per Flag „einschaltet". Ohne echte Savestates kein Sleep/Wake.

Bislang unterstützt **kein** FPGA-SNES-Core Savestates (auch nicht srg320s
MiSTer-Original, auch nicht Analogues Super NT) — weil dafür der interne
Registerzustand *aller* Chips (65C816, SPC700, PPU, S-DSP, Enhancement-Chips)
über einen Serialisierungs-Bus auslesbar gemacht werden muss. Das bloße
Speichern der RAM-Abbilder reicht nicht: PC, Akku, Scanline-Zähler, BRR-Decoder
usw. liegen in Flipflops, nicht im adressierbaren RAM.

Dieser Spike baut die **Pipeline drumherum** einmal komplett durch — bewusst nur
für **die 64 KB VRAM** (Block-RAM, einfachster Anzapfpunkt) — damit Quartus den
**Ressourcenverbrauch** der Infrastruktur meldet, bevor wir die große
Chip-für-Chip-Serialisierung angehen.

## Was der Spike enthält

| Datei | Änderung |
|---|---|
| `rtl/mister_top/ss_spike.sv` | **Neu.** Minimaler Savestate-Bus-Master; serialisiert VRAM ↔ APF-Controller. |
| `rtl/mister_top/SNES.sv` | `ss_*`-Bus-Ports; `ss_spike` instanziiert; VRAM-Port-B gemuxt (Clear ODER Savestate). |
| `rtl/snes.qip` | `ss_spike.sv` in den Build aufgenommen. |
| `target/pocket/core_top.sv` | `savestate_supported = 1`; `savestate_addr = 0x50000000`; `save_state_controller` (war toter Code) instanziiert und verdrahtet; Bridge-Read-Mux Region `0x5`. |
| `target/pocket/save_state_controller.sv` | Savestate-Region von `0x4` auf `0x5` (**siehe Kollision unten**). |
| `pkg/Cores/…/core.json` | `sleep_supported: true`. |

### Wichtiger Fund: Adresskollision

Der agg23-Controller hartcodiert die Bridge-Region `0x4xxxxxxx` für Savestates.
In diesem MK3-Fork ist `0x40000000` aber **schon belegt** vom „MK3 Cheats"-
Dataslot (`data.json` id 11). Deshalb läuft der Savestate hier auf der freien
Region **`0x50000000`** — sonst hätten sich Cheat-Save und Savestate gegenseitig
überschrieben.

## Synthese

```bash
# In Quartus: projects/snes_pocket.qpf öffnen und kompilieren,
# oder headless (wie in der CI, Quartus im Docker):
pwsh build.ps1
```

Es muss **kompilieren und durch Fitter + Timing laufen**. Funktionale Korrektheit
des Round-Trips ist hier *nicht* das Ziel (siehe Limitierungen).

## Was messen — die eigentliche Frage

Im **Fitter-Report** (`projects/output_files/*.fit.summary` bzw. im Compilation
Report unter *Fitter → Resource Usage Summary*):

1. **Logic utilization (ALMs)** — Differenz zum aktuellen `master`-Build. Das ist
   der LE-Aufschlag für Controller + FIFOs + Bus-Master. Die *eigentlichen*
   Register-Ketten der vollen Implementierung kommen später dazu, aber sie fügen
   überwiegend Mux-Logik um schon existierende Flipflops hinzu, keine neue
   Speicherung — diese Baseline ist also aussagekräftig.
2. **Block memory bits (M10K)** — die beiden `dcfifo_mixed_widths` im Controller
   sind der dominante *neue* BRAM-Posten. Hier zeigt sich, ob noch Luft ist.
3. **Fit ja/nein** — passt es überhaupt? Bei wieviel % landet Logic/BRAM?
4. **Timing (TimeQuest, Slack)** — bleibt `clk_sys_21_48` / `clk_mem_85_9` im
   grünen Bereich, oder reißt die Savestate-Logik das Timing?

Zahlen bitte zurückmelden — daraus leitet sich ab, ob die volle Variante
(alle Chips) realistisch in den verbleibenden Logikraum passt.

## Bekannte Limitierungen (bewusst, für den Spike)

- **Nur VRAM.** Kein CPU-/SPC700-/PPU-/DSP-/Enhancement-Chip-Registerzustand.
  Ein zurückgeladener Stand **resumed nicht** in eine laufende Maschine.
- **Keine Core-Pause.** Der Spike friert die SNES während des Savestates nicht ein
  (Port A läuft weiter, während Port B liest/schreibt) → der Round-Trip wäre
  „torn". Die volle Variante muss den Core-Takt gaten, solange `ss_busy` aktiv ist
  (das ist genau der „stoppe alle Chips"-Teil). **Für die Fit-Messung irrelevant.**
- **Handshake-Timing.** Der `ss_spike`-Master ist gegen den Controller-Vertrag
  geschrieben, aber ungetestet auf Hardware. Rechne mit 1–2 Iterationen am
  `ss_req`/`ss_ack`-Timing, sobald es auf dem Gerät läuft.
- **Savestate-Größe** ist hier `0x10008` Bytes (1 Header- + 8192 VRAM-Worte).

## Wenn der Fit passt — der Weg zur vollen Variante

1. `ss_*`-Serialisierungs-Bus durch CPU/SMP/PPU/DSP + WRAM/ARAM ziehen
   (Register-Ketten + RAM-Walker, analog zu MiSTers `savestates.vhd`).
2. Core-Takt gaten, solange `ss_busy` — sauberer, konsistenter Snapshot.
3. `savestate_supported` dynamisch auf 0, sobald ein Enhancement-Chip aktiv ist
   (SuperFX/SA-1/…), bis deren Zustand ebenfalls serialisiert ist — ehrliches
   „kein Sleep" statt korruptem Save.
4. `savestate_size` an den echten Gesamtzustand anpassen.
