package xband

import "testing"

func TestParsePuke(t *testing.T) {
	var d []byte
	// MsBoxType + "segb"
	d = append(d, MsBoxType, 's', 'e', 'g', 'b')
	// MsLogin + osfree(2)+pad(2) + dbfree(2)+pad(2)
	d = append(d, MsLogin, 0x12, 0x34, 0x00, 0x00, 0x56, 0x78, 0x00, 0x00)
	// MsGameIDAndPatchVer + Mortal Kombat id ab6348e9
	d = append(d, MsGameIDAndPatchVer, 0xab, 0x63, 0x48, 0xe9)

	info := ParsePuke(d)
	if info.BoxType != BoxGenesis {
		t.Errorf("BoxType = %q, want %q", info.BoxType, BoxGenesis)
	}
	if info.GameID != "ab6348e9" {
		t.Errorf("GameID = %q, want ab6348e9", info.GameID)
	}
	if info.GameName != "Mortal Kombat" {
		t.Errorf("GameName = %q, want Mortal Kombat", info.GameName)
	}
	if info.OSFree != 0x1234 {
		t.Errorf("OSFree = %04x, want 1234", info.OSFree)
	}
	if info.DBFree != 0x5678 {
		t.Errorf("DBFree = %04x, want 5678", info.DBFree)
	}
}

func TestParsePukeUnknownGame(t *testing.T) {
	d := []byte{MsBoxType, 's', 'n', '0', '7', MsGameIDAndPatchVer, 0xde, 0xad, 0xbe, 0xef}
	info := ParsePuke(d)
	if info.BoxType != BoxSNES {
		t.Errorf("BoxType = %q, want %q", info.BoxType, BoxSNES)
	}
	if info.GameName != "UNKNOWN" {
		t.Errorf("GameName = %q, want UNKNOWN", info.GameName)
	}
}

func TestParsePukeEmpty(t *testing.T) {
	info := ParsePuke(nil)
	if info.BoxType != "" || info.GameID != "" {
		t.Errorf("empty dump should yield empty info, got %+v", info)
	}
}
