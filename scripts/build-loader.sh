#!/usr/bin/env bash
# Assemble support/mk3_loader.asm into the core's loader.bin using bass (chip32).
# bass is built from source on first run and cached under $TOOLS.
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$(ls -d "$ROOT"/pkg/Cores/*/ | head -1)"
TOOLS="${TOOLS:-/tmp/bass-chip32}"

if [ ! -x "$TOOLS/bass" ]; then
    rm -rf "$TOOLS" /tmp/bass-src /tmp/bass-arch
    git clone --depth=1 -b devel https://github.com/ARM9/bass.git /tmp/bass-src 2>/dev/null \
        || git clone --depth=1 https://github.com/ARM9/bass.git /tmp/bass-src
    ( cd /tmp/bass-src/bass && make )
    git clone --depth=1 https://github.com/open-fpga/bass-chip32.git /tmp/bass-arch
    mkdir -p "$TOOLS"
    cp /tmp/bass-src/bass/out/bass "$TOOLS/bass"
    cp -r /tmp/bass-arch/architectures "$TOOLS/"
fi

cp "$ROOT/support/mk3_loader.asm" "$ROOT/support/util.asm" \
   "$ROOT/support/check_header.asm" "$TOOLS/"
( cd "$TOOLS" && ./bass mk3_loader.asm )
cp "$TOOLS/loader.bin" "${CORE_DIR}loader.bin"
echo "loader.bin: $(wc -c < "${CORE_DIR}loader.bin") bytes"
