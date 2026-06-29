# 12 — Link Cable / ESP32-over-Wi-Fi: Feasibility

**Question (part 3 of the task):** *can we reach "the link cable" from our core
to attach an ESP32 with Wi-Fi, so the modem can be tunnelled?*

**Short answer:** There is **no SNES "link cable"** in the Game Boy sense, and
the Analogue Pocket has no SNES serial port. But the Pocket **does** expose a
4-pin **Link Port** to the FPGA fabric (`port_tran_si/so/sck/sd`), and in this
core it is currently **idle / tri-stated**. The FPGA can drive those pins, so an
ESP32 wired to the Pocket Link Port is a viable transport for tunnelling the
XBAND modem byte stream. This is the recommended path. Details below.

## 1. What "link cable" means on SNES vs. Pocket

- The SNES itself had no standard link cable. XBAND networking went over the
  **phone line via its on-board Rockwell modem**, not a console-to-console
  cable. So "tap the link cable" doesn't map onto real SNES hardware.
- The right integration point is therefore the **modem byte interface** inside
  FRED (`kTxBuff`/`kRxBuff`, see [07-fred-register-map.md](07-fred-register-map.md)),
  abstracted in RTL as a byte FIFO (`xband_modem_uart.sv`, see
  [11-rtl-architecture.md](11-rtl-architecture.md)). Tunnel *that* over Wi-Fi.

## 2. What the Pocket actually exposes (verified in this repo)

The Analogue Pocket has a physical **Link Port** (top-edge connector) that
openFPGA surfaces to the core. In `platform/pocket/apf_top.v` the four bidir
pins + their direction controls are top-level core I/O:

```verilog
inout  wire port_tran_si;   output wire port_tran_si_dir;   // serial in
inout  wire port_tran_so;   output wire port_tran_so_dir;   // serial out
inout  wire port_tran_sck;  output wire port_tran_sck_dir;  // clock
inout  wire port_tran_sd;   output wire port_tran_sd_dir;   // data
```

In **this** core (`target/pocket/core_top.sv`) they are currently parked:

```verilog
assign port_tran_so      = 1'bz;  assign port_tran_so_dir  = 1'b0;  // SO output only
assign port_tran_si      = 1'bz;  assign port_tran_si_dir  = 1'b0;  // SI input only
assign port_tran_sck     = 1'bz;  assign port_tran_sck_dir = 1'b0;  // clock dir can change
assign port_tran_sd      = 1'bz;  assign port_tran_sd_dir  = 1'b0;  // SD unused
```

**Conclusion:** the link port is present and **free** — nothing in the SNES core
uses it today. The core *can* access it; enabling a tunnel is a matter of
driving these pins instead of tri-stating them.

> The `cart_tran_*` banks (also in `core_top.sv`) are the Pocket **cartridge
> adapter** pins. They are held at safe defaults and are *not* a good target —
> they belong to the analog cartridge interface, not a general serial link.

## 3. Recommended architecture (ESP32 as a "modem replacement")

```
   SNES game ──cart bus── FRED(modem FIFO) ──┐
                                              │  (in FPGA)
   xband_modem_uart.sv  ── bit-bang/SPI ──► port_tran_{so,si,sck,sd}
                                              │  (Pocket Link Port pins)
                                              ▼
                                          ESP32  ── Wi-Fi/TCP ──► XBAND server
```

- The ESP32 plays the role the **phone line + remote modem** used to play: it
  carries the XBAND byte stream to a (modern) server or to a peer.
- Use the link port as **SPI** (sck + so + si, with sd as a ready/attention
  strobe) or as an async UART bit-banged on so/si. SPI is the cleaner fit because
  `port_tran_sck_dir` is explicitly allowed to change direction.
- The FPGA side is small: a shift register + the existing Tx/Rx FIFOs. No change
  to the SNES-visible behaviour — to the game, bytes still arrive/depart through
  FRED's modem registers.

## 4. The timing caveat (this is the real risk, not the wiring)

XBAND in-game networking tolerates only **~35–40 ms of *stable* round-trip
latency** ([01-overview.md](01-overview.md)); jitter trips the in-game resync
code. An ESP32-over-Wi-Fi/TCP bridge can easily exceed that under congestion.
Mitigations:

- Prefer **UDP** with a thin reliability layer over raw TCP for the in-game phase.
- Keep the ESP32 link-port clock fast and the framing tight; buffer minimally.
- For the *menu/mail/handshake* phases latency is a non-issue — only the live
  match phase is sensitive.
- Consider doing handshake/CRC framing ([04](04-network-protocol.md)) on the
  ESP32 so the FPGA only ships raw modem bytes.

## 5. What it would take to enable it here (not done in this PR)

1. Add an `xband_link` block that drives `port_tran_*` (SPI/UART) and bridges to
   the `xband_modem_uart.sv` FIFOs.
2. Stop tri-stating the four pins in `core_top.sv`; drive `*_dir` per role.
3. Define a tiny host protocol (ESP32 firmware) framing modem bytes + control
   (off-hook, carrier, hang-up) — these map to FRED control/kill bits.
4. (Optional) expose a Pocket core-option to pick "internal modem model" vs.
   "ESP32 link-port tunnel".

None of these touch the SNES emulation itself; they are additive and isolated to
the link-port pins, which today are idle. So: **yes, the core can reach a usable
link for an ESP32** — via the Pocket Link Port, tunnelling FRED's modem FIFO —
with latency being the design constraint to engineer around.
