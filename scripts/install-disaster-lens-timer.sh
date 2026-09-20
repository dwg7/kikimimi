#!/usr/bin/env bash
# Register/unregister scripts/run-disaster-lens.sh as a periodic macOS
# LaunchAgent on the Mac mini role machine. Kept on its own, longer-interval
# timer -- see run-disaster-lens.sh's header for why this must not share
# sync-segments.sh's 60s cadence (no gate.txt means every record hits the
# LLM). documents/decisions/0018-parallel-validation-lens.md.
set -euo pipefail

ACTION="${1:-install}"
LABEL="com.dwg7.kikimimi.disaster-lens"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/Library/Logs/kikimimi"
INTERVAL_SEC="${KIKIMIMI_DISASTER_LENS_INTERVAL_SEC:-600}"

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
        <string>${REPO_DIR}/scripts/run-disaster-lens.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${REPO_DIR}</string>
    <key>StartInterval</key>
    <integer>${INTERVAL_SEC}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/disaster-lens.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/disaster-lens.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load -w "$PLIST"
    echo "installed and loaded: $PLIST"
    echo "runs every ${INTERVAL_SEC}s. logs: ${LOG_DIR}/disaster-lens.log"
    echo "check with:   just disaster-lens-status"
    echo "uninstall with: ./scripts/install-disaster-lens-timer.sh uninstall"
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
    echo "log: ${LOG_DIR}/disaster-lens.log"
    [ -f "${LOG_DIR}/disaster-lens.log" ] && tail -20 "${LOG_DIR}/disaster-lens.log"
    ;;
  *)
    echo "usage: $0 [install|uninstall|status]" >&2
    exit 1
    ;;
esac
