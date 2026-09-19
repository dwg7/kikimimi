#!/usr/bin/env bash
# Register/unregister scripts/sync-segments.sh as a periodic macOS LaunchAgent
# on the Mac mini role machine. This is the "make it recurring" step that
# documents/decisions/0012-rsync-pull-over-tmpfs.md deliberately left as a
# human decision -- run this only after `just sync-segments` has already
# worked by hand at least once.
#
# A LaunchAgent (not a LaunchDaemon) is used on purpose: it runs in the
# logged-in user's context, with access to that user's SSH keys -- which is
# what rsync/ssh to the RPi needs. It only runs while that user is logged in,
# which is fine for this machine's normal operation.
set -euo pipefail

ACTION="${1:-install}"
LABEL="com.dwg7.kikimimi.sync-segments"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/Library/Logs/kikimimi"
INTERVAL_SEC="${KIKIMIMI_SYNC_INTERVAL_SEC:-60}"

case "$ACTION" in
  install)
    mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${REPO_DIR}/scripts/sync-segments.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${REPO_DIR}</string>
    <key>StartInterval</key>
    <integer>${INTERVAL_SEC}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/sync-segments.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/sync-segments.log</string>
</dict>
</plist>
EOF
    # unload first in case a previous version is already loaded, so this is
    # safe to re-run after editing the interval or the script
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load -w "$PLIST"
    echo "installed and loaded: $PLIST"
    echo "runs every ${INTERVAL_SEC}s. logs: ${LOG_DIR}/sync-segments.log"
    echo "check with:   just sync-timer-status"
    echo "uninstall with: ./scripts/install-sync-timer.sh uninstall"
    ;;
  uninstall)
    if [ -f "$PLIST" ]; then
      launchctl unload "$PLIST" 2>/dev/null || true
      rm -f "$PLIST"
      echo "unloaded and removed: $PLIST"
    else
      echo "not installed: $PLIST"
    fi
    ;;
  status)
    if launchctl list | grep -q "$LABEL"; then
      echo "loaded:"
      launchctl list "$LABEL"
    else
      echo "not loaded"
    fi
    echo "log: ${LOG_DIR}/sync-segments.log"
    [ -f "${LOG_DIR}/sync-segments.log" ] && tail -20 "${LOG_DIR}/sync-segments.log"
    ;;
  *)
    echo "usage: $0 [install|uninstall|status]" >&2
    exit 1
    ;;
esac
