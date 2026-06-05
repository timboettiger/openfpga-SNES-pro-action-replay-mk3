#!/usr/bin/env bash
# Stage the installable Pocket core under release/ and zip it.
# Requires a built bitstream at projects/output_files/snes_pocket.rbf.
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_RBF="${SRC_RBF:-$ROOT/projects/output_files/snes_pocket.rbf}"
SRC_CORE="$(ls -d "$ROOT"/pkg/Cores/*/ | head -1)"
STAGE="$ROOT/release/stage"
OUT="$ROOT/release"

# Card folder = {author}.{shortname} from core.json (the Pocket resolves the path from it).
CORE_DST="$(python3 - "$SRC_CORE/core.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["core"]["metadata"]
print(f"{m['author']}.{m['shortname']}")
PY
)"
VERSION="$(python3 - "$SRC_CORE/core.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["core"]["metadata"]["version"])
PY
)"

[ -f "$SRC_RBF" ] || { echo "bitstream not found: $SRC_RBF (compile first)"; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/Cores/$CORE_DST" "$STAGE/Platforms/_images" "$STAGE/Assets/snes/$CORE_DST"

cp "$SRC_CORE"*.json "$SRC_CORE"info.txt "$SRC_CORE"loader.bin "$SRC_CORE"icon.bin \
   "$STAGE/Cores/$CORE_DST/"

# Bit-reverse the RBF: the Cyclone V loads serial-bit-first, Quartus emits parallel-bit-first.
python3 - "$SRC_RBF" "$STAGE/Cores/$CORE_DST/bitstream.rbf_r" <<'PY'
import sys
data = bytearray(open(sys.argv[1], "rb").read())
for i, b in enumerate(data):
    data[i] = int(f"{b:08b}"[::-1], 2)
open(sys.argv[2], "wb").write(data)
PY

cp "$ROOT/pkg/Platforms/snes.json" "$STAGE/Platforms/"
[ -f "$ROOT/pkg/Platforms/_images/snes.bin" ] && \
  cp "$ROOT/pkg/Platforms/_images/snes.bin" "$STAGE/Platforms/_images/"

# The BIOS is proprietary Datel firmware and is never shipped; the user supplies it.
cat > "$STAGE/Assets/snes/$CORE_DST/PLACE_BIOS_HERE.txt" <<EOF
Place a verified 128 KB Pro Action Replay MK3 BIOS dump in this folder as:
  snes-pro-action-replay-mk3.bin
EOF

mkdir -p "$OUT"
ZIP="$OUT/$(basename "$SRC_CORE")_${VERSION}.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -rq "$ZIP" . )
echo "release: $ZIP"
