#!/usr/bin/env bash
# Run OpenSpeechMap's own ja-radio-disaster lens (no gate.txt -- every record
# goes to the LLM for an is_disaster judgment) over the accumulated
# transcripts, as an independent validation signal alongside tokachi-lens.
#
# Why this exists: tokachi-lens's gate.txt has kept every record out (0
# selected) since the pipeline went live, which is the expected state (no
# real Tokachidake-related broadcast content yet) but is hard to distinguish
# from "the LLM judgment step is silently broken". ja-radio-disaster has no
# keyword gate, so it should react to ordinary disaster-adjacent coverage
# (e.g. today's typhoon warnings) and prove the LLM step itself is alive.
# See documents/decisions/0018-parallel-validation-lens.md.
#
# Deliberately NOT wired into sync-segments.sh's 60s cadence: without a gate,
# every transcript record goes to the LLM, which is much more expensive than
# tokachi-lens's heavily-gated run. Runs on its own, longer-interval timer
# instead (scripts/install-disaster-lens-timer.sh).
#
# Deliberately writes outside docs/ (not docs/data/): this is an unreviewed
# validation signal, not something to publish. docs/ is the GitHub Pages
# publish root (documents/decisions/0006, 0016) and the project's standing
# rule is that a human reviews what actually gets pushed there
# (CLAUDE.md section 4, "公開する検出結果・抜粋の内容確認").
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

KIKIMIMI_ENV_FILE="${KIKIMIMI_ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env}"
if [ -z "${KIKIMIMI_LLM_URL:-}" ] && [ -f "$KIKIMIMI_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$KIKIMIMI_ENV_FILE"
  set +a
fi

TRANSCRIPT_DIR="${KIKIMIMI_TRANSCRIPT_DIR:-$HOME/kikimimi-transcripts}"
OSM_DIR="${OSM_DIR:-$HOME/OpenSpeechMap}"
LLM_URL="${KIKIMIMI_LLM_URL:-http://127.0.0.1:11434/v1}"
LLM_MODEL="${KIKIMIMI_LLM_MODEL:-qwen2.5:14b}"
DISASTER_LENS_DIR="${KIKIMIMI_DISASTER_LENS_DIR:-$OSM_DIR/lenses/ja-radio-disaster}"
DISASTER_LENS_OUT="${KIKIMIMI_DISASTER_LENS_OUT:-$HOME/kikimimi-disaster-lens-output}"
LOCK_DIR="${TMPDIR:-/tmp}/kikimimi-disaster-lens.lock"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "another run-disaster-lens.sh is already running, skipping this tick"
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

if [ ! -d "$DISASTER_LENS_DIR" ]; then
  log "error: lens not found at $DISASTER_LENS_DIR"
  exit 1
fi

log "applying ja-radio-disaster (no gate -- every new/unlabeled record goes to the LLM)"
# aiq only checks that this variable exists, not its value -- Ollama ignores it.
export OPENAI_API_KEY="${OPENAI_API_KEY:-ollama-local-no-key-needed}"
cd "$OSM_DIR"
uv run speechmap lens "$TRANSCRIPT_DIR" \
  --lens "$DISASTER_LENS_DIR" \
  --out "$DISASTER_LENS_OUT" \
  --select ".is_disaster" \
  --model "$LLM_MODEL" \
  --llm-url "$LLM_URL"

DISASTER_COUNT=$(jq -sc 'map(select(.is_disaster == true)) | length' "$DISASTER_LENS_OUT/labeled.jsonl")
log "done: $DISASTER_COUNT record(s) currently judged is_disaster=true (validation signal only, not published)"
