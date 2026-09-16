#!/usr/bin/env bash
# Observability, not setup: reports what's reachable, changes nothing.
# Run this on whichever machine (RPi 4B or Mac mini) you want to check.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok()   { printf '  [ok]   %s\n' "$1"; }
warn() { printf '  [--]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; }

echo "== kikimimi diagnose =="
echo "repo: $REPO_ROOT"
echo

echo "-- OpenSpeechMap CLI --"
if command -v speechmap >/dev/null 2>&1; then
  ok "speechmap on PATH ($(command -v speechmap))"
  speechmap check || true
else
  warn "speechmap not on PATH (not installed in this shell's venv?)"
fi
echo

echo "-- capture (RPi 4B role) --"
for prog in rtl_test rtl_fm ffmpeg; do
  if command -v "$prog" >/dev/null 2>&1; then
    ok "$prog found"
  else
    warn "$prog not found (expected on the RPi 4B, not the Mac mini)"
  fi
done
echo

echo "-- transcription (whisper.cpp server) --"
WHISPER_URL="${WHISPER_URL:-http://127.0.0.1:8080/inference}"
if command -v curl >/dev/null 2>&1; then
  base="${WHISPER_URL%/inference}"
  if curl -fsS -o /dev/null -m 3 "$base" 2>/dev/null; then
    ok "something answers at $base (checked without hitting /inference itself)"
  else
    warn "no answer from $base (set WHISPER_URL if it's not the default)"
  fi
else
  fail "curl not found -- cannot check"
fi
echo

echo "-- lens (LLM endpoint) --"
LLM_URL="${LLM_URL:-http://127.0.0.1:8080/v1}"
if curl -fsS -m 3 "$LLM_URL/models" >/dev/null 2>&1; then
  ok "LLM endpoint answers at $LLM_URL/models"
else
  warn "no answer from $LLM_URL/models (set LLM_URL if it's not the default)"
fi
echo

echo "-- grounding stub (ADR 0002) --"
if command -v locitorium >/dev/null 2>&1; then
  out="$(printf '' | locitorium resolve --format geojson 2>/dev/null)"
  if [ "$out" = '{"type":"FeatureCollection","features":[]}' ]; then
    ok "locitorium on PATH is the kikimimi stub (empty FeatureCollection, as intended)"
  else
    warn "locitorium on PATH does not look like the stub -- is a real one installed? (see ADR 0002 for why that's probably not wanted here)"
  fi
else
  warn "locitorium not on PATH -- speechmap lens will fail without it (see ADR 0002; install scripts/locitorium-stub.sh)"
fi
echo

echo "-- tokachi-lens files --"
LENS_DIR="$REPO_ROOT/lenses/tokachi-lens"
for f in schema.json instruction.txt system.txt gate.txt; do
  path="$LENS_DIR/$f"
  if [ -f "$path" ]; then
    ok "$f present"
  else
    if [ "$f" = "schema.json" ] || [ "$f" = "instruction.txt" ]; then
      fail "$f missing (required)"
    else
      warn "$f missing (optional)"
    fi
  fi
done
if command -v jq >/dev/null 2>&1 && [ -f "$LENS_DIR/schema.json" ]; then
  if jq empty "$LENS_DIR/schema.json" >/dev/null 2>&1; then
    ok "schema.json is valid JSON"
  else
    fail "schema.json is not valid JSON"
  fi
fi
echo

echo "== done =="
echo "This script only reports; it changes nothing. See README.md for the"
echo "'not verified intelligence' caveat before acting on kikimimi's output."
