#!/usr/bin/env bash
# Convert speechmap lens's labeled.jsonl output into openmct/data/live.json,
# the format openmct/plugins/kikimimi-provider.js fetches (DATA_URL).
#
# Run on the Mac mini role machine, after `speechmap lens` has been run
# against the accumulated transcripts. Does not run `speechmap lens` itself
# (that stays a separate, explicit step -- see Justfile).
#
# Handles the "nothing detected yet" case explicitly: `speechmap series`
# errors out when its --select expression matches zero records ("Nothing to
# count"), which is expected to be the normal state for a rare-event volcano
# monitor, so this script produces series: [] itself in that case rather than
# treating it as a failure.
set -euo pipefail

LENS_OUT="${1:-$HOME/kikimimi-lens-output}"
OPENMCT_DATA_DIR="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../openmct/data" && pwd)}"
LIVE_JSON="$OPENMCT_DATA_DIR/live.json"

LABELED="$LENS_OUT/labeled.jsonl"
if [ ! -f "$LABELED" ]; then
  echo "error: $LABELED not found. Run speechmap lens first." >&2
  exit 1
fi

EVENTS=$(jq -sc 'map(select(.is_tokachidake == true))' "$LABELED")
EVENT_COUNT=$(echo "$EVENTS" | jq 'length')

echo "kikimimi: $EVENT_COUNT tokachidake-related record(s) in $LABELED"

if [ "$EVENT_COUNT" -eq 0 ]; then
  SERIES='[]'
else
  export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
  OSM_DIR="${OSM_DIR:-$HOME/OpenSpeechMap}"
  SERIES_OUT="$LENS_OUT/series-output"
  rm -rf "$SERIES_OUT"
  (cd "$OSM_DIR" && uv run speechmap series "$LABELED" \
    --out "$SERIES_OUT" \
    --select ".is_tokachidake" \
    --key-field "" \
    --bucket hour)
  # speechmap series' own format is {series: [{key, t: [...], value: [...], ...}]}
  # (with baseline/anomaly detail we don't surface yet); flatten the first
  # (and, with --key-field "", only) series into the simple {t, count} pairs
  # the dashboard's SVG plot expects.
  SERIES=$(jq -c '.series[0] | [.t, .value] | transpose | map({t: .[0], count: .[1]})' \
    "$SERIES_OUT/series.json")
fi

GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n --argjson series "$SERIES" --argjson events "$EVENTS" \
  --arg generated_at "$GENERATED_AT" \
  '{generated_at: $generated_at, threshold: 4, series: $series, events: $events}' \
  > "$LIVE_JSON"

echo "kikimimi: wrote $LIVE_JSON ($EVENT_COUNT events, $(echo "$SERIES" | jq 'length') series points)"
