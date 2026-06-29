# 05 — Opcode Tables

There are two opcode spaces:

- **Box → Server** ("send" messages the box emits, including inside the puke).
  Numbers come from Catapult `Messages.h` (`kNumPeerOpCodeItems = 10`, so the
  first box→server opcode `msLogin` = 11 = `0x0B`) and match `xbsega.go`.
- **Server → Box** ("receive"/command messages the server sends to the box).
  Numbers come from `Messages.h`. **In `sample_packets.txt` these decimal opcode
  numbers are written as the single leading hex byte** — e.g. `msSetBoxHometown`
  = 56 = `0x38`, and the sample packet starts with `38`.

Peer-to-peer opcodes occupy **1…10** (`kNumPeerOpCodeItems`); `msEndOfStream` /
`msPeerEndOfStream` = **2**.

> Source of truth: `catapult.tar.gz →
> Catapult/Box-16bit-Feb96/Box/OS/OSCore/Messages.h`. `xbsega.go` re-declares the
> box→server set with explicit hex values.

## Box → Server (the box "pukes"/sends these)

| Hex    | Dec | Constant (`xbsega.go` / `Messages.h`) | Meaning                                   |
| ------ | --- | ------------------------------------- | ----------------------------------------- |
| `0x0B` | 11  | `msLogin`                             | Login; followed by OS-free/DB-free etc.   |
| `0x0C` | 12  | `msGameIDAndPatchVersion`             | Cartridge game id + patch version         |
| `0x0D` | 13  | `msDoSendNewsControls`                | News controls                             |
| `0x0E` | 14  | `msChallengeRequest`                  | Challenge/match request                   |
| `0x0F` | 15  | `msSystemVersion`                     | OS/ROM patch version                      |
| `0x10` | 16  | `msSendNGPVersion`                    | NGP (network game patch) list version     |
| `0x11` | 17  | `msDBIDInfo`                          | Database id info                          |
| `0x12` | 18  | `msSendItemFromDB`                    | Send a DB item                            |
| `0x13` | 19  | `msSendFirstItemID`                   | First DB item id                          |
| `0x14` | 20  | `msSendNextItemID`                    | Next DB item id                           |
| `0x15` | 21  | `msSendSendQElements`                 | Send-queue elements                       |
| `0x16` | 22  | `msSendAddressesToVerify`             | Address-book entries to verify            |
| `0x17` | 23  | `msSendNumRankings`                   | Number of rankings on box                 |
| `0x18` | 24  | `msSendFirstRankingID`                | First ranking id                          |
| `0x19` | 25  | `msSendNextRankingID`                 | Next ranking id                           |
| `0x1A` | 26  | `msSendRankingData`                   | Ranking data blob                         |
| `0x1B` | 27  | `msSendInvalidPers`                   | Personification (password/taunt/about)    |
| `0x1C` | 28  | `msSendInterestingDBConstants`        | DB constants                              |
| `0x1D` | 29  | `msSendOutgoingMail`                  | Outgoing XMail                            |
| `0x1E` | 30  | `msSendCreditDebitInfo`               | Credit/debit (billing) info               |
| `0x1F` | 31  | `msBoxType`                           | 4-char box type (`segb`/`sn07`/`sj01`)    |
| `0x20` | 32  | `msSendGameResults`                   | Game results                              |
| `0x21` | 33  | `msSendNoGameResults`                 | No game results                           |
| `0x22` | 34  | `msSendConstant`                      | A constant                                |
| `0x23` | 35  | `msSendGameErrorResults`              | Game error results                        |
| `0x24` | 36  | `msSendNoGameErrorResults`            | No game error results                     |
| `0x25` | 37  | `msSendNetErrors`                     | Net errors                                |
| `0x26` | 38  | `msNoNetErrors`                       | No net errors                             |
| `0x27` | 39  | `msSendHiddenSerials`                 | Hidden serial numbers                     |
| `+30`  | 40  | `msSendBoxMemStats`                   | Box memory stats                          |
| `+31`  | 41  | `msSendBoxLogs`                       | Box logs                                  |

(`msSendBoxMemStats`/`msSendBoxLogs` exist in `Messages.h` beyond the set
`xbsega.go` enumerates.)

## Server → Box (commands the server sends)

These are the opcodes you *craft* (see [06-sample-packets.md](06-sample-packets.md)).
The "Hex" column is the single leading byte used in `sample_packets.txt`.

| Hex    | Dec | Constant                                  | Notes                                       |
| ------ | --- | ----------------------------------------- | ------------------------------------------- |
| `0x01` | 1   | `msUnusedMessageHandler`                  | reserved                                    |
| `0x02` | 2   | `msEndOfStream` / `msPeerEndOfStream`     | end of opcode stream                        |
| `0x03` | 3   | `msGamePatch`                             | push a game patch                           |
| `0x04` | 4   | `msSetDateAndTime`                        | set RTC (odd backwards date format, see 06) |
| `0x05` | 5   | `msServerMiscControl`                     | misc server control                         |
| `0x09` | 9   | `msExecuteCode`                           | execute code on box                         |
| `0x0A` | 10  | `msPatchOSCode`                           | patch the box OS                            |
| `0x0C` | 12  | `msRemoveDBTypeOpCode`                    | remove a DB type                            |
| `0x0D` | 13  | `msRemoveMessageHandler`                  | remove a handler                            |
| `0x0E` | 14  | `msRegisterPlayer`                        | register player / wait-time                 |
| `0x0F` | 15  | `msNewNGPList`                            | new network-game-patch list                 |
| `0x10` | 16  | `msSetBoxSerialNumber`                    | set region+serial                           |
| `0x11` | 17  | `msGetTypeIDsFromDB`                      | query DB type ids                           |
| `0x12` | 18  | `msAddItemToDB`                           | add DB item                                 |
| `0x13` | 19  | `msDeleteItemFromDB`                      | delete DB item                              |
| `0x14` | 20  | `msGetItemFromDB`                         | get DB item                                 |
| `0x15` | 21  | `msGetFirstItemIDFromDB`                  | first DB item id                            |
| `0x16` | 22  | `msGetNextItemIDFromDB`                   | next DB item id                             |
| `0x17` | 23  | `msClearSendQ`                            | "stop sending, I've stored it all"          |
| `0x1B` | 27  | `msLoopBack`                              | network debug loopback                      |
| `0x1C` | 28  | `msWaitForOpponent`                       | wait for opponent                           |
| `0x1D` | 29  | `msOpponentPhoneNumber`                   | call opponent                               |
| `0x1E` | 30  | `msReceiveMail`                           | deliver XMail                               |
| `0x1F` | 31  | `msNewsHeader`                            | news header                                 |
| `0x20` | 32  | `msNewsPage`                              | news page                                   |
| `0x21` | 33  | `msUNUSED1`                               | (was msInstaller)                           |
| `0x22` | 34  | `msQDefDialog`                            | show a dialog box on the TV                 |
| `0x23` | 35  | `msAddAddressBookEntry`                   | add player to player list                   |
| `0x24` | 36  | `msDeleteAddressBookEntry`                | delete address-book entry                   |
| `0x25` | 37  | `msReceiveRanking`                        | stats/ranking screen                        |
| `0x26` | 38  | `msDeleteRanking`                         | delete ranking                              |
| `0x27` | 39  | `msGetNumRankings`                        | number of rankings on box                   |
| `0x28` | 40  | `msGetFirstRankingID`                     | first ranking id                            |
| `0x29` | 41  | `msGetNextRankingID`                      | next ranking id                             |
| `0x2A` | 42  | `msGetRankingData`                        | ranking data                                |
| `0x2B` | 43  | `msSetBoxPhoneNumber`                     | set box phone number                        |
| `0x2C` | 44  | `msSetLocalAccessPhoneNumber`             | set dial-up numbers                         |
| `0x2D` | 45  | `msSetConstants`                          | set constants                               |
| `0x2E` | 46  | `msReceiveValidPers`                      | valid personification                       |
| `0x2F` | 47  | `msGetInvalidPers`                        | invalid personification                     |
| `0x30` | 48  | `msDeleteUncorrelatedAddressBookEntries`  | address-book cleanup                        |
| `0x31` | 49  | `msCorrelateAddressBookEntry`             | correlate address-book entry                |
| `0x32` | 50  | `msReceiveWriteableString`                | writeable string                            |
| `0x33` | 51  | `msReceiveCredit`                         | credit                                      |
| `0x34` | 52  | `msReceiveRestrictions`                   | restrictions                                |
| `0x35` | 53  | `msReceiveCreditToken`                    | credit token                                |
| `0x36` | 54  | `msSetCurrentUserName`                    | set current username                        |
| `0x38` | 56  | `msSetBoxHometown`                        | set hometown                                |
| `0x39` | 57  | `msGetConstant`                           | get a constant                              |
| `0x3A` | 58  | `msReceiveProblemToken`                   | problem token                               |
| `0x3B` | 59  | `msReceiveValidationToken`                | validation token                            |
| `0x3C` | 60  | `msLiveDebitSmartCard`                    | smart-card debit                            |
| `0x3D` | 61  | `msSendDialScript`                        | dial script                                 |
| `0x3E` | 62  | `msSetCurrentUserNumber`                  | set current user number                     |
| `0x3F` | 63  | `msBoxWipeMind`                           | factory-wipe the box                        |
| `0x40` | 64  | `msGetHiddenSerials`                      | get hidden serials                          |
| `0x42` | 66  | `msGetLoadedGameInfo`                     | loaded game info                            |
| `0x43` | 67  | `msClearNetOpponent`                      | clear net opponent                          |
| `0x44` | 68  | `msGetBoxMemStats`                        | get box mem stats                           |
| `0x45` | 69  | `msReceiveRentalSerialNumber`             | rental serial                               |
| `0x46` | 70  | `msReceiveNewsIndex`                      | custom news index                           |
| `0x47` | 71  | `msReceiveBoxNastyLong`                   | "nasty long"                                |

> Gaps (6,7,8,11,…) are unused/renumbered slots in `Messages.h`; the table lists
> only the assigned opcodes. Always terminate an opcode stream with `0x02`
> (`msEndOfStream`).
