#!/bin/bash
# Wraps the OrigamiClose binary into a real .app bundle. macOS grants Accessibility
# per bundled app identity, so the event tap needs this rather than a bare binary.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Origami Close.app"
BUNDLE_ID="com.samzehuang.OrigamiClose"

cd "$ROOT"
swift build -c "$CONFIG" --product OrigamiClose
BINARY="$(swift build -c "$CONFIG" --product OrigamiClose --show-bin-path)/OrigamiClose"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/OrigamiClose"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OrigamiClose</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Origami Close</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Sign with a real identity when one exists. An ad-hoc signature changes on every
# rebuild, which silently invalidates the Accessibility grant each time.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk 'NR==1 {print $2}')}"
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed (grant will need re-approving after each rebuild)"
fi

echo "Built: $APP"
