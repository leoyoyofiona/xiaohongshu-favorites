#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

LOG_FILE="/tmp/xhsorganizer.log"
APP_BIN="$ROOT_DIR/.build/debug/XHSOrganizerApp"

if [ ! -x "$APP_BIN" ]; then
  swift build >/dev/null
fi

if pgrep -x "XHSOrganizerApp" >/dev/null 2>&1; then
  osascript -e 'tell application "System Events" to set frontmost of process "XHSOrganizerApp" to true' >/dev/null 2>&1 || true
  exit 0
fi

nohup "$APP_BIN" >"$LOG_FILE" 2>&1 </dev/null &
disown

sleep 1
osascript -e 'tell application "System Events" to set frontmost of process "XHSOrganizerApp" to true' >/dev/null 2>&1 || true
