#!/usr/bin/env bash
# Build + run the XBAND RTL self-checking testbench, then clean up artifacts.
#
# Requires Verilator (tested with 5.020).
#
#   ./run-tb.sh          # lint, build, run, then remove obj_dir/
#   ./run-tb.sh --keep   # leave obj_dir/ in place for inspection
set -euo pipefail
cd "$(dirname "$0")"

PKG=xband_pkg.sv
SRC=(
  "$PKG"
  xband_mapper.sv
  xband_fred_regs.sv
  xband_fred_patch.sv
  xband_sram.sv
  xband_modem_timing.sv
  xband_modem_uart.sv
)

LINT_WAIVERS=(-Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-WIDTHEXPAND)
TB_WAIVERS=("${LINT_WAIVERS[@]}" -Wno-UNUSEDSIGNAL -Wno-INITIALDLY \
            -Wno-PINCONNECTEMPTY -Wno-BLKSEQ)

echo "==> Lint (top: xband_top)"
verilator --lint-only "${LINT_WAIVERS[@]}" --top-module xband_top \
  "${SRC[@]}" xband_top.sv

echo "==> Build testbench"
verilator --binary --timing "${TB_WAIVERS[@]}" --top-module xband_tb \
  "${SRC[@]}" xband_tb.sv >/dev/null

echo "==> Run testbench"
./obj_dir/Vxband_tb

if [[ "${1:-}" != "--keep" ]]; then
  rm -rf obj_dir
fi
