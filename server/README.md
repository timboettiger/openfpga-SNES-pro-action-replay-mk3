# XBAND modem-replacement server

A small, dependency-free Go server that plays the role the **phone line + remote
modem** used to play for an XBAND cartridge. Clients (an ESP32 bridge — see
[`../firmware/esp32`](../firmware/esp32) — or anything that speaks raw bytes)
connect over **TCP** and stream the exact modem bytes a box would have exchanged
with its on-board modem. The server performs the XBAND handshake, parses the
box's "puke" dump, and **relays a live match** between two boxes that asked for
the same game.

This implements the protocol documented in
[`../docs/xband/04-network-protocol.md`](../docs/xband/04-network-protocol.md),
[`05-opcodes.md`](../docs/xband/05-opcodes.md) and
[`06-sample-packets.md`](../docs/xband/06-sample-packets.md), and is a faithful
port of the handshake/CRC logic in
[`../platform/xband/xbsega.go`](../platform/xband/xbsega.go).

## What it does

```
 Pocket #1 ─link→ ESP32 ─Wi-Fi/TCP→ ┐
                                     ├─ xband-server ─ handshake, parse, MATCH + RELAY
 Pocket #2 ─link→ ESP32 ─Wi-Fi/TCP→ ┘
```

Per connection the server runs this state machine (`internal/xband/session.go`):

1. **Handshake** — read the 26-byte ADSP handshake packet from the box.
2. **Ack** — echo it back with `byte0=00`, `byte13=0x82` (ACK) and a recomputed
   CRC over bytes 0..21 (`AckHandshake`).
3. **Puke** — read the post-handshake dump until the stream goes idle.
4. **Parse** — locate the box type (`segb`/`sn07`/…) and the cartridge game id
   (`ParsePuke`).
5. **Opcode stream** — send an ADSP-wrapped `msRegisterPlayer` + `msEndOfStream`
   message (`BuildMessage`).
6. **Matchmaking** — wait for another box with the **same game id**, then relay
   the live byte stream between the two (`Matchmaker` + `Relay`).

The transport carries the **raw modem byte stream** (no AT commands — those were
between the original server and its *local* modem; here the ESP32 replaces the
phone line). Carrier-up = TCP connected; hang-up = TCP closed.

## Run with Docker

```sh
cd server
docker compose up --build
# server now listening on 0.0.0.0:7654
```

The image is a static binary on `distroless/static` running as a non-root user.
The compose healthcheck calls the binary's own `-healthcheck` flag, which dials
the listen port.

## Run locally

```sh
cd server
go test ./...                       # unit + integration tests
XBAND_LISTEN=:7654 go run ./cmd/xbandserver
```

## Configuration

| Env var         | Default | Meaning                         |
| --------------- | ------- | ------------------------------- |
| `XBAND_LISTEN`  | `:7654` | TCP listen address              |

CLI: `-healthcheck` dials `XBAND_LISTEN` and exits 0 if reachable (used by the
container healthcheck).

## Layout

| Path                              | Role                                                    |
| --------------------------------- | ------------------------------------------------------- |
| `cmd/xbandserver/main.go`         | TCP listener, per-connection goroutine, healthcheck     |
| `internal/xband/crc.go`           | CRC-16/CCITT table + `UpdCRC`/`CRC16` (from xbsega.go)   |
| `internal/xband/protocol.go`      | Framing, opcodes, handshake ack, ADSP message builder   |
| `internal/xband/parse.go`         | Puke-dump parser (box type, game id, free memory)       |
| `internal/xband/matchmaker.go`    | Pair boxes by game id + bidirectional relay             |
| `internal/xband/session.go`       | Per-box state machine                                    |
| `internal/xband/*_test.go`        | CRC vectors, handshake, message build, parse, relay      |

## Caveats (inherited from the reverse-engineering)

- **Framing**: `{DLE,ETX}` inside a payload can split a packet early. Robust
  byte-stuffing is an unsolved RE problem (doc 04 §Framing); the handshake and
  control opcode streams are unambiguous in practice and that is what the server
  relies on.
- **Latency**: in-match traffic tolerates only ~35–40 ms of *stable* RTT (doc 01).
  Keep the server close to players and prefer the relay path stay thin.
- Packet **sizes must be exact**; the box silently waits or crashes on wrong
  lengths. The opcode templates here match the tested ones in `xbsega.go` /
  `sample_packets.txt`.
