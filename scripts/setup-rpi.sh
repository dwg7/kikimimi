#!/usr/bin/env bash
# RPi 4B side: RTL-SDR capture only. It does NOT run whisper.cpp -- that
# moved to the Mac mini role machine after real-hardware benchmarks showed
# the RPi both too slow (small/medium models) and prone to thermal
# throttling even on tiny. See documents/decisions/0010-whisper-model-benchmark.md
# and documents/decisions/0011-transcription-moves-to-macmini-role.md.
# This machine does not run the lens (LLM) or series (detempus) stages either,
# and it never serves or displays anything itself — see
# documents/decisions/0003-hardware-split-rpi-macmini.md and
# documents/decisions/0004-single-output-path-github-pages.md for why.
#
# This script installs what `speechmap record --source sdr` needs, and sets
# up a tmpfs directory for it to record into so segments never touch the SD
# card (documents/decisions/0012-rsync-pull-over-tmpfs.md). It does not
# connect the dongle or start a capture — that's a physical/operational step
# for a human (CLAUDE.md 4節).
set -euo pipefail

echo "== kikimimi: RPi 4B setup =="

if ! command -v apt >/dev/null 2>&1; then
  echo "This script targets Raspberry Pi OS (apt-based). Aborting." >&2
  exit 1
fi

sudo apt update
sudo apt install -y ffmpeg jq curl rtl-sdr git

echo
echo "-- rtl-sdr check --"
if command -v rtl_test >/dev/null 2>&1; then
  echo "rtl_test found. Plug in the dongle and run 'rtl_test' by hand to confirm"
  echo "it is seen (this script does not touch hardware)."
else
  echo "rtl_test not found after install -- check the rtl-sdr package." >&2
fi

echo
echo "-- tmpfs recording directory --"
# speechmap record --out just needs a writable directory; pointing it at
# tmpfs means audio segments are never written to the SD card. Sized well
# above the realistic daily volume (~1GB/day at 60s segments -- see ADR
# 0012) while staying a small fraction of this board's RAM.
AUDIO_DIR="${KIKIMIMI_RPI_AUDIO_DIR:-/mnt/kikimimi-audio}"
TMPFS_SIZE="${KIKIMIMI_TMPFS_SIZE:-1G}"
sudo mkdir -p "$AUDIO_DIR"
if mountpoint -q "$AUDIO_DIR"; then
  echo "$AUDIO_DIR is already a mount point, leaving it as-is."
else
  FSTAB_LINE="tmpfs $AUDIO_DIR tmpfs rw,nosuid,nodev,size=${TMPFS_SIZE},uid=$(id -u),gid=$(id -g) 0 0"
  if grep -qF "$AUDIO_DIR" /etc/fstab 2>/dev/null; then
    echo "$AUDIO_DIR already has an /etc/fstab entry, leaving it as-is."
  else
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
    echo "added to /etc/fstab: $FSTAB_LINE"
  fi
  sudo mount "$AUDIO_DIR"
  echo "mounted tmpfs at $AUDIO_DIR ($TMPFS_SIZE, owned by $(id -un))"
fi
echo "Point speechmap record at it, with a retention window that fits in"
echo "$TMPFS_SIZE, e.g.:"
echo "  speechmap record --out $AUDIO_DIR --retention-hours 12 --max-gb 0.8 ..."

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
- Start `speechmap record` pointed at the tmpfs directory above. Transcription
  and everything downstream happens on the Mac mini role machine, which pulls
  segments via `just sync-segments` (scripts/sync-segments.sh) -- see
  documents/decisions/0011-transcription-moves-to-macmini-role.md and
  documents/decisions/0012-rsync-pull-over-tmpfs.md

Run `speechmap check` after installing the Python package to confirm what's
still missing.
EOF
