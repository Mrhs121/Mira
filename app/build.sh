#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"

swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
APP="$PWD/build/Mira.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Mira" "$APP/Contents/MacOS/Mira"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Mira.icns "$APP/Contents/Resources/Mira.icns"
chmod +x "$APP/Contents/MacOS/Mira"
codesign --force --deep --sign - "$APP" >/dev/null

echo "Built: $APP"
