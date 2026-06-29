# XBAND reference RTL skeleton

These SystemVerilog files are a **reference skeleton** for representing the XBAND
cartridge add-on as RTL. They are described in
[../11-rtl-architecture.md](../11-rtl-architecture.md) and use the register map
from [../07-fred-register-map.md](../07-fred-register-map.md).

## Status: specification-in-HDL, NOT a finished core

- Ports, parameters, register decode, reset values, memory blocks and the
  BIOS/SRAM load+save interfaces are **filled in** and follow the conventions
  this repo already uses for the MK3 add-on (`rtl/chip/mk3/…`).
- Two behavioural blocks are deliberately **stubbed** with `TODO`s because they
  still require reverse-engineering work and external hardware modelling:
  - `xband_fred_patch.sv` — the FRED patch-vector compare/redirect datapath.
  - `xband_modem_uart.sv` — the modem PHY (the FIFO/byte interface is provided;
    the Rockwell data-pump / line modeling is out of scope and is meant to be a
    tunnel to an external bridge, e.g. an ESP32, see
    [../12-link-cable-esp32.md](../12-link-cable-esp32.md)).

## NOT wired into the Pocket build

These files are intentionally **not** added to `gateware.json` or any `*.qip`
list, so they do not affect this core's bitstream. They exist to be lifted into
a dedicated XBAND project (or an `fxpakpro`-style extension). Treat them as a
starting point to validate against a real BIOS dump and real hardware.

## Files

| File                      | Role                                                     |
| ------------------------- | -------------------------------------------------------- |
| `xband_pkg.sv`            | Register offsets + bit masks + parameters (from doc 07)  |
| `xband_top.sv`            | Top-level wiring of the sub-blocks                       |
| `xband_mapper.sv`         | SNES cartridge-address decode → BIOS / game / SRAM / regs |
| `xband_fred_regs.sv`      | FRED register file (control/kill/patch/LED/modem status)  |
| `xband_fred_patch.sv`     | FRED patch engine (11 vectors + remaps) — **stub**       |
| `xband_sram.sv`           | 64 KB battery SRAM, dual-port (SNES + save channel)      |
| `xband_modem_timing.sv`   | Video-locked VCnt/VSync counters + modem bit clock        |
| `xband_modem_uart.sv`     | 16550-style byte interface + Tx/Rx FIFOs — PHY **stub**  |
