#!/usr/bin/env bash
# Mac mini role machine side: pull recorded segments from the RPi's tmpfs
# directory, transcribe whatever is new, run the tokachi-lens over the
# transcripts, and refresh the Open MCT dashboard's live data.
#
# Meant to be run on a timer (cron/launchd) on the machine that runs
# `speechmap transcribe` -- see documents/decisions/0011-transcription-moves-to-macmini-role.md
# and documents/decisions/0012-rsync-pull-over-tmpfs.md for why this is a
# pull (not push) over plain rsync (not CIFS), and why the RPi's audio dir is
# tmpfs (never touches its SD card). The lens/series/Open MCT steps were
# added in documents/decisions/0015-llm-endpoint-and-real-data-pipeline.md,
# after validating each stage by hand.
#
# Deliberately has no delete/cleanup logic of its own: the RPi's own
# `speechmap record --retention-hours/--max-gb` sweep is what bounds disk
# (RAM) usage there. This script only copies forward and transcribes.
set -euo pipefail

# launchd/cron run with a minimal, non-login environment: no .zshrc, no
# Homebrew on PATH (the same gotcha as the non-interactive-SSH one hit
# during setup -- see documents/decisions/0011-transcription-moves-to-macmini-role.md).
# Make this script self-sufficient regardless of who invokes it.
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

# Resolved once, before anything below `cd`s elsewhere (into $OSM_DIR) --
# BASH_SOURCE[0] is only reliably resolvable relative to the original cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# `just` normally loads .env for us (set dotenv-load), but launchd/cron call
# this script directly, so load it here too if it hasn't been already.
KIKIMIMI_ENV_FILE="${KIKIMIMI_ENV_FILE:-$SCRIPT_DIR/../.env}"
if [ -z "${KIKIMIMI_RPI_HOST:-}" ] && [ -f "$KIKIMIMI_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$KIKIMIMI_ENV_FILE"
  set +a
fi

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
LLM_URL="${KIKIMIMI_LLM_URL:-http://127.0.0.1:11434/v1}"
LLM_MODEL="${KIKIMIMI_LLM_MODEL:-qwen2.5:14b}"
LENS_DIR="${KIKIMIMI_LENS_DIR:-$SCRIPT_DIR/../lenses/tokachi-lens}"
LENS_OUT="${KIKIMIMI_LENS_OUT:-$HOME/kikimimi-lens-output}"
OPENMCT_DATA_DIR="${KIKIMIMI_OPENMCT_DATA_DIR:-$SCRIPT_DIR/../docs/data}"
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

log "quarantining any corrupted segments (a stray 0-byte .ts breaks the whole transcribe batch -- see documents/decisions/0012-rsync-pull-over-tmpfs.md)"
QUARANTINE_DIR="${KIKIMIMI_AUDIO_QUARANTINE_DIR:-$HOME/kikimimi-audio-quarantine}"
mkdir -p "$QUARANTINE_DIR"
# Sort by name (chronological, per record.py's filename convention) and skip
# the newest file: it may legitimately still be growing. Built as a plain
# array via a read loop, not `mapfile` -- macOS ships bash 3.2 (pre-GPLv3),
# which doesn't have that builtin, unlike the RPi's bash.
_segments=()
while IFS= read -r _f; do
  _segments+=("$_f")
done < <(find "$LOCAL_AUDIO_DIR" -maxdepth 1 -name '*.ts' -type f | sort)
if [ "${#_segments[@]}" -gt 1 ]; then
  _last_index=$((${#_segments[@]} - 1))
  for _i in "${!_segments[@]}"; do
    if [ "$_i" -eq "$_last_index" ]; then
      continue
    fi
    _f="${_segments[$_i]}"
    if ! ffprobe -v error "$_f" -show_entries format=duration -of csv=p=0 >/dev/null 2>&1; then
      log "quarantining corrupted segment: $(basename "$_f")"
      mv "$_f" "$QUARANTINE_DIR/"
    fi
  done
fi

log "transcribing new segments (--skip-newest: record.py may still be writing the latest one)"
cd "$OSM_DIR"
uv run speechmap transcribe "$LOCAL_AUDIO_DIR" \
  --out "$TRANSCRIPT_DIR" \
  --skip-newest \
  --language "$LANGUAGE" \
  --whisper-url "$WHISPER_URL"

log "applying tokachi-lens (only new/unlabeled transcripts are sent to the LLM)"
# aiq only checks that this variable exists, not its value -- Ollama ignores it.
export OPENAI_API_KEY="${OPENAI_API_KEY:-ollama-local-no-key-needed}"
uv run speechmap lens "$TRANSCRIPT_DIR" \
  --lens "$LENS_DIR" \
  --out "$LENS_OUT" \
  --select ".is_tokachidake" \
  --model "$LLM_MODEL" \
  --llm-url "$LLM_URL"

log "refreshing Open MCT live data"
"$SCRIPT_DIR/lens-to-openmct.sh" "$LENS_OUT" "$OPENMCT_DATA_DIR"

log "refreshing health panel data"
"$SCRIPT_DIR/update-health.sh" || log "update-health.sh failed, continuing anyway"

log "done"
