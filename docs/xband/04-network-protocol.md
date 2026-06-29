# 04 — Network Protocol

XBAND's wire protocol is a **modified, early variant of AppleTalk ADSP**
(AppleTalk Data Stream Protocol). The reference implementation for everything on
this page is `platform/xband/xbsega.go` (a working Go handshake + parser) backed
by `sample_packets.txt`; both are community reverse-engineering and carry the
original "TESTED / NEEDS TESTING" qualifiers.

## Framing

- Packets are **DLE/ETX framed**: almost every packet ends with the two bytes
  `10 03` (hex) = `DLE` `ETX`.
- **Payload caveat:** any `10 03` byte sequence occurring *inside* a payload (a
  game patch, a long string) will be mistaken for end-of-packet. On the Sega
  side this is a known, unsolved escaping problem when uploading patches to SRAM.
  A robust re-implementation needs byte-stuffing/escaping here.
- The **SNES is little-endian, Sega is big-endian** — order multi-byte fields
  per box type.

## Layering

Once the link is up, an application message is wrapped like this (from
`Send_Message()` in `xbsega.go`):

```
┌────────────────────────┐
│  ADSP header (26 bytes) │  ack/seq + CRC over its own first 22 bytes
├────────────────────────┤
│  Payload header (14 B)  │  ┐
├────────────────────────┤  ├─ CRC-16 is computed over (payload header + data)
│  Payload (opcode+data)  │  ┘   and written into the 4-byte payload trailer
├────────────────────────┤
│  Payload trailer (4 B)  │  CRC_hi CRC_lo 10 03
└────────────────────────┘
```

### CRC-16 (CCITT / XMODEM, 0x1021)

`Updcrc()` is a table-driven CRC-16 with polynomial **0x1021**, init **0xFFFF**,
and the result **bit-inverted** (`crc = ^crc`) before insertion. The 256-entry
table in `xbsega.go` is the standard CCITT/XMODEM table. Pseudocode:

```
crc = 0xFFFF
for each byte b in region:
    crc = ((crc << 8) & 0xFF00) ^ crctab[((crc >> 8) & 0x00FF) ^ b]
crc = ~crc & 0xFFFF        // one's complement
hi = crc >> 8 ; lo = crc & 0xFF
```

> The CRC always covers the **first 22 bytes** of the 26-byte ADSP header
> (everything up to the 2 CRC bytes and the trailing `10 03`), and separately the
> whole payload (payload-header + data) for the payload trailer.

## The 26-byte handshake

The **first** packet the box sends after carrier is **26 bytes**. To complete the
handshake the server echoes that same packet back with three modifications
(`xbsega.go`):

```
rx[0]   = 0x00                       // force first byte to 00
rx[13]  = 0x82                       // set the ACK flag in the ADSP header
crc      = ~Updcrc(0xFFFF, rx, 0,22) // CRC over bytes 0..21
rx[22]  = crc >> 8                    // CRC hi
rx[23]  = crc & 0xFF                  // CRC lo
// bytes 24,25 stay 10 03 (DLE/ETX); send all 26 bytes back
```

So: byte **13 = 0x82** is the ACK flag, bytes **22–23** are the recomputed CRC,
bytes **24–25** are the `10 03` terminator, byte **0** is forced to `00`.

## The outgoing ADSP + payload headers

`Send_Message(DATA)` builds a full packet from three literal templates. The
bytes marked below are the ones it patches at runtime.

**ADSP header (26 bytes):**
```
00 DE AD 00 00 00 00 00 00 00 00 04 00 80 01 00 <rx1> <rx2> 00 00 00 00 AA AA 10 03
                                             │      │     │                 └┴── CRC (recomputed)
                                             │      └─────┴── echoed from handshake bytes 1,2 (session id)
                                             └── 0x80 = control/ack byte
```
- Bytes `DE AD` and the `04 00 80 01` group are fixed ADSP control fields.
- Bytes 16,17 are copied from the handshake's bytes 1,2 (the session/connection
  identifier).
- Bytes 22,23 are overwritten with the CRC of bytes 0..21; bytes 24,25 = `10 03`.

**Payload header (14 bytes):**
```
00 BE EF 00 00 00 00 00 00 00 00 04 00 00
```
The application payload (opcode stream) is appended to this header, then a
**4-byte trailer** `AA AA 10 03` is appended whose first two bytes are replaced
by the CRC over `payloadHeader + data`.

**Full packet** = `ADSP_header ++ (payload_header ++ data ++ payload_trailer)`.

## Connection sequence (end to end)

```
1.  AT / AT&F / ATQ0 / AT+VCID=1 / ATS0=2 / ATM0      (host modem setup)
2.  wait "CONNECT"  →  send CR                          (signal "ready to talk")
3.  read 26-byte handshake packet from box
4.  modify (byte0=00, byte13=0x82, CRC) → send back     (handshake complete)
5.  read the big "puke" dump from the box (use a ≥2 KB buffer)   ← see §below
6.  parse box state + game id  (xbsega.go does this in full)
7.  for each thing to send: Send_Message(opcodeStream)  (ADSP-wrap + CRC)
8.  ATH  → hang up
```

## The "puke" dump

Right after the handshake the box sends one large multi-packet burst. `xbsega.go`
locates fields by scanning for opcodes, then reading fixed-size structures:

| Field                | How it is located/read                                            |
| -------------------- | ----------------------------------------------------------------- |
| `BOXTYPE`            | 4 chars after the `msBoxType` (0x1F) opcode (`segb`/`sn07`/…)      |
| `OSFREE`, `DBFREE`   | longwords right after `msLogin` (0x0B)                             |
| `MISCFLAGS`          | flags longword                                                    |
| `LASTBOXSTATE`       | last box state                                                   |
| `PHONENUMBER`        | 26-byte phone-number field                                       |
| `REGION`, `SERIAL`   | two longwords                                                    |
| `BOXID`/`CLUTID`/`ICONID` | 1 byte each: profile #, color-LUT index, icon id            |
| `HOMETOWN`           | 34-byte null-padded string                                       |
| `USERNAME`           | 34-byte null-padded string (Genesis pads +35, SNES +34)          |
| `XMAILS`             | mail count                                                       |
| `PASSWORD`/`TAUNT`/`ABOUT` | personification, after `msSendInvalidPers` (0x1B); a `0x5D` marker indicates whether a password is set |
| `GAMEID`             | 4 bytes after `msGameIDAndPatchVersion` (0x0C) → mapped to a name |

The `GAMEID → name → patch file` mapping tables in `xbsega.go` are reproduced in
[09-game-patches.md](09-game-patches.md).

## Notes & open problems (from the reverse-engineering)

- Sending packets *back* to the box beyond the handshake + a single test opcode
  is only partially implemented in `xbsega.go`; the framing above is known-good
  but the full server state machine is not.
- Packet **sizes must be exact**. Wrong length/sizing makes the box silently
  wait, time out, or crash. Expect trial-and-error.
- Keep latency low and stable (see [01-overview.md](01-overview.md)).
