#!/usr/bin/env bash
# Mac mini role machine side: whisper.cpp transcription (Metal backend), LLM
# endpoint (lens judging), locitorium stub (grounding omitted, see
# documents/decisions/0002-omit-nominatim-grounding.md), and detempus
# (series/anomaly detection). This machine does not touch the RTL-SDR --
# that's the RPi 4B's job (see setup-rpi.sh). It DOES run whisper.cpp, moved
# here from the RPi after real-hardware benchmarks showed the RPi too slow
# and thermally constrained (documents/decisions/0010-whisper-model-benchmark.md,
# documents/decisions/0011-transcription-moves-to-macmini-role.md).
set -euo pipefail

echo "== kikimimi: Mac mini setup =="

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install it first: https://brew.sh" >&2
  exit 1
fi

brew install ffmpeg jq curl uv git cmake rsync

echo
echo "-- whisper.cpp (Metal backend) --"
# On this machine, NOT the RPi -- see the header comment above. Real-hardware
# benchmarks (ADR 0011): small ~0.04x realtime, medium ~0.15x realtime with
# Metal, both far faster and more accurate than anything usable on the RPi.
WHISPER_DIR="${WHISPER_DIR:-$HOME/whisper.cpp}"
if [ -d "$WHISPER_DIR" ]; then
  echo "Found existing checkout at $WHISPER_DIR, leaving it as-is."
else
  git clone https://github.com/ggml-org/whisper.cpp "$WHISPER_DIR"
fi
echo "Build it (Metal framework found / Including METAL backend should appear"
echo "in the cmake output):"
echo "  cmake -B $WHISPER_DIR/build -S $WHISPER_DIR -DCMAKE_BUILD_TYPE=Release"
echo "  cmake --build $WHISPER_DIR/build --config Release -j"
echo
echo "If the build fails with a broken-CLT-style error (headers not found,"
echo "or a malformed .tbd link error from an unrelated newer SDK), see"
echo "documents/decisions/0011-transcription-moves-to-macmini-role.md for the"
echo "diagnosis and workaround (an explicit -DCMAKE_OSX_SYSROOT=... pin)."
echo
echo "Then fetch a model (medium is the current first candidate -- see ADR"
echo "0011; small is the lighter fallback):"
echo "  bash $WHISPER_DIR/models/download-ggml-model.sh medium"
echo
echo "Start the server by hand once you've picked a model:"
echo "  $WHISPER_DIR/build/bin/whisper-server -m $WHISPER_DIR/models/ggml-medium.bin \\"
echo "    --host 127.0.0.1 --port 30180"

echo
echo "-- OpenSpeechMap CLI --"
OSM_DIR="${OSM_DIR:-$HOME/OpenSpeechMap}"
if [ -d "$OSM_DIR" ]; then
  echo "Found existing checkout at $OSM_DIR, leaving it as-is."
else
  git clone https://github.com/yuiseki/OpenSpeechMap "$OSM_DIR"
fi
(cd "$OSM_DIR" && uv venv && uv pip install -e .)
uv pip install --python "$OSM_DIR/.venv/bin/python" \
  'detempus[all] @ git+https://github.com/yuiseki/detempus'

echo
echo "-- aiq (the fork with 'extract') --"
AIQ_DIR="$OSM_DIR/.tools/aiq"
mkdir -p "$OSM_DIR/.tools"
if [ -d "$AIQ_DIR" ]; then
  echo "Found existing checkout at $AIQ_DIR, leaving it as-is."
else
  git clone https://github.com/yuiseki/aiq "$AIQ_DIR"
fi

echo
echo "-- locitorium stub (grounding omitted on purpose) --"
BIN_DIR="/usr/local/bin"
STUB_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/locitorium-stub.sh"
if [ -w "$BIN_DIR" ] || sudo -n true 2>/dev/null; then
  sudo install -m 755 "$STUB_SRC" "$BIN_DIR/locitorium"
  echo "Installed stub as $BIN_DIR/locitorium (real locitorium/Nominatim not needed)."
else
  echo "Could not write to $BIN_DIR. Install the stub yourself:"
  echo "  sudo install -m 755 $STUB_SRC $BIN_DIR/locitorium"
fi

cat <<'EOF'

== Not done by this script (human steps) ==
- Fetch and quantize an LLM model, then start an OpenAI-compatible endpoint,
  e.g. via llama.cpp's llama-server:
    llama-server -m model.gguf --host 0.0.0.0 --port 8080
  Confirm with: curl -s "$LLM_URL/models"
- Point `speechmap lens` at this endpoint and at lenses/tokachi-lens, but only
  after a human has reviewed lenses/tokachi-lens/README.md's review checklist
  (CLAUDE.md 4節 -- lens content is not this script's call).
- Segments arrive from the RPi 4B via `just sync-segments`
  (scripts/sync-segments.sh: rsync pull + `speechmap transcribe
  --skip-newest`, decided in documents/decisions/0012-rsync-pull-over-tmpfs.md).
  Run it once by hand to confirm it works end-to-end before registering it as
  a recurring cron/launchd job -- that recurring registration is a human step,
  not something this script or a later Claude Code session should do on its
  own (see that ADR's "実装" section).

Run `speechmap check` to confirm what's still missing before running a pass.
EOF
