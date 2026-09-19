#!/usr/bin/env bash
# Restore a card image previously made with scripts/backup-sdcard.sh.
# Pairs with backup-sdcard.sh — see that script's header for why this
# pair exists (shared physical Pi chassis across dwg7 projects).
#
# Ported from rpi-geoserver0's scripts/restore-sdcard.sh (2026-09-17),
# written for exactly this handover. Generic; no changes needed beyond
# this header.
#
# Deliberately NOT run unattended — same reasoning as flash-sdcard.sh:
# writing to the wrong block device destroys data with no undo.
set -euo pipefail

IMAGE="${1:-}"
DEVICE="${2:-}"
if [[ -z "$IMAGE" || -z "$DEVICE" ]]; then
  echo "usage: $0 <backup-image.img.gz> <target-device> [mdns-hostname]" >&2
  echo "  e.g.: $0 backups/rpi-geoserver0-2026-09-19.img.gz /dev/rdisk4 <hostname>.local" >&2
  echo "  the optional third argument clears that host's cached SSH key" >&2
  echo "  afterward (ssh-keygen -R) — every reflash/restore gets a fresh" >&2
  echo "  host key, so without this the next 'ssh' will refuse to connect" >&2
  echo "  with 'REMOTE HOST IDENTIFICATION HAS CHANGED!'." >&2
  exit 1
fi
HOSTNAME_HINT="${3:-}"

case "$DEVICE" in
  /dev/disk0|/dev/disk1|/dev/rdisk0|/dev/rdisk1)
    echo "error: '$DEVICE' looks like a macOS internal disk identifier — refusing." >&2
    echo "  confirm the SD card's identifier with: diskutil list external" >&2
    exit 1
    ;;
esac

if [[ ! -f "$IMAGE" ]]; then
  echo "error: backup image '$IMAGE' not found." >&2
  exit 1
fi

if [[ ! -e "$DEVICE" ]]; then
  echo "error: '$DEVICE' does not exist." >&2
  exit 1
fi

echo "About to write '$IMAGE' to '$DEVICE'."
echo "This ERASES everything currently on $DEVICE."
read -r -p "Type the device path again to confirm ($DEVICE): " CONFIRM
if [[ "$CONFIRM" != "$DEVICE" ]]; then
  echo "confirmation did not match — aborting, nothing written." >&2
  exit 1
fi

echo "Writing $IMAGE to $DEVICE (this can take a while)..."
gunzip -c "$IMAGE" | dd of="$DEVICE" bs=4m status=progress
sync

if [[ -n "$HOSTNAME_HINT" ]]; then
  ssh-keygen -R "$HOSTNAME_HINT" >/dev/null 2>&1 || true
  echo "cleared any cached SSH host key for '$HOSTNAME_HINT'."
fi

echo "done. Insert the card into the Pi and power on."
echo "cloud-init treats this as a fresh boot only if the meta-data"
echo "instance_id differs from what that install last saw — a straight"
echo "backup/restore of the same card preserves it byte-for-byte, so no"
echo "first-boot logic re-runs. First SSH may still warn about the host"
echo "key if you didn't pass a hostname above to clear it."
