#!/usr/bin/env bash
# Mac mini side: LLM endpoint (lens judging), locitorium stub (grounding
# omitted, see documents/decisions/0002-omit-nominatim-grounding.md), and detempus
# (series/anomaly detection). This machine does not touch the RTL-SDR or
# whisper.cpp -- that's the RPi 4B's job (see setup-rpi.sh and
# documents/decisions/0003-hardware-split-rpi-macmini.md).
set -euo pipefail

echo "== kikimimi: Mac mini setup =="

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install it first: https://brew.sh" >&2
  exit 1
fi

brew install ffmpeg jq curl uv git

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
- Receive transcripts from the RPi 4B (decide the transport: rsync, a shared
  directory, scp on a timer -- not decided yet, see notes/observations.md).

Run `speechmap check` to confirm what's still missing before running a pass.
EOF
