#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" XDG_CACHE_HOME="$PWD/.build/cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$XDG_CACHE_HOME"
swift build -c release --disable-sandbox --scratch-path "$PWD/.build"
APP="$PWD/dist/Mayhem Pocket.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ARAMMayhem "$APP/Contents/MacOS/MayhemPocket"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
codesign --force --deep --sign - "$APP"
