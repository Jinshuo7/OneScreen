#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OneScreen"
VERSION="1.0"
BUILD_DIR="$ROOT_DIR/build/release"
APP_DIR="$BUILD_DIR/OneScreen.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RELEASE_ZIP="$BUILD_DIR/OneScreen-$VERSION.zip"
ICONSET_DIR="$BUILD_DIR/OneScreen.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
MODULE_CACHE_DIR="$ROOT_DIR/build/module-cache"
ICON_GENERATOR="$BUILD_DIR/generate_icon"

cd "$ROOT_DIR"

mkdir -p "$BUILD_DIR"
mkdir -p "$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
rm -rf "$APP_DIR" "$RELEASE_ZIP" "$ICONSET_DIR" "$ICON_GENERATOR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Building $APP_NAME $VERSION..."
swiftc Sources/OneScreen/main.swift \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -O \
    -o "$MACOS_DIR/OneScreen" \
    -framework AppKit \
    -framework Carbon \
    -framework CoreGraphics \
    -framework ServiceManagement

echo "Generating app icon..."
swiftc Scripts/generate_icon.swift \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -o "$ICON_GENERATOR" \
    -framework AppKit \
    -framework CoreGraphics
"$ICON_GENERATOR" "$ICONSET_DIR" "$ICON_FILE"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OneScreen</string>
    <key>CFBundleIdentifier</key>
    <string>local.onescreen.blackout</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OneScreen</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$RELEASE_ZIP"

echo "Created $APP_DIR"
echo "Created $RELEASE_ZIP"
