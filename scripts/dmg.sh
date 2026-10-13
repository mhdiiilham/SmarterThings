#!/usr/bin/env bash
# Packages SmarterThings.app into a drag-to-Applications disk image: build/SmarterThings-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
version="${VERSION:-1.0.0}"
dmg="build/SmarterThings-$version.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

VERSION="$version" scripts/bundle.sh release

cp -R SmarterThings.app "$staging/"
ln -s /Applications "$staging/Applications"

mkdir -p build
rm -f "$dmg"
hdiutil create -volname "SmarterThings $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null

shasum -a 256 "$dmg" | tee "$dmg.sha256"
echo "Built $PWD/$dmg"
