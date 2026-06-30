package xband

import (
	"bytes"
	"errors"
)

// Framing constants (docs/xband/04-network-protocol.md §Framing).
const (
	DLE = 0x10 // data-link escape
	ETX = 0x03 // end-of-text; the pair {DLE,ETX} terminates a packet
)

// Box → Server opcodes (the box "pukes" these). Values from
// docs/xband/05-opcodes.md / Catapult Messages.h / xbsega.go.
const (
	MsLogin             byte = 0x0B
	MsGameIDAndPatchVer byte = 0x0C
	MsChallengeRequest  byte = 0x0E
	MsSystemVersion     byte = 0x0F
	MsBoxType           byte = 0x1F
	MsSendInvalidPers   byte = 0x1B
)

// Server → Box opcodes (commands we craft). Values from docs/xband/05-opcodes.md
// and sample_packets.txt.
const (
	MsEndOfStream         byte = 0x02 // always terminate an opcode stream with this
	MsGamePatch           byte = 0x03
	MsServerMiscControl   byte = 0x05
	MsRegisterPlayer      byte = 0x0E
	MsSetBoxSerialNumber  byte = 0x10
	MsClearSendQ          byte = 0x17
	MsLoopBack            byte = 0x1B
	MsWaitForOpponent     byte = 0x1C
	MsOpponentPhoneNumber byte = 0x1D
	MsQDefDialog          byte = 0x22
	MsSetCurrentUserName  byte = 0x36
	MsSetBoxHometown      byte = 0x38
)

// Known box types (the 4 chars after MsBoxType). From xbsega.go.
const (
	BoxGenesis = "segb"
	BoxSaturn  = "tj01"
	BoxJSNES   = "sj01"
	BoxSNES    = "sn07"
)

// HandshakeLen is the size of the first packet the box sends after carrier.
const HandshakeLen = 26

var (
	// ErrShortHandshake is returned when fewer than HandshakeLen bytes are given.
	ErrShortHandshake = errors.New("xband: handshake packet too short")
)

// AckHandshake takes the 26-byte handshake packet the box sent and returns the
// reply the server must send back to complete the handshake: byte 0 forced to
// 0x00, byte 13 set to the ACK flag 0x82, and bytes 22..23 replaced with the
// recomputed CRC over bytes 0..21. Bytes 24..25 stay {DLE,ETX}.
//
// Mirrors the handshake block in xbsega.go (main()).
func AckHandshake(rx []byte) ([]byte, error) {
	if len(rx) < HandshakeLen {
		return nil, ErrShortHandshake
	}
	out := make([]byte, HandshakeLen)
	copy(out, rx[:HandshakeLen])
	out[0] = 0x00
	out[13] = 0x82
	crc := ^UpdCRC(0xFFFF, out, 0, 22)
	out[22] = byte(crc >> 8)
	out[23] = byte(crc)
	out[24] = DLE
	out[25] = ETX
	return out, nil
}

// SessionID extracts the 2-byte session/connection identifier from a handshake
// packet (bytes 1,2). Send_Message() copies these into the ADSP header.
func SessionID(handshake []byte) (b1, b2 byte) {
	if len(handshake) < 3 {
		return 0, 0
	}
	return handshake[1], handshake[2]
}

// BuildMessage wraps an application opcode stream into a full XBAND message:
// a 26-byte ADSP header (CRC over its first 22 bytes) followed by a 14-byte
// payload header + the opcode stream + a 4-byte trailer (CRC over
// payloadHeader+data, then DLE/ETX).
//
// sid1/sid2 are the session id bytes echoed from the handshake (bytes 1,2).
// This is a faithful port of Send_Message() in xbsega.go.
func BuildMessage(sid1, sid2 byte, data []byte) []byte {
	adsp := []byte{
		0x00, 0xDE, 0xAD, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x04, 0x00, 0x80, 0x01, 0x00,
		sid1, sid2, 0x00, 0x00, 0x00, 0x00, 0xAA, 0xAA,
		DLE, ETX,
	}
	crc := ^UpdCRC(0xFFFF, adsp, 0, 22)
	adsp[22] = byte(crc >> 8)
	adsp[23] = byte(crc)

	payload := []byte{0x00, 0xBE, 0xEF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00}
	payload = append(payload, data...)
	pcrc := ^UpdCRC(0xFFFF, payload, 0, len(payload))
	trailer := []byte{byte(pcrc >> 8), byte(pcrc), DLE, ETX}

	out := make([]byte, 0, len(adsp)+len(payload)+len(trailer))
	out = append(out, adsp...)
	out = append(out, payload...)
	out = append(out, trailer...)
	return out
}

// SplitPackets splits a raw byte stream into DLE/ETX-terminated packets. Each
// returned packet includes its trailing {DLE,ETX}. Any trailing bytes that are
// not yet terminated are returned in rest so a caller can carry them into the
// next read.
//
// NOTE: this is the naive splitter the original used; a {DLE,ETX} occurring
// inside a payload will split early. Byte-stuffing is an unsolved RE problem
// (docs/xband/04 §Framing); for handshake + control opcode streams the terminator
// is unambiguous in practice.
func SplitPackets(stream []byte) (packets [][]byte, rest []byte) {
	term := []byte{DLE, ETX}
	for {
		i := bytes.Index(stream, term)
		if i < 0 {
			rest = stream
			return
		}
		end := i + 2
		pkt := make([]byte, end)
		copy(pkt, stream[:end])
		packets = append(packets, pkt)
		stream = stream[end:]
	}
}
