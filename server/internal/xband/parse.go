package xband

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
)

// BoxInfo is the subset of the post-handshake "puke" dump that the matchmaker
// needs. Field locations follow the scan logic in xbsega.go (decode section).
type BoxInfo struct {
	BoxType  string // "segb"/"sn07"/"sj01"/"tj01" or "" if not found
	GameID   string // 8 hex chars, e.g. "ab6348e9"; "" if not found
	GameName string // resolved friendly name, "UNKNOWN" if unmapped
	OSFree   uint16
	DBFree   uint16
}

// gameNames maps the 4-byte GAMEID (hex) to a friendly name. Genesis entries are
// the verified ones from xbsega.go; SNES entries are the (commented) candidates
// kept for documentation. Unknown ids resolve to "UNKNOWN".
var gameNames = map[string]string{
	// Genesis (verified in xbsega.go)
	"31ed8123": "Madden 95",
	"ab6348e9": "Mortal Kombat",
	"c4cddf0c": "Mortal Kombat II",
	"e30c296e": "NBA JAM [Rev 1]",
	"8f6b9f70": "NHL 95",
}

// ParsePuke locates the box type and game id inside a raw multi-packet dump.
// It is intentionally tolerant: missing fields are left zero/empty rather than
// panicking, because real dumps vary in size (xbsega.go reads into a 2 KB
// buffer and scans for opcodes).
func ParsePuke(dump []byte) BoxInfo {
	var info BoxInfo

	if i := bytes.IndexByte(dump, MsBoxType); i >= 0 && i+5 <= len(dump) {
		info.BoxType = string(dump[i+1 : i+5])
	}

	if i := bytes.IndexByte(dump, MsLogin); i >= 0 {
		idx := i + 1
		if idx+4 <= len(dump) {
			info.OSFree = binary.BigEndian.Uint16(dump[idx : idx+2])
		}
		if idx+8 <= len(dump) {
			info.DBFree = binary.BigEndian.Uint16(dump[idx+4 : idx+6])
		}
	}

	if i := bytes.IndexByte(dump, MsGameIDAndPatchVer); i >= 0 && i+5 <= len(dump) {
		info.GameID = hex.EncodeToString(dump[i+1 : i+5])
		if name, ok := gameNames[info.GameID]; ok {
			info.GameName = name
		} else {
			info.GameName = "UNKNOWN"
		}
	}

	return info
}
