package xband

import (
	"io"
	"sync"
)

// Peer is one connected box waiting to be matched. It carries the box info and
// a channel used to hand it a partner once one is found.
type peer struct {
	info    BoxInfo
	conn    io.ReadWriteCloser
	partner chan io.ReadWriteCloser
}

// Matchmaker pairs boxes that want to play the same game and relays the live
// byte stream between the two once paired. It is safe for concurrent use.
//
// Pairing key: the GameID from the puke dump (so two boxes only match if they
// have the same cartridge). Boxes with an empty GameID are matched in a single
// shared "any" pool so the relay still works for testing / unknown carts.
type Matchmaker struct {
	mu      sync.Mutex
	waiting map[string]*peer
}

// NewMatchmaker returns an empty matchmaker.
func NewMatchmaker() *Matchmaker {
	return &Matchmaker{waiting: make(map[string]*peer)}
}

func matchKey(info BoxInfo) string {
	if info.GameID == "" {
		return "any"
	}
	return info.GameID
}

// WaitForPartner registers conn as waiting to play info.GameID. If another box
// is already waiting on the same key it returns that box's conn immediately and
// hands this conn to the waiting box. Otherwise it blocks until a partner
// arrives or cancel is closed. It returns (nil, false) if cancelled.
func (m *Matchmaker) WaitForPartner(info BoxInfo, conn io.ReadWriteCloser, cancel <-chan struct{}) (io.ReadWriteCloser, bool) {
	key := matchKey(info)

	m.mu.Lock()
	if other, ok := m.waiting[key]; ok {
		// A partner is already waiting: pair them up.
		delete(m.waiting, key)
		m.mu.Unlock()
		other.partner <- conn // wake the waiting box with our conn
		return other.conn, true
	}
	self := &peer{info: info, conn: conn, partner: make(chan io.ReadWriteCloser, 1)}
	m.waiting[key] = self
	m.mu.Unlock()

	select {
	case p := <-self.partner:
		return p, true
	case <-cancel:
		// Remove ourselves from the pool if we are still the one registered.
		m.mu.Lock()
		if cur, ok := m.waiting[key]; ok && cur == self {
			delete(m.waiting, key)
		}
		m.mu.Unlock()
		return nil, false
	}
}

// Relay copies bytes in both directions between a and b until either side
// closes or errors. It returns after both copy directions have finished.
func Relay(a, b io.ReadWriteCloser) {
	var wg sync.WaitGroup
	wg.Add(2)
	cp := func(dst io.Writer, src io.Reader) {
		defer wg.Done()
		_, _ = io.Copy(dst, src)
		// Closing the writers unblocks the opposite copy.
		if c, ok := dst.(io.Closer); ok {
			_ = c.Close()
		}
	}
	go cp(a, b)
	go cp(b, a)
	wg.Wait()
}
