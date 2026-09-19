#!/usr/bin/env bash
# Mac mini role machine side: pull recorded segments from the RPi's tmpfs
# directory, then transcribe whatever is new.
#
# Meant to be run on a timer (cron/launchd) on the machine that runs
# `speechmap transcribe` -- see documents/decisions/0011-transcription-moves-to-macmini-role.md
# and documents/decisions/0012-rsync-pull-over-tmpfs.md for why this is a
# pull (not push) over plain rsync (not CIFS), and why the RPi's audio dir is
# tmpfs (never touches its SD card).
#
# Deliberately has no delete/cleanup logic of its own: the RPi's own
# `speechmap record --retention-hours/--max-gb` sweep is what bounds disk
# (RAM) usage there. This script only copies forward and transcribes.
set -euo pipefail

: "${KIKIMIMI_RPI_HOST:?set in .env}"
: "${KIKIMIMI_RPI_AUDIO_DIR:?set in .env}"
KIKIMIMI_RPI_USER="${KIKIMIMI_RPI_USER:-pi}"
# mDNS needs the .local suffix to resolve; .env.example documents the host
# without it, so add it back (idempotently -- fine if it's already there).
KIKIMIMI_RPI_HOST="${KIKIMIMI_RPI_HOST%.local}.local"
LOCAL_AUDIO_DIR="${KIKIMIMI_LOCAL_AUDIO_DIR:-$HOME/kikimimi-audio}"
TRANSCRIPT_DIR="${KIKIMIMI_TRANSCRIPT_DIR:-$HOME/kikimimi-transcripts}"
WHISPER_URL="${KIKIMIMI_WHISPER_URL:-http://127.0.0.1:30180/inference}"
LANGUAGE="${KIKIMIMI_LANGUAGE:-ja}"
OSM_DIR="${OSM_DIR:-$HOME/OpenSpeechMap}"
LOCK_DIR="${TMPDIR:-/tmp}/kikimimi-sync-segments.lock"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# mkdir is atomic on POSIX filesystems and needs no extra tool (unlike
# flock(1), which macOS does not ship).
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "another sync-segments.sh is already running, skipping this tick"
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

mkdir -p "$LOCAL_AUDIO_DIR" "$TRANSCRIPT_DIR"

log "rsync pull from ${KIKIMIMI_RPI_USER}@${KIKIMIMI_RPI_HOST}:${KIKIMIMI_RPI_AUDIO_DIR}/"
rsync -a --timeout=30 \
  "${KIKIMIMI_RPI_USER}@${KIKIMIMI_RPI_HOST}:${KIKIMIMI_RPI_AUDIO_DIR}/" \
  "$LOCAL_AUDIO_DIR/"

log "transcribing new segments (--skip-newest: record.py may still be writing the latest one)"
cd "$OSM_DIR"
uv run speechmap transcribe "$LOCAL_AUDIO_DIR" \
  --out "$TRANSCRIPT_DIR" \
  --skip-newest \
  --language "$LANGUAGE" \
  --whisper-url "$WHISPER_URL"

log "done"
