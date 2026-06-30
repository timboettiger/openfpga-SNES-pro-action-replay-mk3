// Command xbandserver is a small XBAND "modem replacement" server. ESP32
// bridges (or any client) connect over TCP and stream the raw modem bytes a box
// would have exchanged with its on-board modem; the server performs the XBAND
// handshake, parses the box dump, and relays a live match between two boxes that
// requested the same game.
//
// See docs/xband/14-esp32-and-server.md for the full picture.
package main

import (
	"context"
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/timboettiger/openfpga-SNES-pro-action-replay-mk3/server/internal/xband"
)

func main() {
	healthcheck := flag.Bool("healthcheck", false, "dial the listen port and exit 0 if reachable")
	flag.Parse()

	addr := getenv("XBAND_LISTEN", ":7654")

	if *healthcheck {
		runHealthcheck(addr)
		return
	}

	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("listen %s: %v", addr, err)
	}
	log.Printf("XBAND server listening on %s", addr)

	mm := xband.NewMatchmaker()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Close the listener on shutdown so Accept unblocks.
	go func() {
		<-ctx.Done()
		log.Printf("shutting down")
		_ = ln.Close()
	}()

	var connID uint64
	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				log.Printf("accept: %v", err)
				continue
			}
		}
		id := atomic.AddUint64(&connID, 1)
		go handle(ctx, id, conn, mm)
	}
}

func handle(ctx context.Context, id uint64, conn net.Conn, mm *xband.Matchmaker) {
	defer conn.Close()
	lg := log.New(os.Stderr, "", log.LstdFlags|log.Lmicroseconds)
	prefixed := &prefixLogger{l: lg, prefix: "[conn " + itoa(id) + "] "}
	prefixed.Printf("connected from %s", conn.RemoteAddr())

	// Tie the per-connection cancel to the server context.
	cancel := make(chan struct{})
	go func() {
		<-ctx.Done()
		close(cancel)
		_ = conn.SetReadDeadline(time.Now())
	}()

	s := &xband.Session{Conn: conn, MM: mm, Log: prefixed}
	if err := s.Run(cancel); err != nil {
		prefixed.Printf("session ended: %v", err)
	} else {
		prefixed.Printf("session ended")
	}
}

func getenv(k, def string) string {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		return v
	}
	return def
}

// runHealthcheck dials the listen address (using localhost for a bare ":port"
// form) and exits 0 if the TCP connection succeeds, non-zero otherwise.
func runHealthcheck(addr string) {
	dialAddr := addr
	if len(addr) > 0 && addr[0] == ':' {
		dialAddr = "127.0.0.1" + addr
	}
	conn, err := net.DialTimeout("tcp", dialAddr, 2*time.Second)
	if err != nil {
		os.Exit(1)
	}
	_ = conn.Close()
}

type prefixLogger struct {
	l      *log.Logger
	prefix string
}

func (p *prefixLogger) Printf(format string, v ...any) {
	p.l.Printf(p.prefix+format, v...)
}

func itoa(n uint64) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
