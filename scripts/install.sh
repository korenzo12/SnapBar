#!/bin/bash
# Builds Release, replaces /Applications/SnapBar.app (the old copy goes to the Trash), and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGS=Release ./scripts/build.sh
APP="$HOME/Library/Developer/SnapBar/DerivedData/Build/Products/Release/SnapBar.app"
[ -d "$APP" ] || { echo "no build at $APP"; exit 1; }
pkill -x SnapBar 2>/dev/null || true
sleep 0.5
if [ -d /Applications/SnapBar.app ]; then
  mv /Applications/SnapBar.app "$HOME/.Trash/SnapBar $(date +%Y-%m-%d\ %H.%M.%S).app"
fi
ditto "$APP" /Applications/SnapBar.app
codesign -dv /Applications/SnapBar.app 2>&1 | grep -E "Identifier|Signature" || true
echo "installed version $(defaults read /Applications/SnapBar.app/Contents/Info.plist CFBundleShortVersionString)"
open /Applications/SnapBar.app
