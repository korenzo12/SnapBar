#!/bin/bash
# Debug stand-in for /usr/sbin/screencapture (see AppEnvironment.captureTool).
# Writes a sample PNG to the output path, or exits without a file when the mode file says "cancel",
# which is exactly what the real tool does when you press Esc.
out="${@: -1}"
home="${SNAPBAR_HOME:-/tmp}"
mode="$(cat "$home/fake-capture-mode" 2>/dev/null || echo ok)"
echo "$(date '+%H:%M:%S') args=$* mode=$mode" >> "$home/fake-capture.log"
[ "$mode" = "cancel" ] && exit 1
cp "${FAKE_CAPTURE_SAMPLE:-$home/Samples/sample-3.png}" "$out"
