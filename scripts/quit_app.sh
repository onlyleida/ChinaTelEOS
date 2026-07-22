#!/bin/zsh
set -euo pipefail

# Quit by bundle name and by executable name, then force-kill leftovers.
osascript -e 'tell application "翼存 CloudBox" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "CloudBox" to quit' >/dev/null 2>&1 || true
pkill -x CloudBox >/dev/null 2>&1 || true

for _ in {1..30}; do
  pgrep -x CloudBox >/dev/null 2>&1 || exit 0
  sleep 0.1
done

pkill -9 -x CloudBox >/dev/null 2>&1 || true
exit 0
