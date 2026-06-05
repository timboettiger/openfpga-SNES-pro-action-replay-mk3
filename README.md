# Pro Action Replay MK3 for Analogue Pocket

A SNES core for the Analogue Pocket that emulates the Datel **Pro Action Replay
MK3** cheat cartridge on top of [agg23's openFPGA SNES core](https://github.com/agg23/openfpga-SNES)
(a port of [srg320's MiSTer SNES](https://github.com/MiSTer-devel/SNES_MiSTer)).
The MK3 BIOS wraps a standard SNES ROM and provides the cartridge's cheat entry,
trainer, and live cheat application.

## Features

### This core adds

- **Pro Action Replay MK3:** boots into the MK3 BIOS (the Pro Action Replay UI)
  for cheat-code entry, trainer, and live cheat application. A pause-menu action
  returns to the BIOS from a running game, the Cheats / Trainer option toggles
  cheats (also live in-game), and the cheat list is saved to the SD card and
  restored on the next launch.
- **Cartridge LEDs:** an on-screen recreation of the cartridge's front-panel
  LEDs, placeable in any corner or hidden.
- **Mouse on the Analogue Dock:** a USB mouse acts as the SNES Mouse, on SNES
  port 1 or 2 (Mouse Port), in games and in the BIOS. Without one, the D-Pad or
  left analog stick emulates it.

### Inherited from agg23's SNES core

- SNES emulation, NTSC and PAL
- Enhancement chips: SuperFX, SA-1, DSP-1/2/3/4, CX4, S-DD1, SPC7110, BS-X, MSU-1
- Controllers: gamepad, SNES Mouse, Super Scope, Justifier, and up to four
  players via Multitap
- CPU and SuperFX overclock (CPU Turbo / SuperFX Turbo)
- Video options: square pixels, pseudo-transparency

## Install

1. Extract the latest release ZIP to the root of your Pocket SD card.
2. Place a verified 128 KB MK3 BIOS dump at
   `Assets/snes/timboettiger.Pro Action Replay/snes-pro-action-replay-mk3.bin`.
   The BIOS is proprietary Datel firmware and is not distributed here.
3. Load any SNES ROM through the Pocket UI.

## Usage

The core powers on into the MK3 BIOS, the Pro Action Replay UI. Enter codes
there, then start the game from the BIOS menu. Two core options control it:

- **Cheats / Trainer**: whether the launched game runs with cheats applied
  (can also be toggled live in-game)
- **Pro Action Replay**: pause-menu action that jumps back into the BIOS from a
  running game, like the button on the cartridge

## Controls

A USB mouse on the Analogue Dock works as the SNES Mouse automatically (Mario
Paint and similar); the **Mouse Port** option places it on SNES port 1 or 2.
Without a USB mouse, set *Controller Options* to **Mouse** to drive the SNES
Mouse from the D-Pad or left analog stick.

## Documentation

The user manuals and the full reverse-engineering documentation live in the
parent project: <https://github.com/timboettiger/action-replay-mk-iii>.

## Build & release

Pushing a version tag builds and publishes a release via GitHub Actions
(`.github/workflows/build.yml`):

```
git tag v0.3.0 && git push origin v0.3.0            # release
git tag v0.3.0-beta && git push origin v0.3.0-beta  # pre-release
```

It compiles the bitstream (Quartus in Docker), converts the assets, packages the
core, and attaches the ZIP to the release.

To build locally: compile `projects/snes_pocket.qpf` with Quartus, then run
`scripts/build-release.sh`. Other helpers: `scripts/build-loader.sh` (chip32
loader), and `scripts/build-icon-image.sh` / `scripts/build-platform-image.sh`
(PNG to Pocket `.bin`).

## Credits & licence

SNES core by srg320, openFPGA port by agg23, MK3 emulation by Tim Boettiger.
GPL-3.0, see `LICENSE`; redistributions must include source.
