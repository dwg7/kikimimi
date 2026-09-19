#!/usr/bin/env bash
# Back up an SD card to a compressed image file, before repurposing it
# for kikimimi (this Pi's physical chassis is shared across multiple
# dwg7 projects — see documents/decisions/0009-rpi-os-trixie-cloudinit-just.md).
# Pairs with scripts/restore-sdcard.sh.
#
# Ported from rpi-geoserver0's scripts/backup-sdcard.sh (2026-09-17),
# written for exactly this handover. Generic enough that no changes were
# needed beyond this header and the example path below.
#
# Like flash-sdcard.sh, this is deliberately NOT run unattended: you
# confirm the device yourself. Reading the wrong block device is less
# catastrophic than writing to it, but still not something to automate
# past a human's eyes.
set -euo pipefail

DEVICE="${1:-}"
OUT="${2:-}"
if [[ -z "$DEVICE" || -z "$OUT" ]]; then
  echo "usage: $0 <source-device> <output-image.img.gz>" >&2
  echo "  e.g.: $0 /dev/rdisk4 backups/rpi-geoserver0-2026-09-19.img.gz" >&2
  echo "  list candidate devices first, e.g. on macOS: diskutil list external" >&2
  exit 1
fi

# Same internal-disk guard as flash-sdcard.sh.
case "$DEVICE" in
  /dev/disk0|/dev/disk1|/dev/rdisk0|/dev/rdisk1)
    echo "error: '$DEVICE' looks like a macOS internal disk identifier — refusing." >&2
    echo "  confirm the SD card's identifier with: diskutil list external" >&2
    exit 1
    ;;
esac

if [[ ! -e "$DEVICE" ]]; then
  echo "error: '$DEVICE' does not exist." >&2
  exit 1
fi

if [[ -e "$OUT" ]]; then
  echo "error: '$OUT' already exists — refusing to overwrite a backup." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

echo "About to read the ENTIRE card at '$DEVICE' and write a compressed image to '$OUT'."
echo "This does not modify '$DEVICE' — it's a read-only backup."
read -r -p "Type the device path again to confirm ($DEVICE): " CONFIRM
if [[ "$CONFIRM" != "$DEVICE" ]]; then
  echo "confirmation did not match — aborting, nothing read." >&2
  exit 1
fi

# On macOS, the raw device (/dev/rdiskN) is substantially faster to
# read than the buffered one (/dev/diskN). bs=4m is a reasonable
# middle ground for SD card read speeds; gzip shrinks a mostly-empty
# Pi image a lot (typically well under half the raw card size).
echo "Reading $DEVICE (this can take a while for a large card)..."
dd if="$DEVICE" bs=4m status=progress | gzip > "$OUT"

echo "done. Backup written to $OUT ($(du -h "$OUT" | cut -f1))."
echo "To restore this exact card state later: scripts/restore-sdcard.sh $OUT <target-device>"
