#!/bin/bash
# Generates the Xcode project and builds Debug and Release. Logs go to build/logs.
set -uo pipefail
cd "$(dirname "$0")/.."
# Outside the Desktop on purpose: iCloud Drive tags files there and codesign rejects them.
DERIVED="${DERIVED:-$HOME/Library/Developer/SnapBar/DerivedData}"
xcodegen generate --quiet || exit 1
mkdir -p build/logs
status=0
for CONFIG in ${CONFIGS:-Debug Release}; do
  LOG="build/logs/build-$CONFIG.log"
  xcodebuild -project SnapBar.xcodeproj -scheme SnapBar -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" -destination 'platform=macOS' build >"$LOG" 2>&1
  rc=$?
  warnings=$(grep -c "warning:" "$LOG" || true)
  errors=$(grep -c "error:" "$LOG" || true)
  result=$(grep -oE "BUILD (SUCCEEDED|FAILED)" "$LOG" | tail -1)
  echo "$CONFIG: ${result:-NO RESULT} warnings=$warnings errors=$errors log=$LOG"
  [ $rc -ne 0 ] && status=1
done
exit $status
