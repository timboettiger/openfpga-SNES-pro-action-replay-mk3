# 14 — ESP32 bridge + XBAND server (online play, reimplemented)

This document ties together the two new, fully-implemented pieces that bring
XBAND online play back to life through the Analogue Pocket:

- **ESP32 bridge firmware** — [`firmware/esp32/`](../../firmware/esp32)
- **Dockerized XBAND server** — [`server/`](../../server)

They build directly on the reverse-engineering in this folder: the link-port
feasibility analysis ([12](12-link-cable-esp32.md)), the network protocol
([04](04-network-protocol.md)), the opcode tables ([05](05-opcodes.md)) and the
sample packets ([06](06-sample-packets.md)), plus the working handshake/CRC
reference [`platform/xband/xbsega.go`](../../platform/xband/xbsega.go).

## The two play modes

```
 Mode 1 (local versus, no server):
   Pocket A ──link── ESP32 ──link── Pocket B

 Mode 2 (online via server):
   Pocket #1 ──link── ESP32 ──Wi-Fi/TCP──┐
                                          ├── xband-server ── handshake + relay
   Pocket #2 ──link── ESP32 ──Wi-Fi/TCP──┘
```

- **Mode 1** cross-connects two Pockets' modem byte streams on a single ESP32
  with two link cables. Each Pocket's XBAND core believes it is talking to its
  on-board modem; the ESP32 is the "phone line" between them. Lowest latency, no
  network — best for live matches.
- **Mode 2** bridges one Pocket to the server over Wi-Fi/TCP. The ESP32 replaces
  the **phone line + remote modem**: carrier-up = TCP connected, hang-up = TCP
  closed. The server performs the XBAND handshake, parses the box dump, and
  relays a live match between two boxes that requested the same game.

## What runs where

| Concern                                   | Where                                                      |
| ----------------------------------------- | ---------------------------------------------------------- |
| Pocket link-port byte stream (modem FIFO) | RTL `xband_modem_uart.sv` + a future `xband_link` serialiser (doc 12 §5) |
| Byte pump (both modes)                    | `firmware/esp32/include/xband_bridge.h` (`xband::Bridge`)   |
| Carrier / off-hook / hang-up              | link "sd" strobe → `SerialIO::connected()`; TCP connect/close |
| CRC-16/CCITT, DLE/ETX framing             | `server/internal/xband/crc.go`, `protocol.go`              |
| 26-byte handshake ack                     | `server/internal/xband/protocol.go` (`AckHandshake`)       |
| Box/game identification (puke parse)      | `server/internal/xband/parse.go`                           |
| Opcode message construction (ADSP wrap)   | `server/internal/xband/protocol.go` (`BuildMessage`)       |
| Matchmaking + live relay                  | `server/internal/xband/matchmaker.go`, `session.go`        |

## Transport contract (ESP32 ⇄ Pocket)

The firmware assumes the Pocket presents the modem FIFO as an **async UART** on
the link port: `port_tran_so` = Pocket→ESP32, `port_tran_si` = ESP32→Pocket,
`port_tran_sd` = carrier/online strobe (HIGH while off-hook). This needs a small
`xband_link` RTL block driving those pins instead of the current tri-state
(doc 12 §5); the byte stream it carries is exactly the `phy_tx`/`phy_rx` FIFO
contents of `xband_modem_uart.sv`. Bit rate is `LINK_BAUD` (default 115200).

## Transport contract (ESP32 ⇄ server)

A raw TCP byte stream carrying exactly the modem bytes the box would have sent to
its modem — **no AT commands** (those were between the original server and its
*local* modem; here the ESP32 is the line). The server therefore speaks pure
XBAND framing from the first byte (the 26-byte handshake).

## Verification status

- **Server**: `cd server && go test ./...` — CRC vectors (XMODEM check `0x29B1`),
  handshake ack invariants, ADSP message structure/CRC, puke parsing, and a full
  two-box **handshake → parse → opcode → live relay** integration test over
  `net.Pipe`. An end-to-end test over real TCP (two simulated boxes through the
  running server) was also confirmed during development.
- **Firmware**: the `xband::Bridge` pump is unit-tested on a host
  (`firmware/esp32/test/test_bridge.cpp` → `ALL BRIDGE TESTS PASSED`), covering
  bidirectional transfer, the partial-write carryover (no byte loss) and
  endpoint-disconnect teardown. `src/main.cpp` compiles for both modes.

## Known limitations (carried from the reverse-engineering)

- **Framing**: a `{DLE,ETX}` byte pair inside a payload can split a packet early;
  robust byte-stuffing is unsolved (doc 04 §Framing). Handshake + control opcode
  streams are unambiguous in practice.
- **Latency**: live matches need ~35–40 ms of stable RTT (doc 01). Mode 1 is
  ideal; Mode 2 works on a low-latency LAN.
- **Exact packet sizes** matter; the box silently waits or crashes on wrong
  lengths. The opcode templates match the tested ones in `xbsega.go` /
  `sample_packets.txt`.
- The `xband_link` RTL serialiser that drives the Pocket link-port pins is
  specified here but not yet added to the core build (doc 12 §5).
