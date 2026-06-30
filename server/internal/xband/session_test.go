package xband

import (
	"bytes"
	"io"
	"net"
	"testing"
	"time"
)

// box simulates a connected XBAND box over one end of a net.Pipe: it sends a
// handshake, expects the ack, sends a puke dump, expects the initial opcode
// stream, then exchanges a couple of live bytes with its opponent.
type boxResult struct {
	ack       []byte
	opcodeMsg []byte
	relayRecv []byte
	err       error
}

func runBox(conn net.Conn, gameID []byte, send, wantRecv []byte) <-chan boxResult {
	out := make(chan boxResult, 1)
	go func() {
		var res boxResult
		defer func() { conn.Close(); out <- res }()

		// 1. handshake (26 bytes); bytes 1,2 are the session id.
		hs := make([]byte, HandshakeLen)
		hs[1], hs[2] = 0x12, 0x34
		hs[24], hs[25] = DLE, ETX
		if _, err := conn.Write(hs); err != nil {
			res.err = err
			return
		}
		// 2. read ack.
		res.ack = make([]byte, HandshakeLen)
		if _, err := io.ReadFull(conn, res.ack); err != nil {
			res.err = err
			return
		}
		// 3. send a minimal puke: box type + game id opcode + DLE/ETX.
		puke := []byte{MsBoxType, 's', 'e', 'g', 'b', MsGameIDAndPatchVer}
		puke = append(puke, gameID...)
		puke = append(puke, DLE, ETX)
		if _, err := conn.Write(puke); err != nil {
			res.err = err
			return
		}
		// 4. read the server's initial opcode message (ADSP-wrapped).
		buf := make([]byte, 256)
		n, err := conn.Read(buf)
		if err != nil {
			res.err = err
			return
		}
		res.opcodeMsg = append([]byte(nil), buf[:n]...)

		// 5. live relay: send our bytes, read the opponent's.
		if _, err := conn.Write(send); err != nil {
			res.err = err
			return
		}
		got := make([]byte, len(wantRecv))
		if _, err := io.ReadFull(conn, got); err != nil {
			res.err = err
			return
		}
		res.relayRecv = got
		return
	}()
	return out
}

func TestSessionHandshakeAndMatchRelay(t *testing.T) {
	mm := NewMatchmaker()
	gameID := []byte{0xab, 0x63, 0x48, 0xe9} // Mortal Kombat

	srvA, boxA := net.Pipe()
	srvB, boxB := net.Pipe()

	cancel := make(chan struct{})
	defer close(cancel)

	sessDone := make(chan error, 2)
	mkSession := func(c net.Conn) {
		s := &Session{Conn: c, MM: mm, Log: nopLogger{}, PukeIdle: 80 * time.Millisecond}
		sessDone <- s.Run(cancel)
	}
	go mkSession(srvA)
	go mkSession(srvB)

	resA := runBox(boxA, gameID, []byte("FROM-A"), []byte("FROM-B"))
	resB := runBox(boxB, gameID, []byte("FROM-B"), []byte("FROM-A"))

	a := <-resA
	b := <-resB

	if a.err != nil {
		t.Fatalf("box A error: %v", a.err)
	}
	if b.err != nil {
		t.Fatalf("box B error: %v", b.err)
	}

	// Handshake ack checks (byte0=00, byte13=0x82, DLE/ETX terminator).
	for name, ack := range map[string][]byte{"A": a.ack, "B": b.ack} {
		if ack[0] != 0x00 || ack[13] != 0x82 || ack[24] != DLE || ack[25] != ETX {
			t.Errorf("box %s: bad ack %x", name, ack)
		}
	}

	// Initial opcode message must be a well-formed ADSP message echoing the
	// session id and containing the register-player opcode.
	if a.opcodeMsg[16] != 0x12 || a.opcodeMsg[17] != 0x34 {
		t.Errorf("opcode msg session id = %02x%02x, want 1234", a.opcodeMsg[16], a.opcodeMsg[17])
	}
	if !bytes.Contains(a.opcodeMsg, []byte{MsRegisterPlayer}) {
		t.Errorf("opcode msg missing register-player opcode")
	}

	// Live relay crossed correctly.
	if string(a.relayRecv) != "FROM-B" {
		t.Errorf("box A received %q, want FROM-B", a.relayRecv)
	}
	if string(b.relayRecv) != "FROM-A" {
		t.Errorf("box B received %q, want FROM-A", b.relayRecv)
	}

	// Both sessions should finish.
	for i := 0; i < 2; i++ {
		select {
		case <-sessDone:
		case <-time.After(2 * time.Second):
			t.Fatal("session did not finish")
		}
	}
}

func TestMatchmakerCancel(t *testing.T) {
	mm := NewMatchmaker()
	srv, _ := net.Pipe()
	defer srv.Close()
	cancel := make(chan struct{})
	done := make(chan bool, 1)
	go func() {
		_, ok := mm.WaitForPartner(BoxInfo{GameID: "x"}, srv, cancel)
		done <- ok
	}()
	time.Sleep(20 * time.Millisecond)
	close(cancel)
	select {
	case ok := <-done:
		if ok {
			t.Fatal("expected cancel to return ok=false")
		}
	case <-time.After(time.Second):
		t.Fatal("WaitForPartner did not unblock on cancel")
	}
}
