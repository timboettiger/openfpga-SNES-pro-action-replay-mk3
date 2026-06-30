# XBAND reference RTL skeleton

These SystemVerilog files are a **reference skeleton** for representing the XBAND
cartridge add-on as RTL. They are described in
[../11-rtl-architecture.md](../11-rtl-architecture.md) and use the register map
from [../07-fred-register-map.md](../07-fred-register-map.md).

## Status: specification-in-HDL, behavioural model (NOT a verified core)

- Ports, parameters, register decode, reset values, memory blocks and the
  BIOS/SRAM load+save interfaces are **filled in** and follow the conventions
  this repo already uses for the MK3 add-on (`rtl/chip/mk3/…`).
- The behavioural core blocks are **implemented** as a model of the documented
  register behaviour (they elaborate, lint clean under Verilator, and pass a
  self-checking testbench for gating / patch redirect / modem pacing):
  - `xband_mapper.sv` — gates BIOS vs. pass-through game vs. SRAM-redirect on the
    FRED `kHereAssert` / `kRomHi` bits and the patch-engine redirect. Now decodes
    the BIOS as **HiROM** (confirmed against the verified 1 MB dump, see
    [../13-rom-memory-map.md](../13-rom-memory-map.md)) and gates the safe-ROM hole.
  - `xband_fred_patch.sv` — the FRED patch-vector compare/redirect datapath
    (range→translation remap, zero-page remap, per-vector enables, safe-RAM
    bounds) including the **per-vector table walk** that fetches each vector's
    redirect target from SRAM (1-cycle read-latency aware FSM).
  - `xband_modem_uart.sv` — the modem bridge: Tx/Rx FIFOs paced both ways to the
    video-locked bit clock. The Rockwell analog data-pump is intentionally out of
    scope; the line side is a tunnel to an external bridge, e.g. an ESP32, see
    [../12-link-cable-esp32.md](../12-link-cable-esp32.md).
- Still **open**: the exact retail SNES FRED register window location and the
  safe-ROM interaction still need validation against a real game patch on
  hardware. The HiROM decode and per-vector table walk are now modelled against
  the verified BIOS dump.

## Building / running the testbench

`xband_tb.sv` is a self-checking testbench (gating, HiROM decode, safe-ROM hole,
zero-page / trans-address remap, per-vector table walk, modem pacing). Build,
lint and run everything with:

```sh
./run-tb.sh          # lint + build + run, then clean up obj_dir/
./run-tb.sh --keep   # keep obj_dir/ for inspection
```

It prints `ALL TESTS PASSED` on success. Verilator build artifacts (`obj_dir/`)
are git-ignored.

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
| `xband_mapper.sv`         | SNES cartridge-address decode → BIOS / game / SRAM / regs (FRED-gated) |
| `xband_fred_regs.sv`      | FRED register file (control/kill/patch/LED/modem status)  |
| `xband_fred_patch.sv`     | FRED patch engine (11 vectors + remaps) — **implemented** |
| `xband_sram.sv`           | 64 KB battery SRAM, dual-port (SNES + save channel)      |
| `xband_modem_timing.sv`   | Video-locked VCnt/VSync counters + modem bit clock        |
| `xband_modem_uart.sv`     | Tx/Rx FIFO modem bridge, paced to the bit clock — **implemented** |
| `xband_tb.sv`             | Self-checking testbench (run via `run-tb.sh`)            |
| `run-tb.sh`               | Lint + build + run the testbench, then clean up          |
