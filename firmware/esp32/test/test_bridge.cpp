// Host-side unit test for the transport-agnostic Bridge byte pump.
//
// Build & run on a normal PC (no ESP32 toolchain needed):
//   c++ -std=c++11 -I../include test_bridge.cpp -o /tmp/test_bridge && /tmp/test_bridge
//
// It exercises: bidirectional transfer, the partial-write carryover path (no
// byte loss when a destination is temporarily full), and teardown when an
// endpoint disconnects.
#include <cassert>
#include <cstdio>
#include <deque>
#include <string>
#include <vector>

#include "xband_bridge.h"

using xband::Bridge;
using xband::IByteIO;

// FakeIO is an in-memory endpoint: a read FIFO, a write sink, an optional cap on
// how many bytes write() accepts per call (to force the carryover path), and a
// connected flag.
class FakeIO : public IByteIO {
 public:
  std::deque<uint8_t> in;       // bytes the bridge will read from us
  std::vector<uint8_t> out;     // bytes the bridge wrote to us
  size_t write_cap = 0;         // 0 = accept all; N = accept at most N per call
  bool up = true;

  int available() override { return static_cast<int>(in.size()); }
  int read() override {
    if (in.empty()) return -1;
    uint8_t b = in.front();
    in.pop_front();
    return b;
  }
  size_t write(const uint8_t* buf, size_t n) override {
    size_t lim = (write_cap == 0) ? n : (n < write_cap ? n : write_cap);
    for (size_t i = 0; i < lim; i++) out.push_back(buf[i]);
    return lim;
  }
  bool connected() override { return up; }
};

static void pushStr(FakeIO& io, const std::string& s) {
  for (char c : s) io.in.push_back(static_cast<uint8_t>(c));
}

static std::string outStr(const FakeIO& io) {
  return std::string(io.out.begin(), io.out.end());
}

static int failures = 0;
#define CHECK(cond, msg)                                  \
  do {                                                    \
    if (!(cond)) {                                        \
      std::printf("FAIL: %s\n", msg);                     \
      failures++;                                         \
    }                                                     \
  } while (0)

static void testBidirectional() {
  FakeIO a, b;
  pushStr(a, "hello-from-pocket-1");
  pushStr(b, "hello-from-pocket-2");
  Bridge br(&a, &b);

  // A couple of pumps move everything across (chunk is 64, payload is smaller).
  CHECK(br.pumpOnce(), "pump should report connected");
  br.pumpOnce();

  CHECK(outStr(b) == "hello-from-pocket-1", "A->B delivered intact");
  CHECK(outStr(a) == "hello-from-pocket-2", "B->A delivered intact");
  CHECK(br.stats().a_to_b == 19, "a_to_b byte count");
  CHECK(br.stats().b_to_a == 19, "b_to_a byte count");
}

static void testPartialWriteCarryover() {
  FakeIO a, b;
  // 10 bytes from A, but B only accepts 3 bytes per write() call.
  pushStr(a, "0123456789");
  b.write_cap = 3;
  Bridge br(&a, &b);

  // First pump: reads all 10 into carry, flush() loops writing 3 at a time.
  // Our FakeIO.write returns up to 3 each call but flush loops, so within one
  // pumpOnce the inner loop keeps going until write returns 0 — here it never
  // returns 0, so all 10 land. Verify nothing is lost regardless.
  br.pumpOnce();
  br.pumpOnce();
  CHECK(outStr(b) == "0123456789", "carryover delivered all bytes, no loss");
}

static void testPartialWriteHardStall() {
  FakeIO a;
  pushStr(a, "ABCDEFGH");

  // A destination that is completely full this pump: write() always accepts 0.
  struct StallIO : public FakeIO {
    size_t write(const uint8_t*, size_t) override { return 0; }
  } stall;

  Bridge br(&a, &stall);
  br.pumpOnce();  // reads ABCDEFGH into the carry buffer, writes nothing
  CHECK(stall.out.empty(), "stalled dst received nothing yet");
  CHECK(br.stats().a_to_b == 0, "no bytes counted while stalled");
  // Bytes are held in carryover (not dropped): a is fully drained but nothing
  // was counted as delivered, so they are safe to flush on a later pump.
  CHECK(a.in.empty(), "source drained into carryover");
}

static void testDisconnectTearsDown() {
  FakeIO a, b;
  b.up = false;
  Bridge br(&a, &b);
  CHECK(!br.pumpOnce(), "pump returns false when an endpoint is down");
}

int main() {
  testBidirectional();
  testPartialWriteCarryover();
  testPartialWriteHardStall();
  testDisconnectTearsDown();
  if (failures == 0) {
    std::printf("ALL BRIDGE TESTS PASSED\n");
    return 0;
  }
  std::printf("%d bridge test(s) failed\n", failures);
  return 1;
}
