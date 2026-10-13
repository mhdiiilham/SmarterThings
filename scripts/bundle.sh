#!/usr/bin/env bash
# Builds a release binary and wraps it in TVRemote.app (menu bar only, no Dock icon).
set -euo pipefail

cd "$(dirname "$0")/.."
app="TVRemote.app"

swift build -c release --product TVRemoteApp
binary="$(swift build -c release --show-bin-path)/TVRemoteApp"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/TVRemote"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TVRemote</string>
    <key>CFBundleIdentifier</key><string>com.mo.TVRemote</string>
    <key>CFBundleName</key><string>TV Remote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>TV Remote connects to your Samsung TV on this network so you can type into it.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $PWD/$app"
