#!/usr/bin/env bash
# Convert art/icon.png (36x36 greyscale) to the core's icon.bin, or back with --decode.
# Pocket core icon: rotated 90 deg CCW, headerless, 16-bit big-endian, brightness in
# the upper byte (white = 0xFF), lower byte 0x00. Requires Pillow.
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ART="$ROOT/art/icon.png"
BIN="$(ls -d "$ROOT"/pkg/Cores/*/ | head -1)icon.bin"

MODE=encode; IN="$ART"; OUT="$BIN"
case "${1:-}" in
  --decode) MODE=decode; IN="$BIN"; OUT="$ART" ;;
  "") ;;
  *) IN="$1" ;;
esac

python3 - "$MODE" "$IN" "$OUT" <<'PY'
import sys
from PIL import Image
mode, inp, out = sys.argv[1:4]
N = 36
if mode == "encode":
    img = Image.open(inp).convert("L")
    if img.size != (N, N):
        img = img.resize((N, N), Image.LANCZOS)
    src = img.transpose(Image.Transpose.ROTATE_90).tobytes()
    buf = bytearray(len(src) * 2)
    for i, v in enumerate(src):
        buf[2 * i] = v
    open(out, "wb").write(buf)
else:
    data = open(inp, "rb").read()
    gray = bytes(data[i] for i in range(0, len(data), 2))
    Image.frombytes("L", (N, N), gray).transpose(Image.Transpose.ROTATE_270).save(out)
print(f"{mode}: {out}")
PY
