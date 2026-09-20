#!/usr/bin/env bash
# Collect coarse health info (temperature, load average, service status) from
# the RPi and this machine (Mac mini role), and write docs/data/health.json
# for the dashboard's health panel.
#
# Deliberately generic labels ("RPi", "Mac mini") only -- no hostnames, no
# IPs, matching the project's standing policy of never putting individual
# machine identifiers in anything published (see .env.example, ADR 0009).
#
# Mac-side temperature is intentionally omitted: reading it needs
# `sudo powermetrics`, which requires an interactive password this script
# cannot supply. Load average alone is shown for the Mac.
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

KIKIMIMI_ENV_FILE="${KIKIMIMI_ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env}"
if [ -z "${KIKIMIMI_RPI_HOST:-}" ] && [ -f "$KIKIMIMI_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$KIKIMIMI_ENV_FILE"
  set +a
fi

: "${KIKIMIMI_RPI_HOST:?set in .env}"
KIKIMIMI_RPI_USER="${KIKIMIMI_RPI_USER:-pi}"
KIKIMIMI_RPI_HOST="${KIKIMIMI_RPI_HOST%.local}.local"
OPENMCT_DATA_DIR="${KIKIMIMI_OPENMCT_DATA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/data}"

# --- RPi: temp, load, recording service state, in one SSH round trip ---
RPI_RAW=$(ssh -o ConnectTimeout=10 "${KIKIMIMI_RPI_USER}@${KIKIMIMI_RPI_HOST}" \
  'vcgencmd measure_temp; cat /proc/loadavg; systemctl is-active kikimimi-record.service' \
  2>/dev/null || echo "")

RPI_TEMP=$(echo "$RPI_RAW" | sed -n "1p" | sed -E "s/temp=([0-9.]+).*/\1/")
RPI_LOAD=$(echo "$RPI_RAW" | sed -n "2p" | awk '{print $1}')
RPI_SERVICE=$(echo "$RPI_RAW" | sed -n "3p")
[ -z "$RPI_SERVICE" ] && RPI_SERVICE="unknown"

# --- Mac mini role machine: load average only (see header) ---
MAC_LOAD=$(uptime | sed -E 's/.*load averages?: *([0-9.]+).*/\1/')

GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg generated_at "$GENERATED_AT" \
  --arg rpi_temp "$RPI_TEMP" --arg rpi_load "$RPI_LOAD" --arg rpi_service "$RPI_SERVICE" \
  --arg mac_load "$MAC_LOAD" \
  '{
    generated_at: $generated_at,
    machines: [
      {
        label: "RPi",
        temp_c: (if $rpi_temp == "" then null else ($rpi_temp | tonumber) end),
        load_1m: (if $rpi_load == "" then null else ($rpi_load | tonumber) end),
        recording: $rpi_service
      },
      {
        label: "Mac mini",
        temp_c: null,
        load_1m: (if $mac_load == "" then null else ($mac_load | tonumber) end),
        recording: null
      }
    ]
  }' > "$OPENMCT_DATA_DIR/health.json"

echo "kikimimi: wrote $OPENMCT_DATA_DIR/health.json"
