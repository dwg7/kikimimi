#!/usr/bin/env bash
# RPi 4B side: RTL-SDR capture + whisper.cpp transcription only.
# This machine does not run the lens (LLM) or series (detempus) stages, and it
# never serves or displays anything itself — see
# documents/decisions/0003-hardware-split-rpi-macmini.md and
# documents/decisions/0004-single-output-path-github-pages.md for why.
#
# This script installs what `speechmap record --source sdr` and
# `speechmap transcribe` need. It does not connect the dongle or start a
# capture — that's a physical/operational step for a human (CLAUDE.md 4節).
set -euo pipefail

echo "== kikimimi: RPi 4B setup =="

if ! command -v apt >/dev/null 2>&1; then
  echo "This script targets Raspberry Pi OS (apt-based). Aborting." >&2
  exit 1
fi

sudo apt update
sudo apt install -y ffmpeg jq curl rtl-sdr git build-essential cmake

echo
echo "-- rtl-sdr check --"
if command -v rtl_test >/dev/null 2>&1; then
  echo "rtl_test found. Plug in the dongle and run 'rtl_test' by hand to confirm"
  echo "it is seen (this script does not touch hardware)."
else
  echo "rtl_test not found after install -- check the rtl-sdr package." >&2
fi

echo
echo "-- whisper.cpp --"
WHISPER_DIR="${WHISPER_DIR:-$HOME/whisper.cpp}"
if [ -d "$WHISPER_DIR" ]; then
  echo "Found existing checkout at $WHISPER_DIR, leaving it as-is."
else
  git clone https://github.com/ggml-org/whisper.cpp "$WHISPER_DIR"
fi

echo "Build it yourself once ARM NEON flags are confirmed for this board:"
echo "  cmake -B $WHISPER_DIR/build -S $WHISPER_DIR"
echo "  cmake --build $WHISPER_DIR/build --config Release -j"
echo
echo "Then fetch a small model (tiny or base -- see CLAUDE.md 2節 on why"
echo "these are the ones expected to run faster than real time on this board):"
echo "  bash $WHISPER_DIR/models/download-ggml-model.sh base"
echo
echo "Start the server by hand once you've picked a model, e.g.:"
echo "  $WHISPER_DIR/build/bin/whisper-server -m $WHISPER_DIR/models/ggml-base.bin \\"
echo "    --host 0.0.0.0 --port 8080"

echo
echo "-- OpenSpeechMap CLI --"
OSM_DIR="${OSM_DIR:-$HOME/OpenSpeechMap}"
if [ -d "$OSM_DIR" ]; then
  echo "Found existing checkout at $OSM_DIR, leaving it as-is."
else
  git clone https://github.com/yuiseki/OpenSpeechMap "$OSM_DIR"
fi
echo "Install it with uv (see $OSM_DIR/docs/PREREQUISITES.md):"
echo "  cd $OSM_DIR && uv venv && uv pip install -e ."

cat <<'EOF'

== Not done by this script (human steps) ==
- Physically connect the RTL-SDR Blog V4 R828D dongle
- Confirm reception with rtl_test / rtl_power on the intended frequency
- Build whisper.cpp and pick tiny vs base after a real accuracy/speed check
- Point `speechmap transcribe --whisper-url` at the whisper-server above, and
  wire the output to wherever the Mac mini reads from (see setup-macmini.sh)

Run `speechmap check` after installing the Python package to confirm what's
still missing.
EOF
