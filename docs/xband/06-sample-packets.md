# 06 — Sample Packets (annotated)

These are crafted **server → box** opcode payloads from
`platform/xband/sample_packets.txt`. They are the *application payload* only —
to actually send them you must wrap each with the ADSP header + payload header +
recomputed CRC trailer as described in
[04-network-protocol.md](04-network-protocol.md), and append `0x02`
(`msEndOfStream`) where you are ending an opcode stream.

The original `[TESTED] / [NEEDS TESTING] / [IN PROGRESS]` qualifiers are kept.
Spaces are only for readability.

## Identity / profile

**Set Box Serial** — `msSetBoxSerialNumber` (0x10) — *TESTED 100%*
```
10  42947672  42947672
└op └region   └serial
```

**Set Box Hometown** — `msSetBoxHometown` (0x38) — *TESTED 100%*
```
38  5465737420546f776e  00…00     ("Test Town", padded to EXACTLY 34 bytes)
└op └hometown string    └zero pad
```

**Set Current Username** — `msSetCurrentUserName` (0x36) — *TESTED 100%*
```
36  74657374757365723031  00…00   ("testuser01", padded to EXACTLY 34 bytes)
```

**Set Current User Number** — `msSetCurrentUserNumber` (0x3E).

## Phone numbers / dialling

**Set Dial-Up Numbers** — `msSetLocalAccessPhoneNumber` (0x2C) — *TESTED 100%*
```
2C 00 00 <phone 24B padded> 00…  05 00 <phone 24B padded> 0100
└op DBID pad number          flags …second entry…          flags
```

**Set Box Phone Number** — `msSetBoxPhoneNumber` (0x2B) — *TESTED 100%*
(must follow the Set Dial-Up Numbers packet)
```
2B 00 00 35313238363735333039 00…00
└op DBID pad number
```

**Call Opponent** — `msOpponentPhoneNumber` (0x1D) — *TESTED 100%*
```
1D 00 00 <scriptID> <phone> <opponent verification tag, long>
```

## Matchmaking / players

**Register Player** — `msRegisterPlayer` (0x0E) — *TESTED 100%*
```
0E 01000000
└op └wait time (long)
```

**NGP List** (network game patch list) — `msNewNGPList` (0x0F) — *TESTED 100%*
```
0F 0010 0001 0009 C4CDDF0C 00000000 00000003 0010 4D6F7274616C204B6F6D626174203200
└op │    │    │    └GameID  └flags    └patchVer └titleLen └"Mortal Kombat 2\0"
    │    │    └version of list (short)
    │    └count (short)
    └length up to next length (short)
```

**Add Player to Player list** — `msAddAddressBookEntry` (0x23) — *IN PROGRESS*
```
23 00 0059 <region/serial> <userid> <color> <icon> <town34> <username34> <date long> <wins short> <losses short> <filler>
└op DBID len
```

## Dialogs / rankings / queue

**Send Dialog Box** — `msQDefDialog` (0x22) — *NEEDS TESTING*
```
22 0000 00 0000 0000 00000000 [string+00]
└op (totalLen+1) DBID minTime maxTime strLen text(null-terminated)
```
2 s = `120`, 5 s = `300` ticks. `maxTime = 0` ⇒ "sticky" dialog (stays until input).

**Clear Send Queue** — `msClearSendQ` (0x17) — *TESTED 100%*
```
17
```
Tells the box "everything's stored, stop sending it to us".

**Stats / Ranking screen** — `msReceiveRanking` (0x25) — *TESTED 100%*
```
25 00 002E AB6348E9 00 00 <stats struct> 02
└op DBID size └CartID(hex) userID hidden …            └end_stream
```
The **stats struct** is 5 null-separated strings, each ≤20 chars, in this exact
order: `game name`, `current rank`, `current points`, `next rank`, `next points`.
Example decodes to `Mortal Kombat / Black Belt / 69 / No Belt / 200`.

**Delete Ranking** — `msDeleteRanking` (0x26): `26 01` (op + DBID).
**Get #/First/Next Ranking ID** — `0x27` / `0x28` / `0x29` (+DBID for next).
**Get Ranking Data** — `msGetRankingData` (0x2A): `2A <DBID>`; returns the full
5×≤20-char struct (~105 bytes max).

## Date/time encoding (the weird one)

`msSetDateAndTime` (0x04) and `msAddAddressBookEntry` use a packed date **long**
`00 YY MD D` where the box stores the date **backwards** (year, month, day) with
unusual nibble math. Worked example for **9/23/17** vs **9/22/17**:

- **Byte 2 = year in hex:** `17` decimal → `0x11`.
- **Month** = the *upper* nibble's low bits of byte 3: `00=Jan, 10=Feb, 20=Mar,
  30=Apr, 40=May, 50=Jun, 60=Jul, 70=Aug, 80=Sep, 90=Oct, A0=Nov, B0=Dec`.
- **Day** = upper nibble of the month byte, but in **multiples of 2 only**
  (`0→0, 1→2, 2→4, … F→30`), i.e. day/2 goes in that nibble.
- To add **+1** day (odd days) set the *lower* nibble of the last byte to `A`.

So **9/22/17** = `00 11 8B 00` and **9/23/17** = `00 11 8B A0`.

Layout: `00 YY M[D_hi] [D_lo +1?]` → here `Y=0x11 (=17)`, `Sep=0x80`,
`day22 ⇒ B in the day nibble (22/2=11=0xB)` giving `8B`, and the final `A0` adds
the odd +1 day. (Yes, this is genuinely how the box encodes it.)

## Reference debug dumps

`sample_packets.txt`/`xbsega.go` also embed two full captured **"puke" dumps**,
`MK_PUKE` and `MK2_PUKE` (Mortal Kombat / MK2 cartridge connected). Those are
real byte streams you can replay into the parser (`DEBUG=true` in `xbsega.go`
feeds `MK2_PUKE`) without a physical box — invaluable for testing a decoder.
