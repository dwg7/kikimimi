#!/usr/bin/env bash
# Register/unregister whisper-server as a persistent macOS LaunchAgent on the
# Mac mini role machine, so it survives logout/reboot without anyone
# remembering to start it by hand (it had been a plain `nohup` process since
# documents/decisions/0011-transcription-moves-to-macmini-role.md, which is
# how it silently stayed on the small model long after ADR 0011 recommended
# large-v3-turbo -- see that ADR's later addendum).
#
# Same LaunchAgent + KeepAlive pattern as scripts/install-llm-service.sh.
set -euo pipefail

ACTION="${1:-install}"
LABEL="com.dwg7.kikimimi.whisper-server"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/kikimimi"
WHISPER_DIR="${WHISPER_DIR:-$HOME/whisper.cpp}"
WHISPER_MODEL="${KIKIMIMI_WHISPER_MODEL:-large-v3-turbo}"
WHISPER_PORT="${KIKIMIMI_WHISPER_PORT:-30180}"

case "$ACTION" in
  install)
    MODEL_PATH="${WHISPER_DIR}/models/ggml-${WHISPER_MODEL}.bin"
    if [ ! -f "$MODEL_PATH" ]; then
      echo "error: model not found: $MODEL_PATH" >&2
      echo "  fetch it with: bash $WHISPER_DIR/models/download-ggml-model.sh $WHISPER_MODEL" >&2
      exit 1
    fi
    # Stop any manually-started (nohup) instance first, so the port is free.
    pkill -f "whisper-server" 2>/dev/null || true
    sleep 1
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
        <string>${WHISPER_DIR}/build/bin/whisper-server</string>
        <string>-m</string>
        <string>${MODEL_PATH}</string>
        <string>--host</string>
        <string>127.0.0.1</string>
        <string>--port</string>
        <string>${WHISPER_PORT}</string>
        <string>--language</string>
        <string>ja</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${WHISPER_DIR}</string>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/whisper-server.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/whisper-server.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load -w "$PLIST"
    echo "installed and loaded: $PLIST"
    echo "model: $WHISPER_MODEL, endpoint: http://127.0.0.1:${WHISPER_PORT}/inference"
    echo "logs: ${LOG_DIR}/whisper-server.log"
    echo "uninstall with: ./scripts/install-whisper-service.sh uninstall"
    ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "unloaded and removed: $PLIST"
    ;;
  status)
    launchctl list | grep "$LABEL" || echo "not loaded"
    tail -20 "${LOG_DIR}/whisper-server.log" 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 [install|uninstall|status]" >&2
    exit 1
    ;;
esac
