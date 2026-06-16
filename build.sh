#!/usr/bin/env bash
# Build the openFPGA Pac-Man core: Quartus compile (Dockerised) -> reverse bitstream -> stage package.
# Mirrors the local SNES/NES Pocket build flow (raetro/quartus:21.1 + reverse_rbf.py).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA="$ROOT/src/fpga"
RBF="$FPGA/output_files/ap_core.rbf"
OUT="$ROOT/output/bitstream.rbf_r"
QUARTUS_IMAGE="raetro/quartus:21.1"   # Quartus Prime 21.1.1 Lite — same image the SNES/NES cores build with
CORE_DIR="$ROOT/dist/Cores/TheDiscordian.PacMan"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }

# Ensure the analogue-pocket-utils IP submodule is checked out (git clones only).
[ -d "$ROOT/.git" ] && git -C "$ROOT" submodule update --init --recursive

echo "=== [$(stamp)] Quartus compile (Docker: $QUARTUS_IMAGE) ==="
rm -f "$RBF"
docker run --rm -v "$ROOT":/build -w /build/src/fpga "$QUARTUS_IMAGE" \
    quartus_sh --flow compile ap_core

if [ ! -f "$RBF" ]; then
    echo "!!! No ap_core.rbf produced — compile failed (check fit/timing in output_files/)." >&2
    exit 1
fi

echo "--- fit summary ---"; cat "$FPGA/output_files/ap_core.fit.summary" 2>/dev/null || true
echo "--- timing summary ---"; cat "$FPGA/output_files/ap_core.sta.summary" 2>/dev/null || true

echo "=== [$(stamp)] reverse bitstream -> $OUT ==="
mkdir -p "$ROOT/output"
python3 "$ROOT/tools/reverse_rbf.py" "$RBF" "$OUT"

echo "=== [$(stamp)] stage SD package -> dist/Cores/TheDiscordian.PacMan ==="
mkdir -p "$CORE_DIR"
cp -f "$OUT" "$CORE_DIR/bitstream.rbf_r"
cp -f "$ROOT"/{core,data,video,audio,input,interact,variants}.json "$CORE_DIR/"
cp -f "$ROOT/dist/icon.bin" "$CORE_DIR/" 2>/dev/null || true

echo "=== [$(stamp)] DONE. Deploy dist/ to the Pocket SD (Cores/Platforms/Assets)."
