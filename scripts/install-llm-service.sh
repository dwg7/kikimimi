#!/usr/bin/env bash
# Register/unregister `ollama serve` as a periodic-checked macOS LaunchAgent
# on the Mac mini role machine, so `speechmap lens`'s LLM endpoint survives
# logout/reboot without anyone remembering to run `ollama serve` by hand.
#
# Same rationale as scripts/install-sync-timer.sh: a LaunchAgent (not a
# LaunchDaemon), because it only needs to run while the operating user is
# logged in, and KeepAlive (not StartInterval) because this is a long-running
# server, not a one-shot task.
#
# OLLAMA_MODELS is pinned to $HOME/ollama-models (not ollama's default
# $HOME/.ollama/models) because on this machine that path resolved into
# ~/github/dot.ollama/models (a dotfiles-managed symlink), and macOS TCC
# silently blocks launchd-spawned processes from reading that particular
# directory ("Operation not permitted", confirmed by a minimal `ls` test
# LaunchAgent) even though the same command works fine from an interactive
# shell. Moving the actual model blobs to a plain, non-dotfiles-managed
# path under $HOME sidesteps the TCC restriction entirely -- no GUI/Full
# Disk Access grant needed. See documents/decisions/ for the writeup.
set -euo pipefail

ACTION="${1:-install}"
LABEL="com.dwg7.kikimimi.ollama"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/kikimimi"
OLLAMA_BIN="$(command -v ollama || echo /opt/homebrew/bin/ollama)"

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
        <string>${OLLAMA_BIN}</string>
        <string>serve</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>OLLAMA_MODELS</key>
        <string>${HOME}/ollama-models</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/ollama.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load -w "$PLIST"
    echo "installed and loaded: $PLIST"
    echo "endpoint: http://127.0.0.1:11434/v1 (OpenAI-compatible)"
    echo "logs: ${LOG_DIR}/ollama.log"
    echo "uninstall with: ./scripts/install-llm-service.sh uninstall"
    ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "unloaded and removed: $PLIST"
    ;;
  status)
    launchctl list | grep "$LABEL" || echo "not loaded"
    tail -20 "${LOG_DIR}/ollama.log" 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 [install|uninstall|status]" >&2
    exit 1
    ;;
esac
