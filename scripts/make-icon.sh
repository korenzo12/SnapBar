#!/bin/bash
# Renders the icon and fills SnapBar/Assets.xcassets/AppIcon.appiconset with every macOS size.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="SnapBar/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
swift scripts/make-icon.swift "$SET/icon_1024.png"
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$SET/icon_1024.png" --out "$SET/icon_$s.png" >/dev/null
done
cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "SnapBar/Assets.xcassets/Contents.json"
echo "icon set written: $(ls "$SET" | wc -l | tr -d ' ') files"
