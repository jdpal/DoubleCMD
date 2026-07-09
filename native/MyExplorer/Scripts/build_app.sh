#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_CONFIG=${BUILD_CONFIG:-release}
VERSION=${VERSION:-$(cat "$PROJECT_DIR/VERSION")}
ARCH=${ARCH:-$(uname -m)}
APP_NAME="My Explorer"
APP_DIR=${APP_DIR:-"$PROJECT_DIR/.build/$APP_NAME.app"}

swift build --package-path "$PROJECT_DIR" -c "$BUILD_CONFIG" --arch "$ARCH"
BIN_DIR=$(swift build --package-path "$PROJECT_DIR" -c "$BUILD_CONFIG" --arch "$ARCH" --show-bin-path)
EXECUTABLE="$BIN_DIR/MyExplorer"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/MyExplorer"
cp "$PROJECT_DIR/Resources/MyExplorer.icns" "$APP_DIR/Contents/Resources/MyExplorer.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MyExplorer</string>
  <key>CFBundleIconFile</key>
  <string>MyExplorer</string>
  <key>CFBundleIdentifier</key>
  <string>com.jdpal.myexplorer</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>My Explorer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Jatin Durgapal. All rights reserved.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
