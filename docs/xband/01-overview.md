# 01 — Overview & History

## What XBAND was

XBAND was a dial-up online-gaming service that ran on a cartridge-style modem
that plugged into the SNES (and Sega Genesis) cartridge slot, with the game
cartridge plugged into a pass-through socket on top. It was built by **Catapult
Entertainment** (Cupertino, CA) and launched in late 1994 in the US, with a
short-lived UK rollout. It let two players play certain head-to-head games
against each other over ordinary copper phone lines, and provided e-mail
("XMail"), news, player rankings/ladders, taunts, and custom player icons.

The modem ran at **2400 baud** on a **Rockwell** chipset, plus a Catapult custom
ASIC nick-named **"FRED"** that did the game-patching and the SNES/Genesis bus
glue. SRAM (battery-backed, 64 KB on the retail unit) held the user profile, the
downloaded game patches, mail, news and statistics.

## How a session worked

From `platform/xband/Readme.md`, paraphrased and cross-checked against the
Catapult source:

1. **Dial-up & handshake.** The box dials a central server. After modem carrier
   is established the box sends a 26-byte handshake/"hello" packet; the server
   echoes essentially the same packet back with a couple of modified bytes (the
   ACK flag and a recomputed CRC) to complete the handshake. See
   [04-network-protocol.md](04-network-protocol.md).

2. **The "puke".** Immediately after the handshake the box dumps ("pukes") its
   entire state to the server in one large multi-packet burst: box type, free OS
   and DB memory, flags, last box state, phone number, region/serial, the active
   profile (icon, color, hometown, username), XMail count, personification
   (password/taunt/about), and the **GAME ID** of whatever cartridge is plugged
   in on top. `xbsega.go` contains a complete parser for this dump.

3. **Server work.** The server reads mail/profile/stats, sends down any system
   (OS) patches, mail, news, rankings and — for matchmaking — a **game patch**
   (typically ≤10 KB) for the specific cartridge. It also tells the box how much
   it should report as free.

4. **Matchmaking & play.** To challenge someone the box dials the server, spends
   a minute or two downloading the game patch into SRAM, then the **FRED** chip
   applies that patch to the running game on the fly (think Game Genie, but with
   ~10 programmable patch vectors and the ability to inject whole subroutines).
   The patched game streams controller data between the two consoles and syncs
   vblanks; it switches between interlaced/non-interlaced modes to keep the two
   machines in lock-step.

## Latency — why it was fragile (and why it matters for emulation)

The networked play is extremely latency-sensitive. The community notes and the
in-source docs converge on roughly **35–40 ms of *stable* round-trip latency**
as the absolute ceiling. Copper phone lines gave low, stable latency; modern
VoIP/internet jitter trips the in-game resync code and the game either lags out
or becomes unplayable. Any modern re-implementation that bridges two XBANDs over
IP has to keep jitter very low, not just mean latency.

## Box types

`xbsega.go` and the Catapult source recognise these 4-character box-type tags
(sent in the puke after the `msBoxType` opcode):

| Tag    | Constant  | Platform                         |
| ------ | --------- | -------------------------------- |
| `segb` | `GENESIS` | Sega Genesis / Mega Drive XBAND  |
| `sn07` | `SNES`    | Super Nintendo XBAND (US)        |
| `sj01` | `JSNES`   | Super Famicom XBAND (Japan)      |
| `tj01` | `SATURN`  | Sega Saturn (prototype/unused)   |

> **Endianness gotcha.** The SNES/65816 side is **little-endian**, the Genesis
> 68000 side is **big-endian**. Multi-byte fields in patches and packets must be
> byte-ordered for the target box type. This single fact is the source of a lot
> of "why won't it handshake" pain — keep it front of mind.

## Why we care here

This repository already integrates the Datel **Pro Action Replay MK3** as an
add-on chip (`rtl/chip/mk3/…`) on top of agg23's SNES core. XBAND is the same
*shape* of problem: a cartridge-slot add-on with its own ROM, its own SRAM, a
memory-mapped ASIC, and a bus that sits between the SNES and the game. The MK3
work is therefore a useful template for an XBAND core, and the protocol notes
here are what a separate `fxpakpro`-style project would need to talk to a real
box (or to emulate the server side).
