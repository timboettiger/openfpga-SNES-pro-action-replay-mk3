# XBAND ESP32 bridge firmware

Firmware that turns an ESP32 into the **modem replacement** for the XBAND
cartridge running on an Analogue Pocket. It tunnels the XBAND core's raw modem
byte stream off the Pocket **Link Port** (see
[`../../docs/xband/12-link-cable-esp32.md`](../../docs/xband/12-link-cable-esp32.md))
in one of two modes:

| Mode | Build env          | Topology                                              |
| ---- | ------------------ | ----------------------------------------------------- |
| 1    | `mode1_linklink`   | ESP32 wired to **two** Pockets via two link cables — cross-connects them so the two consoles play **head-to-head locally**, no server. |
| 2    | `mode2_wifi`       | ESP32 wired to **one** Pocket — bridges its modem stream over **Wi-Fi/TCP** to the [`server/`](../../server), which handshakes and relays the match to a second box. |

```
 Mode 1:  Pocket A ─link─ ESP32 ─link─ Pocket B          (local versus)
 Mode 2:  Pocket ──link── ESP32 ──Wi-Fi/TCP── xband-server ──…── Pocket #2
```

## How it works

All byte-moving logic is in the transport-agnostic
[`include/xband_bridge.h`](include/xband_bridge.h) (`xband::Bridge`): it pumps
bytes both ways between two `IByteIO` endpoints, in bounded non-blocking chunks,
with a carryover buffer so a temporarily-full destination never drops bytes.
Because it has no Arduino dependencies it is unit-tested on a host
([`test/test_bridge.cpp`](test/test_bridge.cpp)).

`src/main.cpp` wraps the concrete transports in `IByteIO` adapters:

- `SerialIO` — a Pocket link-port UART (`HardwareSerial`), with carrier taken
  from the link "sd" online strobe.
- `ClientIO` — the `WiFiClient` TCP link to the server (Mode 2 only).

Carrier handling mirrors the original phone line: in Mode 2 the ESP32 only dials
the server while the box is "off-hook" (carrier strobe high), and tears the
session down when the box hangs up or the socket drops. In Mode 1 it relays only
while **both** boxes have carrier up.

## The Pocket side (RTL, not yet wired)

The firmware expects the Pocket to present the modem FIFO as an async UART on the
link port. That requires a small `xband_link` RTL block driving
`port_tran_so/si/sck/sd` instead of tri-stating them (today they are idle — see
doc 12 §5). The byte stream it carries is exactly the
[`xband_modem_uart.sv`](../../docs/xband/rtl/xband_modem_uart.sv) `phy_tx`/`phy_rx`
FIFO contents. The UART bit rate is `LINK_BAUD` (default 115200; the historic
modem was 2400 baud, but the link is a short local wire so we can run faster to
keep added latency negligible).

## Build

Install [PlatformIO](https://platformio.org/), then:

```sh
cd firmware/esp32
pio run -e mode2_wifi          # Mode 2 firmware (default)
pio run -e mode1_linklink      # Mode 1 firmware
pio run -e mode2_wifi -t upload
```

Provide Wi-Fi credentials and the server host **without committing them** — pass
build flags or create `include/secrets.h` (git-ignored):

```sh
pio run -e mode2_wifi \
  --build-flag '-DWIFI_SSID="my-ssid"' \
  --build-flag '-DWIFI_PASS="my-pass"' \
  --build-flag '-DXBAND_SERVER_HOST="192.168.1.10"'
```

Defaults and pin assignments live in [`include/config.h`](include/config.h).

## Test (host, no hardware)

The `Bridge` logic is verified on a normal PC:

```sh
cd firmware/esp32/test
c++ -std=c++11 -I../include test_bridge.cpp -o /tmp/test_bridge && /tmp/test_bridge
# -> ALL BRIDGE TESTS PASSED
```

## Latency note

In-match XBAND traffic tolerates only ~35–40 ms of **stable** round-trip latency
(doc 01); jitter trips the in-game resync. The bridge moves small chunks per pump
and sets `TCP_NODELAY`; Mode 1 (local) is best for live versus, Mode 2 is fine
for menus/mail and works for matches on a low-latency LAN.
