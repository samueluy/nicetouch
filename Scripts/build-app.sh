#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP="dist/NiceTouch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NiceTouch" "$APP/Contents/MacOS/NiceTouch"
cp -R "$BIN_DIR/NiceTouch_NiceTouch.bundle" "$APP/Contents/Resources/"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
"$APP/Contents/MacOS/NiceTouch" --check-resources
echo "Built $APP"
