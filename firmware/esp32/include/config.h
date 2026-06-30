// config.h — build-time configuration for the XBAND ESP32 bridge firmware.
//
// Override any of these with PlatformIO build_flags (-D...) or a local
// secrets.h; do NOT commit real Wi-Fi credentials.
#ifndef XBAND_CONFIG_H
#define XBAND_CONFIG_H

// ---------------------------------------------------------------------------
// Operating mode
// ---------------------------------------------------------------------------
//   XBAND_MODE_LINK_LINK (1): bridge two Pockets via two link-port UARTs (P2P).
//   XBAND_MODE_LINK_WIFI (2): bridge one Pocket link-port UART to the server.
#define XBAND_MODE_LINK_LINK 1
#define XBAND_MODE_LINK_WIFI 2

#ifndef XBAND_MODE
#define XBAND_MODE XBAND_MODE_LINK_WIFI
#endif

// ---------------------------------------------------------------------------
// Link-port UART wiring (ESP32 <-> Pocket Link Port)
// ---------------------------------------------------------------------------
// The Pocket Link Port exposes port_tran_so/si/sck/sd to the FPGA fabric
// (docs/xband/12-link-cable-esp32.md). A future `xband_link` RTL block serialises
// the modem FIFO as async UART on so (Pocket TX) / si (Pocket RX); sd is the
// carrier/online strobe. Pins below are the ESP32 side.
//
// Link A (used in both modes).
#ifndef PIN_A_RX
#define PIN_A_RX 16  // ESP32 RX  <- Pocket A "so" (serial out)
#endif
#ifndef PIN_A_TX
#define PIN_A_TX 17  // ESP32 TX  -> Pocket A "si" (serial in)
#endif
#ifndef PIN_A_CD
#define PIN_A_CD 4   // carrier-detect / online strobe from Pocket A "sd"
#endif

// Link B (used only in MODE_LINK_LINK).
#ifndef PIN_B_RX
#define PIN_B_RX 25  // ESP32 RX  <- Pocket B "so"
#endif
#ifndef PIN_B_TX
#define PIN_B_TX 26  // ESP32 TX  -> Pocket B "si"
#endif
#ifndef PIN_B_CD
#define PIN_B_CD 27  // carrier-detect / online strobe from Pocket B "sd"
#endif

// Status LED (active-high). Many ESP32 dev boards use GPIO2.
#ifndef PIN_STATUS_LED
#define PIN_STATUS_LED 2
#endif

// Link UART bit rate. Must match the `xband_link` RTL serialiser. The XBAND
// modem ran at 2400 baud over the phone line; the link port can go much faster
// since it is a short local wire. 115200 keeps added latency negligible.
#ifndef LINK_BAUD
#define LINK_BAUD 115200
#endif

// ---------------------------------------------------------------------------
// Wi-Fi + server (MODE_LINK_WIFI only)
// ---------------------------------------------------------------------------
#ifndef WIFI_SSID
#define WIFI_SSID "your-ssid"
#endif
#ifndef WIFI_PASS
#define WIFI_PASS "your-password"
#endif
#ifndef XBAND_SERVER_HOST
#define XBAND_SERVER_HOST "192.168.1.10"  // host running server/ (docker compose)
#endif
#ifndef XBAND_SERVER_PORT
#define XBAND_SERVER_PORT 7654
#endif

#endif  // XBAND_CONFIG_H
