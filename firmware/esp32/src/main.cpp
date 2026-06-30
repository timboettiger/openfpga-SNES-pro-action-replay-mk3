// main.cpp — XBAND ESP32 bridge firmware (Arduino-ESP32).
//
// Two build-time modes (see include/config.h):
//
//   Mode 1 (XBAND_MODE_LINK_LINK): the ESP32 is wired to TWO Pockets via two
//     link cables and cross-connects their modem byte streams, so the two
//     consoles play head-to-head locally with no server.
//
//   Mode 2 (XBAND_MODE_LINK_WIFI): the ESP32 is wired to ONE Pocket and bridges
//     its modem byte stream over Wi-Fi/TCP to the XBAND server (server/), which
//     performs the handshake and relays the match to a second box.
//
// All byte-moving logic lives in the transport-agnostic xband::Bridge
// (include/xband_bridge.h), which is unit-tested on a host in test/test_bridge.cpp.
#include <Arduino.h>

#include "config.h"
#include "xband_bridge.h"

#if XBAND_MODE == XBAND_MODE_LINK_WIFI
#include <WiFi.h>
#endif

// ---------------------------------------------------------------------------
// Adapters: wrap Arduino streams in the xband::IByteIO interface.
// ---------------------------------------------------------------------------

// SerialIO bridges a HardwareSerial (one Pocket link port). Carrier is taken
// from the link "sd" strobe on cdPin: HIGH = box online / off-hook.
class SerialIO : public xband::IByteIO {
 public:
  SerialIO(HardwareSerial& s, int cdPin) : s_(s), cd_(cdPin) {}
  int available() override { return s_.available(); }
  int read() override { return s_.read(); }
  size_t write(const uint8_t* b, size_t n) override {
    // HardwareSerial.write only accepts as many bytes as fit its TX buffer
    // without blocking once availableForWrite() is honoured.
    size_t room = s_.availableForWrite();
    if (room == 0) return 0;
    size_t n2 = n < room ? n : room;
    return s_.write(b, n2);
  }
  bool connected() override { return digitalRead(cd_) == HIGH; }

 private:
  HardwareSerial& s_;
  int cd_;
};

#if XBAND_MODE == XBAND_MODE_LINK_WIFI
// ClientIO bridges a WiFiClient (the TCP link to the server).
class ClientIO : public xband::IByteIO {
 public:
  explicit ClientIO(WiFiClient& c) : c_(c) {}
  int available() override { return c_.available(); }
  int read() override { return c_.read(); }
  size_t write(const uint8_t* b, size_t n) override { return c_.write(b, n); }
  bool connected() override { return c_.connected(); }

 private:
  WiFiClient& c_;
};
#endif

// ---------------------------------------------------------------------------
// Status LED helper
// ---------------------------------------------------------------------------
static void led(bool on) { digitalWrite(PIN_STATUS_LED, on ? HIGH : LOW); }

static void blink(int times, int ms) {
  for (int i = 0; i < times; i++) {
    led(true);
    delay(ms);
    led(false);
    delay(ms);
  }
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  pinMode(PIN_STATUS_LED, OUTPUT);
  pinMode(PIN_A_CD, INPUT);

  // Link A UART on Serial1.
  Serial1.begin(LINK_BAUD, SERIAL_8N1, PIN_A_RX, PIN_A_TX);

#if XBAND_MODE == XBAND_MODE_LINK_LINK
  pinMode(PIN_B_CD, INPUT);
  // Link B UART on Serial2.
  Serial2.begin(LINK_BAUD, SERIAL_8N1, PIN_B_RX, PIN_B_TX);
  Serial.println(F("XBAND bridge: MODE 1 (link <-> link)"));
#else
  Serial.println(F("XBAND bridge: MODE 2 (link <-> Wi-Fi)"));
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print(F("Wi-Fi connecting"));
  while (WiFi.status() != WL_CONNECTED) {
    delay(250);
    Serial.print('.');
    led(!digitalRead(PIN_STATUS_LED));
  }
  led(false);
  Serial.print(F("\nWi-Fi up, IP="));
  Serial.println(WiFi.localIP());
#endif
}

// ---------------------------------------------------------------------------
// Mode 1: bridge two Pocket link ports
// ---------------------------------------------------------------------------
#if XBAND_MODE == XBAND_MODE_LINK_LINK
void loop() {
  static SerialIO a(Serial1, PIN_A_CD);
  static SerialIO b(Serial2, PIN_B_CD);
  static xband::Bridge bridge(&a, &b);

  // Wait until BOTH boxes have carrier up before relaying.
  if (!a.connected() || !b.connected()) {
    led(false);
    delay(5);
    return;
  }
  led(true);
  // Pump until one side drops; pumpOnce() is non-blocking.
  bridge.pumpOnce();
}
#endif

// ---------------------------------------------------------------------------
// Mode 2: bridge one Pocket link port to the server over Wi-Fi/TCP
// ---------------------------------------------------------------------------
#if XBAND_MODE == XBAND_MODE_LINK_WIFI
void loop() {
  static SerialIO pocket(Serial1, PIN_A_CD);

  // Only dial the server while the box has carrier up (off-hook).
  if (!pocket.connected()) {
    led(false);
    delay(5);
    return;
  }

  WiFiClient client;
  Serial.printf("dialing %s:%d ...\n", XBAND_SERVER_HOST, (int)XBAND_SERVER_PORT);
  if (!client.connect(XBAND_SERVER_HOST, XBAND_SERVER_PORT)) {
    Serial.println(F("server connect failed; retrying"));
    blink(3, 100);
    delay(1000);
    return;
  }
  client.setNoDelay(true);  // latency matters more than throughput (doc 01)
  Serial.println(F("server connected; relaying"));
  led(true);

  ClientIO net(client);
  xband::Bridge bridge(&pocket, &net);

  // Relay until either the box hangs up (carrier down) or the socket drops.
  while (pocket.connected() && client.connected()) {
    if (!bridge.pumpOnce()) break;
    // Yield briefly so Wi-Fi/RTOS housekeeping can run without adding latency.
    delay(0);
  }

  client.stop();
  led(false);
  Serial.printf("session ended (a->b=%u b->a=%u bytes)\n",
                bridge.stats().a_to_b, bridge.stats().b_to_a);
}
#endif
