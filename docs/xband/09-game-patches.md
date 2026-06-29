# 09 — Game Patches & FRED Patching

## How patching works

XBAND game patches are the network-game code injected into a *stock* cartridge.
They are conceptually like Game Genie / Pro Action Replay codes but far more
powerful: instead of a few value overrides, FRED exposes **11 patch vectors**
plus zero-page / trans-address remapping and "safe RAM/ROM" ranges (see
[07-fred-register-map.md](07-fred-register-map.md)), so a patch can redirect game
addresses into whole **injected subroutines** running from XBAND SRAM. Those
routines stream controller input between the two consoles, sync vblanks, and
flip interlace modes to keep the machines in lock-step.

A retail patch is "10 KB or smaller", downloaded into the 64 KB battery SRAM
during matchmaking, then applied on the fly. Without these patches the *gaming*
side of XBAND is a lost cause — they are rare.

> **Escaping caveat:** a patch payload containing the bytes `10 03` (DLE/ETX)
> will prematurely terminate a packet on the Sega side. This is a known,
> unsolved upload problem (`platform/xband/Readme.md`); a re-implementation needs
> byte-stuffing. See [04-network-protocol.md](04-network-protocol.md).

## Surviving patches in the submodule

`platform/xband/XBAND_Game_Patches.zip`:

```
XBAND Game Patches/
  Sega/  MADDEN95.SEGA  MK.SEGA  MK2.SEGA  NBAJAM.SEGA  NHL95.SEGA  SSF2.SEGA
  SNES/  SSF2.JSNES
```

Additional patch **source** (assembly) lives in `catapult.tar.gz` under
`Catapult/Box-16bit-Feb96/GamePatches/` (e.g. `RR3/`, `MKCore.a`) and the
`.mp` (MegaPack-compressed) forms appear under `Catapult/MegaPack/`.

Per `platform/xband/Readme.md`: for Sega there are MK, MK2, NBA Jam, Madden 95
and NHL 94/95 patches *with* some source; for SNES only **binary** copies of
Super Mario Kart and a Japanese Super Street Fighter II survive (dumped from a
Japanese XBAND, confirmed working between boxes).

## GAMEID → name → patch-file map (from `xbsega.go`)

The box reports a 4-byte **GAMEID** after `msGameIDAndPatchVersion` (0x0C);
`xbsega.go` maps it. Active (uncommented) Sega mappings ship a patch path:

| GAMEID (hex) | Game               | Patch file (`xbsega.go`)         |
| ------------ | ------------------ | -------------------------------- |
| `31ed8123`   | Madden 95          | `/xband/patches/segb/nfl95.mp`   |
| `ab6348e9`   | Mortal Kombat      | `/xband/patches/segb/mk.mp`      |
| `c4cddf0c`   | Mortal Kombat II   | `/xband/patches/segb/mk2.mp`     |
| `e30c296e`   | NBA JAM [Rev 1]    | `/xband/patches/segb/nbajam.mp`  |
| `8f6b9f70`   | NHL 95             | `/xband/patches/segb/nhl95.mp`   |

`xbsega.go` additionally carries a **commented-out** catalogue of GAMEIDs the
service knew about (kept here because it documents which titles XBAND supported):

**Sega Genesis (`segb`):** NBA Jam [Rev 2] `39677bdb`, NHL 94 `a61b53f8`,
Road Rash 3 `3fed23f2`, NBA Live 95 `00192660`, FIFA Soccer 95 `433e2840`,
WeaponLord [v1] `4a017a94` / [v2] `bf33efc7`, Primal Rage `c6906e52`,
Rampart `51a5e383`, Ballz `067a218f`, Madden 96 `4d402d90`, NHL 96 `afc0ce39`,
Mortal Kombat 3 `6d14eb41`, Super Street Fighter II `4d1c4e1d`.

**SNES (`sn07`, US):** Mortal Kombat II [Rev1] `c4cddf0c` / [Rev2] `c0432172`,
NHL 95 `127e8181`, NBA Jam T.E. `1969d2af`, Super Street Fighter II `ef120a61`,
Madden 95 `b8958396`, FIFA Int'l Soccer `972404cc`, Super Mario Kart `3d1c44eb`,
NBA Live 95 `19a2c936`, WeaponLord [Rev1] `0572a585` / [Rev2] `0572dd87`,
Ken Griffey Baseball `a8973c8c`, Killer Instinct `2d17c045`, Madden 96
`085d3cdb`, NHL 96 `25f372a5`, DOOM `94b564b5`, Mortal Kombat 3 `05484971`,
Kirby's Avalanche `83e627ef`, Zelda: A Link to the Past `8f6b9f70`.

**Super Famicom (`sj01`, Japan):** Super Street Fighter II `d8222103`,
Super Mario Kart `0a2c238a`, Super Fire ProWrestling X `925b41fc`.

**Sega Saturn (`tj01`, prototype):** placeholder list (Decathlete, Virtual On,
Puyo Puyo Sun, Puzzle Bobble 3, Saturn Bomberman, Virtua Fighter Remix, World
Series Baseball, Sega Worldwide Soccer '98, Sega Rally + , Daytona USA CCE) — IDs
were never finalised (`00000000…00000009` placeholders).

> Note the same hex (`8f6b9f70`, `c4cddf0c`) maps to different titles on
> different platforms — **GAMEID is only unique within a box type**. Always key
> your patch lookup on `(BOXTYPE, GAMEID)`.

## `.mp` MegaPack format

Patches are stored compressed ("MegaPack" — LZB/digram coder). The
compressor/decompressor source is in `catapult.tar.gz → Catapult/MegaPack/`
(`LzbDict.c`, `un_main.c`, `unlzb`, `MegaPack.h`, `Digram/`). If you need to
unpack a `.mp` to study the injected code, that directory has the reference
implementation.
