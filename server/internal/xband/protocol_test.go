package xband

import (
	"testing"
)

// The MK puke dump from xbsega.go declares box type "segb" and Mortal Kombat's
// game id ab6348e9; we slice a small piece carrying those opcodes to verify the
// parser and CRC against the reference values.

func TestCRC16KnownVector(t *testing.T) {
	// CRC-16/CCITT (XMODEM) of "123456789" with init 0xFFFF, no final xor, is
	// 0x29B1. Our CRC16 applies the XBAND one's-complement, so expect ^0x29B1.
	got := CRC16([]byte("123456789"))
	want := uint16(^uint16(0x29B1))
	if got != want {
		t.Fatalf("CRC16(123456789) = %04x, want %04x", got, want)
	}
}

func TestUpdCRCMatchesReferenceCheck(t *testing.T) {
	// Without the final complement, the XMODEM check value is 0x29B1.
	got := UpdCRC(0xFFFF, []byte("123456789"), 0, 9)
	if got != 0x29B1 {
		t.Fatalf("UpdCRC check = %04x, want 29B1", got)
	}
}

func TestAckHandshake(t *testing.T) {
	rx := make([]byte, HandshakeLen)
	for i := range rx {
		rx[i] = byte(i + 1) // non-trivial, byte0 != 0 so we can see it forced
	}
	rx[24], rx[25] = DLE, ETX

	out, err := AckHandshake(rx)
	if err != nil {
		t.Fatal(err)
	}
	if out[0] != 0x00 {
		t.Errorf("byte0 = %02x, want 00", out[0])
	}
	if out[13] != 0x82 {
		t.Errorf("byte13 (ACK) = %02x, want 82", out[13])
	}
	if out[24] != DLE || out[25] != ETX {
		t.Errorf("terminator = %02x %02x, want 10 03", out[24], out[25])
	}
	// The CRC bytes must be self-consistent: recomputing over 0..21 reproduces them.
	crc := ^UpdCRC(0xFFFF, out, 0, 22)
	if out[22] != byte(crc>>8) || out[23] != byte(crc) {
		t.Errorf("CRC mismatch: have %02x%02x want %04x", out[22], out[23], crc)
	}
}

func TestAckHandshakeShort(t *testing.T) {
	if _, err := AckHandshake(make([]byte, 10)); err == nil {
		t.Fatal("expected error for short handshake")
	}
}

func TestBuildMessageStructure(t *testing.T) {
	data := []byte{MsRegisterPlayer, 0x01, 0x00, 0x00, 0x00, MsEndOfStream}
	pkt := BuildMessage(0xAB, 0xCD, data)

	// 26 (ADSP) + 14 (payload hdr) + len(data) + 4 (trailer)
	want := 26 + 14 + len(data) + 4
	if len(pkt) != want {
		t.Fatalf("packet len = %d, want %d", len(pkt), want)
	}
	// Session id echoed into ADSP bytes 16,17.
	if pkt[16] != 0xAB || pkt[17] != 0xCD {
		t.Errorf("session id = %02x%02x, want ABCD", pkt[16], pkt[17])
	}
	// ADSP CRC over first 22 bytes is self-consistent.
	acrc := ^UpdCRC(0xFFFF, pkt, 0, 22)
	if pkt[22] != byte(acrc>>8) || pkt[23] != byte(acrc) {
		t.Errorf("ADSP CRC mismatch")
	}
	// Must end with DLE/ETX.
	if pkt[len(pkt)-2] != DLE || pkt[len(pkt)-1] != ETX {
		t.Errorf("packet not DLE/ETX terminated")
	}
	// Payload trailer CRC covers payloadHeader+data.
	payStart := 26
	payEnd := len(pkt) - 4
	pcrc := ^UpdCRC(0xFFFF, pkt, payStart, payEnd-payStart)
	if pkt[payEnd] != byte(pcrc>>8) || pkt[payEnd+1] != byte(pcrc) {
		t.Errorf("payload CRC mismatch")
	}
}

func TestSplitPackets(t *testing.T) {
	stream := []byte{0xAA, DLE, ETX, 0xBB, 0xCC, DLE, ETX, 0xDD}
	pkts, rest := SplitPackets(stream)
	if len(pkts) != 2 {
		t.Fatalf("got %d packets, want 2", len(pkts))
	}
	if len(pkts[0]) != 3 || len(pkts[1]) != 4 {
		t.Errorf("packet lengths = %d,%d want 3,4", len(pkts[0]), len(pkts[1]))
	}
	if len(rest) != 1 || rest[0] != 0xDD {
		t.Errorf("rest = %v want [DD]", rest)
	}
}
