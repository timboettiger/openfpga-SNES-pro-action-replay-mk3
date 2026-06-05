#!/usr/bin/env bash
# Convert a 521x165 PNG to the Pocket platform image pkg/Platforms/_images/snes.bin.
# Rotated 90 deg CCW, headerless, 16-bit big-endian, brightness in the upper byte
# (inverted: white = 0x00), lower byte 0x00, greyscale. Requires Pillow.
# Note: "snes" is a shared platform; replacing snes.bin re-skins it for every SNES core.
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/art/snes.png}"
OUT="$ROOT/pkg/Platforms/_images/snes.bin"
[ -f "$SRC" ] || { echo "source PNG not found: $SRC"; exit 1; }

python3 - "$SRC" "$OUT" <<'PY'
import sys
from PIL import Image
src, out = sys.argv[1:3]
W, H = 521, 165
img = Image.open(src).convert("L")
if img.size != (W, H):
    img = img.resize((W, H), Image.LANCZOS)
data = img.transpose(Image.Transpose.ROTATE_90).tobytes()
buf = bytearray(len(data) * 2)
for i, v in enumerate(data):
    buf[2 * i] = 255 - v
open(out, "wb").write(buf)
print(f"wrote {out} ({len(buf)} bytes)")
PY
