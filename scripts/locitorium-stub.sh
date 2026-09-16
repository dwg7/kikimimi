#!/usr/bin/env bash
# A stand-in for `locitorium resolve`, so `speechmap lens` runs without a real
# locitorium/Nominatim install. See documents/decisions/0002-omit-nominatim-grounding.md
# for why: kikimimi watches one known point (十勝岳) and does not use the
# places.geojson output, so real place grounding buys nothing here.
#
# Satisfies only the CLI surface `speechmap lens` actually calls (see
# src/openspeechmap/pipeline.py `_resolve()` in OpenSpeechMap): reads JSONL on
# stdin, and when asked for --format geojson, writes an empty GeoJSON
# FeatureCollection to stdout. Modelled on OpenSpeechMap's own test stub
# (tests/stubs/locitorium), which does the same thing to avoid a Nominatim
# dependency in CI.
#
# Install: put this file on PATH as `locitorium` (or point the LOCITORIUM
# checkout fallback at a directory containing it), so that
# `speechmap`'s `find("locitorium")` succeeds.
set -euo pipefail

[ "${1:-}" = "resolve" ] || {
  echo "locitorium-stub: only 'resolve' is stubbed (kikimimi omits grounding, see ADR 0002)" >&2
  exit 2
}
shift

FORMAT="jsonl"
while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT="$2"; shift 2 ;;
    --text-field|--id-field|--server-url) shift 2 ;;
    --quiet) shift ;;
    *) shift ;;
  esac
done

# Drain stdin so an upstream writer never blocks on a full pipe.
cat >/dev/null

if [ "$FORMAT" = "geojson" ]; then
  echo '{"type":"FeatureCollection","features":[]}'
else
  # No known caller needs jsonl output from this stage, but stay well-defined.
  true
fi
