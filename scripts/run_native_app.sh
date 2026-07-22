#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

CONFIGURATION="${1:-debug}"

./scripts/quit_app.sh
./scripts/build_native_app.sh "$CONFIGURATION"

APP_PATH="build/翼存 CloudBox.app"
open "$APP_PATH"

# Wait until the process is actually up, then bring it to the front.
for _ in {1..50}; do
  if pgrep -x CloudBox >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! pgrep -x CloudBox >/dev/null 2>&1; then
  echo "error: CloudBox failed to launch" >&2
  exit 1
fi

osascript -e 'tell application "翼存 CloudBox" to activate' >/dev/null 2>&1 || true
echo "running: $APP_PATH (pid $(pgrep -x CloudBox | tr '\n' ' '))"
