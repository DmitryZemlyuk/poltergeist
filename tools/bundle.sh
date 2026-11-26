#!/bin/bash
# Builds a universal "Poltergeist.app" and a zip into dist/. Runs on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
BUILD=${GITHUB_RUN_NUMBER:-1}
APP="dist/Poltergeist.app"

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Poltergeist

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Poltergeist"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
for lang in en ru uk; do
  plutil -lint "Resources/$lang.lproj/Localizable.strings"
  cp -R "Resources/$lang.lproj" "$APP/Contents/Resources/"
done
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

ditto -c -k --keepParent "$APP" "dist/Poltergeist-${VERSION}-macos-universal.zip"
echo "Built $APP ($VERSION, build $BUILD)"
