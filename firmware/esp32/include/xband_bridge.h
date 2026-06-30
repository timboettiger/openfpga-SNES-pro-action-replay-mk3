// xband_bridge.h — transport-agnostic byte pump shared by both firmware modes.
//
// The XBAND core inside the Pocket exchanges a raw modem byte stream over the
// Link Port (see docs/xband/12-link-cable-esp32.md). This bridge moves those
// bytes between two endpoints:
//
//   * Mode 1 (link<->link): endpoint A and B are the two Pocket UARTs — the
//     ESP32 cross-connects two Pockets so they play head-to-head with no server.
//   * Mode 2 (link<->Wi-Fi): endpoint A is the Pocket UART, endpoint B is the TCP
//     connection to the XBAND server (server/), which performs the handshake and
//     relays the match to a second box.
//
// The logic here is intentionally free of Arduino/ESP-IDF types so it can be
// unit-tested on a host (see test/test_bridge.cpp). Concrete adapters wrap
// HardwareSerial / WiFiClient on the device.
#ifndef XBAND_BRIDGE_H
#define XBAND_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

namespace xband {

// IByteIO is the minimal byte-stream interface the bridge needs. It maps cleanly
// onto Arduino HardwareSerial and WiFiClient.
class IByteIO {
 public:
  virtual ~IByteIO() {}
  // Number of bytes available to read without blocking.
  virtual int available() = 0;
  // Read one byte, or -1 if none is available.
  virtual int read() = 0;
  // Write n bytes; returns the number actually accepted (may be < n).
  virtual size_t write(const uint8_t* buf, size_t n) = 0;
  // True while the endpoint is usable (carrier up / socket connected).
  virtual bool connected() = 0;
};

// BridgeStats counts bytes moved in each direction (useful for diagnostics/LEDs).
struct BridgeStats {
  uint32_t a_to_b = 0;
  uint32_t b_to_a = 0;
};

// Bridge pumps bytes both ways between two IByteIO endpoints. It never blocks:
// call pumpOnce() repeatedly from the main loop. A single pumpOnce() moves at
// most kChunk bytes per direction to keep latency low and the loop responsive
// (in-match XBAND traffic tolerates only ~35-40 ms of stable RTT, doc 01).
//
// Partial writes are handled without byte loss: bytes read from a source but not
// yet accepted by the destination are held in a small carryover buffer and
// flushed first on the next pump.
class Bridge {
 public:
  static const size_t kChunk = 64;

  Bridge(IByteIO* a, IByteIO* b) : a_(a), b_(b) {}

  // Returns false once either endpoint has dropped (so the caller can tear the
  // session down and re-establish carrier).
  bool pumpOnce() {
    if (!a_->connected() || !b_->connected()) return false;
    stats_.a_to_b += transfer(a_, b_, ab_);
    stats_.b_to_a += transfer(b_, a_, ba_);
    return true;
  }

  const BridgeStats& stats() const { return stats_; }

 private:
  // A bounded FIFO of bytes that have been read from a source but not yet
  // accepted by the destination.
  struct Carry {
    uint8_t buf[Bridge::kChunk];
    size_t head = 0;  // index of next byte to write
    size_t tail = 0;  // one past the last valid byte
    size_t size() const { return tail - head; }
    bool empty() const { return head == tail; }
    void reset() { head = tail = 0; }
  };

  // Move bytes from src to dst, draining any carryover first. Returns the number
  // of bytes accepted by dst this call.
  size_t transfer(IByteIO* src, IByteIO* dst, Carry& c) {
    size_t accepted = 0;

    // 1. Flush whatever is pending from a previous partial write.
    accepted += flush(dst, c);
    if (!c.empty()) return accepted;  // dst still full; don't read more

    // 2. Read a fresh chunk from src into the carry buffer.
    c.reset();
    while (c.tail < kChunk && src->available() > 0) {
      int b = src->read();
      if (b < 0) break;
      c.buf[c.tail++] = static_cast<uint8_t>(b);
    }

    // 3. Try to write it; anything not accepted stays for the next pump.
    accepted += flush(dst, c);
    return accepted;
  }

  // Write as much of the carry buffer as dst will accept; advance head.
  static size_t flush(IByteIO* dst, Carry& c) {
    size_t wrote = 0;
    while (!c.empty()) {
      size_t w = dst->write(c.buf + c.head, c.size());
      if (w == 0) break;  // dst full this iteration
      c.head += w;
      wrote += w;
    }
    if (c.empty()) c.reset();
    return wrote;
  }

  IByteIO* a_;
  IByteIO* b_;
  Carry ab_;  // carryover for the A->B direction
  Carry ba_;  // carryover for the B->A direction
  BridgeStats stats_;
};

}  // namespace xband

#endif  // XBAND_BRIDGE_H
