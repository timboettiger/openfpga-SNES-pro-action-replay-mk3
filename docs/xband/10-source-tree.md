# 10 — Catapult Source-Tree Map

`platform/xband/catapult.tar.gz` (≈16,500 entries) is the recovered Catapult
Entertainment source — both the **box** (firmware) and **server** sides. This
page is a navigation map so you can find the authoritative implementation of
anything in these docs. (The tree is in old Mac MPW form: `.finderinfo` /
`.resource` / `:b9` sidecar entries can be ignored.)

> Other recovered bundles in the submodule — `XBand Original Compilation.7z`,
> `catapult (2).zip`, `MiscCatapult.zip`, `Keyboard.zip` — overlap with this tree
> and add the SNES/Saturn keyboard accessory sources.

## Top level

```
Catapult/
├── Box-16bit-Feb96/     ← box (cartridge) firmware, Feb 1996 snapshot
├── Server-16bit-Dec94/  ← server, Dec 1994
├── Server-16bit-Mar96pre/  Server-16bit-Mar96post/  ← server, Mar 1996
├── Server-pc-Mar96/     ← PC port of the server
├── MegaPack/            ← the .mp patch (de)compressor (LZB + digram coder)
├── Install.Nov94/       ← installer
└── Misc/                ← docs, known game ids, phone translation, test data
```

## `Box-16bit-Feb96/` (the firmware)

```
Box/
├── OS/
│   ├── OSCore/          ← message dispatch + opcode tables  ★
│   │   ├── Messages.h / Messages.c / MessDisp.c   ← OPCODES (see doc 05)
│   │   ├── Dispatcher.c / DispatcherControl.h
│   │   ├── Exceptions.h / Globals.h / SegaOS.c
│   │   └── OSManagers.h
│   ├── Database/        ← the on-box DB (profiles, rankings, mail, NGP list)
│   ├── GameLib/         ← game-side helper library
│   ├── Graphics/  Shell/  UserInterface/   ← box UI (FindOpponent.c, Events.h)
│   ├── Interfaces/  Misc/  DebugTools/
├── Comm/                ← comms layer (ADSP/serial)  ★
├── GameTalk/            ← in-game networking glue (vblank sync, controller xfer) ★
├── SNES/                ← SNES-specific box code  ★ (most relevant here)
├── Genesis/             ← Genesis box code (Cartridge/Hardware/Runtime/SimVDP/…)
├── MazeGame/            ← bundled demo game
└── SegaChannel/         ← Sega Channel variant (SegaOS/OSCore/Messages.* etc.)
GamePatches/             ← per-game network patch sources (RR3, MKCore.a, …)  ★
SNESObj/                 ← built SNES objects
Sega1.0/                 ← Sega 1.0 build
Server/                  ← server bits bundled with the box snapshot
Tools/
├── ModemTester/         ← FRED + modem diagnostics  ★★ (defines.h / fredtest.c)
│   ├── defines.h        ← FRED REGISTER MAP (see doc 07)
│   ├── fredtest.c       ← FRED presence/self-test
│   ├── modem.c / ModemTest.h / Main.c
├── Flasher/             ← flash programmer (flashmap)
└── Commands/            ← ORCA/MPW command glue
```

★ = files referenced directly by these docs. The two starred-★★ files
(`Tools/ModemTester/defines.h`, `fredtest.c`) are the primary hardware source of
truth for [07-fred-register-map.md](07-fred-register-map.md).

## Servers

```
Server-16bit-Mar96post/
├── Comm/        GameTalk/     SegaOS/      SegaServer/
├── proto/       newrpc/       UNIX/        build/   doc/
Server-pc-Mar96/
├── include/  lib/  bin/  conf/  build/  doc/   (CVS/ metadata present)
```

The servers implement the *other* end of the opcodes in
[05-opcodes.md](05-opcodes.md) — useful if you want to stand up a modern XBAND
server (the actual goal for an `fxpakpro`-style extension).

## `MegaPack/` (patch compression)

```
MegaPack/
├── LzbDict.c  un_main.c  unlzb  MegaPack.h  HuffTable.h  Generic.c  Debug.c
├── Digram/    ← digram-pair coder (DigramTab.c, scanpair.c, *.mp samples)
├── Calgary/   ← compression-corpus test harness
└── Carts/     ← cart_lzss(.c) cartridge compressor
```

Reference for unpacking `.mp` game patches (see [09-game-patches.md](09-game-patches.md)).

## `Misc/` (worth a look)

```
Misc/
├── known_game_ids.gz   ← fuller GAMEID list than xbsega.go embeds
├── doom_pkt/           ← DOOM network packet captures
├── PhoneXlate.xyzzy    ← phone-number translation
├── match_rates  mail.targets  Japan/  Tankhunt/  Doc/
```

`known_game_ids.gz` is the best place to extend the `(BOXTYPE, GAMEID) → title`
tables beyond what [09-game-patches.md](09-game-patches.md) reproduces.
