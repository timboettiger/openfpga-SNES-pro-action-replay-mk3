package xband

import (
	"bytes"
	"errors"
	"io"
	"time"
)

// Logger is the minimal logging surface the session needs (satisfied by the
// stdlib *log.Logger).
type Logger interface {
	Printf(format string, v ...any)
}

type nopLogger struct{}

func (nopLogger) Printf(string, ...any) {}

// Session drives a single connected box over a raw modem-byte stream (the bytes
// the box would have exchanged with its on-board modem). The transport is any
// io.ReadWriteCloser: a TCP connection from an ESP32 bridge, or a net.Pipe in
// tests.
type Session struct {
	Conn io.ReadWriteCloser
	MM   *Matchmaker
	Log  Logger

	// PukeIdle is how long to wait for the dump to go quiet before parsing it.
	// Zero uses a sensible default.
	PukeIdle time.Duration
	// MaxPuke caps the dump buffer. Zero uses a default.
	MaxPuke int
}

var errClosed = errors.New("xband: session closed")

// readDeadliner is implemented by net.Conn; tests using net.Pipe also satisfy it.
type readDeadliner interface {
	SetReadDeadline(time.Time) error
}

// Run executes the full per-box flow: handshake → ack → read+parse puke → send
// the initial opcode stream → matchmaking relay. It returns when the box
// disconnects or an unrecoverable error occurs.
func (s *Session) Run(cancel <-chan struct{}) error {
	if s.Log == nil {
		s.Log = nopLogger{}
	}
	if s.PukeIdle == 0 {
		s.PukeIdle = 750 * time.Millisecond
	}
	if s.MaxPuke == 0 {
		s.MaxPuke = 4096
	}

	// 1. Handshake: the first HandshakeLen bytes the box sends.
	hs := make([]byte, HandshakeLen)
	if _, err := io.ReadFull(s.Conn, hs); err != nil {
		return err
	}
	sid1, sid2 := SessionID(hs)
	s.Log.Printf("handshake from box (session %02x%02x)", sid1, sid2)

	// 2. Ack the handshake.
	ack, err := AckHandshake(hs)
	if err != nil {
		return err
	}
	if _, err := s.Conn.Write(ack); err != nil {
		return err
	}

	// 3. Read the puke dump until it goes quiet, then 4. parse it.
	dump := s.readPuke()
	info := ParsePuke(dump)
	s.Log.Printf("box=%q game=%q (%s) osfree=%d dbfree=%d",
		info.BoxType, info.GameID, info.GameName, info.OSFree, info.DBFree)

	// 5. Send an initial opcode stream: register the player and ask the box to
	//    wait for an opponent. Mirrors xbsega.go's test opcode stream.
	stream := []byte{MsRegisterPlayer, 0x01, 0x10, 0x00, 0x00, MsEndOfStream}
	if _, err := s.Conn.Write(BuildMessage(sid1, sid2, stream)); err != nil {
		return err
	}

	// 6. Matchmaking: find a partner with the same game and relay live bytes.
	s.Log.Printf("waiting for an opponent for game %q", info.GameID)
	partner, ok := s.MM.WaitForPartner(info, s.Conn, cancel)
	if !ok {
		return errClosed
	}
	s.Log.Printf("matched — relaying live match for game %q", info.GameID)
	Relay(s.Conn, partner)
	return nil
}

// readPuke reads the post-handshake dump. If the transport supports read
// deadlines it reads until the stream goes idle for PukeIdle; otherwise it reads
// until it has seen a game-id opcode followed by a DLE/ETX terminator or hits
// MaxPuke / EOF.
func (s *Session) readPuke() []byte {
	var buf bytes.Buffer
	tmp := make([]byte, 1024)

	rd, canDeadline := s.Conn.(readDeadliner)
	for buf.Len() < s.MaxPuke {
		if canDeadline {
			_ = rd.SetReadDeadline(time.Now().Add(s.PukeIdle))
		}
		n, err := s.Conn.Read(tmp)
		if n > 0 {
			buf.Write(tmp[:n])
		}
		if err != nil {
			break // idle timeout or EOF: dump is complete
		}
		if !canDeadline && pukeLooksComplete(buf.Bytes()) {
			break
		}
	}
	if canDeadline {
		_ = rd.SetReadDeadline(time.Time{}) // clear deadline for the relay phase
	}
	return buf.Bytes()
}

// pukeLooksComplete is the fallback termination heuristic for transports without
// read deadlines (used by the in-memory tests): the dump is considered done once
// the game-id opcode has appeared and the stream ends with DLE/ETX.
func pukeLooksComplete(b []byte) bool {
	if bytes.IndexByte(b, MsGameIDAndPatchVer) < 0 {
		return false
	}
	return len(b) >= 2 && b[len(b)-2] == DLE && b[len(b)-1] == ETX
}
