#!/usr/bin/env bash
# Register/unregister `speechmap record` as a systemd service on the RPi 4B,
# so continuous SDR capture survives SSH disconnects and reboots without
# anyone babysitting a foreground process.
#
# This is the RPi-side counterpart to scripts/install-sync-timer.sh (which
# does the equivalent for the Mac mini role machine via launchd). Run this
# ON the RPi (or via ssh <rpi> 'bash -s' < this script).
#
# A system-level unit (not `systemctl --user`) is used on purpose: it starts
# at boot without needing a lingering login session for the user, which
# `systemctl --user` would require (`loginctl enable-linger`).
set -euo pipefail

ACTION="${1:-install}"
UNIT_NAME="kikimimi-record.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"
RUN_USER="$(id -un)"
OSM_DIR="${OSM_DIR:-$HOME/OpenSpeechMap}"
UV_BIN="$(command -v uv || echo "$HOME/.local/bin/uv")"

AUDIO_DIR="${KIKIMIMI_RPI_AUDIO_DIR:-/mnt/kikimimi-audio}"
FREQ="${KIKIMIMI_FREQ:-85.2M}"
GAIN="${KIKIMIMI_GAIN:-40.2}"
DEVICE="${KIKIMIMI_DEVICE:-0}"
LABEL="${KIKIMIMI_LABEL:-NHKFM}"
SEGMENT_SEC="${KIKIMIMI_SEGMENT_SEC:-60}"
RETENTION_HOURS="${KIKIMIMI_RETENTION_HOURS:-12}"
MAX_GB="${KIKIMIMI_MAX_GB:-0.8}"

case "$ACTION" in
  install)
    if ! mountpoint -q "$AUDIO_DIR"; then
      echo "error: $AUDIO_DIR is not a mountpoint yet. Run setup-rpi.sh's" >&2
      echo "tmpfs step first (documents/decisions/0012-rsync-pull-over-tmpfs.md)." >&2
      exit 1
    fi
    sudo tee "$UNIT_PATH" > /dev/null <<EOF
[Unit]
Description=kikimimi: continuous SDR capture (speechmap record)
After=network.target sound.target
RequiresMountsFor=${AUDIO_DIR}

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${OSM_DIR}
Environment=PATH=$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
ExecStart=${UV_BIN} run speechmap record --source sdr --freq ${FREQ} --gain ${GAIN} --device ${DEVICE} --out ${AUDIO_DIR} --segment-sec ${SEGMENT_SEC} --retention-hours ${RETENTION_HOURS} --max-gb ${MAX_GB} --label ${LABEL}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$UNIT_NAME"
    echo "installed and started: $UNIT_PATH"
    echo "recording: ${LABEL} at ${FREQ}, gain ${GAIN}, into ${AUDIO_DIR}"
    echo "check with:   just record-service-status   (or: systemctl status $UNIT_NAME)"
    echo "logs:         journalctl -u $UNIT_NAME -f"
    echo "uninstall with: ./scripts/install-record-service.sh uninstall"
    ;;
  uninstall)
    sudo systemctl disable --now "$UNIT_NAME" 2>/dev/null || true
    sudo rm -f "$UNIT_PATH"
    sudo systemctl daemon-reload
    echo "stopped and removed: $UNIT_PATH"
    ;;
  status)
    systemctl status "$UNIT_NAME" --no-pager || true
    echo "--- recent log ---"
    journalctl -u "$UNIT_NAME" --no-pager -n 20 || true
    ;;
  *)
    echo "usage: $0 [install|uninstall|status]" >&2
    exit 1
    ;;
esac
