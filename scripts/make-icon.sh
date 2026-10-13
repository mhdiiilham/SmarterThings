#!/usr/bin/env bash
# Renders the app icon (scripts/make-icon.swift) and packs it into Resources/AppIcon.icns.
set -euo pipefail

cd "$(dirname "$0")/.."
iconset="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$iconset")"' EXIT

swift scripts/make-icon.swift "$iconset"
iconutil --convert icns --output Resources/AppIcon.icns "$iconset"
cp "$iconset/icon_512x512@2x.png" Resources/AppIcon.png
echo "Built Resources/AppIcon.icns and Resources/AppIcon.png"
