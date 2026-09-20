#!/usr/bin/env bash
# Register/unregister scripts/publish-live-data.sh as a periodic macOS
# LaunchAgent (every 30 minutes by default), so the published GitHub Pages
# dashboard keeps getting refreshed without manual pushes.
#
# Same pattern as scripts/install-sync-timer.sh -- see that script and
# documents/decisions/0016-publish-docs-via-github-pages.md for why this is
# a separate, slower timer rather than folded into sync-segments.sh's
# 60-second cadence.
set -euo pipefail

ACTION="${1:-install}"
LABEL="com.dwg7.kikimimi.publish-live-data"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/Library/Logs/kikimimi"
INTERVAL_SEC="${KIKIMIMI_PUBLISH_INTERVAL_SEC:-1800}"

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
        <string>${REPO_DIR}/scripts/publish-live-data.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${REPO_DIR}</string>
    <key>StartInterval</key>
    <integer>${INTERVAL_SEC}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/publish-live-data.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/publish-live-data.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load -w "$PLIST"
    echo "installed and loaded: $PLIST"
    echo "runs every ${INTERVAL_SEC}s. logs: ${LOG_DIR}/publish-live-data.log"
    echo "check with:   just publish-timer-status"
    echo "uninstall with: ./scripts/install-publish-timer.sh uninstall"
    ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "unloaded and removed: $PLIST"
    ;;
  status)
    launchctl list | grep "$LABEL" || echo "not loaded"
    tail -20 "${LOG_DIR}/publish-live-data.log" 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 [install|uninstall|status]" >&2
    exit 1
    ;;
esac
