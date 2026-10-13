#!/usr/bin/env bash
# Builds the app and wraps it in SmarterThings.app (menu bar only, no Dock icon).
# Usage: scripts/bundle.sh [release|debug]   (default: release; VERSION env sets the version)
set -euo pipefail

cd "$(dirname "$0")/.."
app="SmarterThings.app"
configuration="${1:-release}"
version="${VERSION:-1.0.0}"

# Release builds are universal (Apple Silicon + Intel); debug builds stay native for speed.
arch_flags=()
if [ "$configuration" = "release" ]; then
    arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"} --product TVRemoteApp
binary="$(swift build -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)/TVRemoteApp"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/SmarterThings"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SmarterThings</string>
    <key>CFBundleIdentifier</key><string>com.mhdiiilham.SmarterThings</string>
    <key>CFBundleName</key><string>SmarterThings</string>
    <key>CFBundleDisplayName</key><string>SmarterThings</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>SmarterThings finds your Samsung TV on this network to type into it and check which apps are installed.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $PWD/$app ($version, $configuration)"
