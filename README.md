# Pro Action Replay MK3 for Analogue Pocket

A SNES core for the Analogue Pocket that integrates the Datel **Pro Action Replay
MK3** cheat cartridge on top of [agg23's openFPGA SNES core](https://github.com/agg23/openfpga-SNES)
(a port of [srg320's MiSTer SNES](https://github.com/MiSTer-devel/SNES_MiSTer)). When the core starts, it first asks for a regular game rom. It then boots into the MK3 UI, where you can manage cheat codes, speed and trainer features. Starting the game from the UI applies the cheats and all settings. You can toggle cheats live in the openFPGA core menu. You can jump back to the MK3 UI from the core menu, too. Optional OSD shows the original cartridge's front-panel LEDs, which indicate the status of the cheat groups and trainer progress.

Additionally it adds support for the SNES mouse on the Analogue Dock. Some games require the SNES mouse at port 1, while others require it at port 2. The core's *Mouse Port* option allows you to choose which one. On the go - without a USB mouse - the D-Pad emulates the SNES Mouse as intended by agg23.

---

This repository is part of the larger [Project Preservation](https://github.com/timboettiger/action-replay-mk-iii), which includes the reverse-engineering documentation, user manuals and other interesting things about the Pro Action Replay MK3 for SNES.

---

## Features

### This core adds

- **Pro Action Replay MK3:** Support for the Pro Action Replay MK3 bios rom.
- **Cheat List:** Your chosen cheats are persisted using a seperate mk3sav file.
- **Cartridge LEDs:** OSD of the cartridge's front-panel LEDs, placeable in any corner or hidden.
- **Mouse on Analogue Dock:** an USB mouse acts as the SNES Mouse, on SNES port 1 or 2 (Mouse Port).

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
there, then start the game from the BIOS menu. Three core options control it:

- **Cheats / Trainer**: whether the launched game runs with cheats applied
  (can also be toggled live in-game)
- **Pro Action Replay**: pause-menu action that jumps back into the BIOS from a
  running game, like the button on the cartridge
- **Mouse Port**: any USB mouse on the Analogue Dock works as the SNES Mouse,
  this option chooses which port is going to be used.

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
