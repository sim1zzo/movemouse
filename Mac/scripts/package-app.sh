#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAC_DIR="$ROOT/Mac"
BUILD_DIR="$MAC_DIR/build"
APP_BUNDLE="$BUILD_DIR/Move Mouse.app"
ARM_TRIPLE="arm64-apple-macosx13.0"
INTEL_TRIPLE="x86_64-apple-macosx13.0"
ARM_BUILD_DIR="$BUILD_DIR/.build-arm64"
INTEL_BUILD_DIR="$BUILD_DIR/.build-x86_64"

mkdir -p "$BUILD_DIR"
swift build --package-path "$MAC_DIR" --scratch-path "$ARM_BUILD_DIR" --configuration release --triple "$ARM_TRIPLE"
swift build --package-path "$MAC_DIR" --scratch-path "$INTEL_BUILD_DIR" --configuration release --triple "$INTEL_TRIPLE"
ARM_BIN_DIR="$(swift build --package-path "$MAC_DIR" --scratch-path "$ARM_BUILD_DIR" --configuration release --triple "$ARM_TRIPLE" --show-bin-path)"
INTEL_BIN_DIR="$(swift build --package-path "$MAC_DIR" --scratch-path "$INTEL_BUILD_DIR" --configuration release --triple "$INTEL_TRIPLE" --show-bin-path)"

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
lipo -create "$ARM_BIN_DIR/MoveMouseMac" "$INTEL_BIN_DIR/MoveMouseMac" -output "$APP_BUNDLE/Contents/MacOS/MoveMouseMac"
cp "$MAC_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
for lproj in "$MAC_DIR"/Resources/*.lproj; do
    rm -rf "$APP_BUNDLE/Contents/Resources/$(basename "$lproj")"
    cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
done

ICONSET_DIR="$BUILD_DIR/MoveMouse.iconset"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Images/mm_blue.png" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$ROOT/Images/mm_blue.png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/MoveMouse.icns"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
    # Ad-hoc sign the whole bundle so its identity (bundle ID + Info.plist) is sealed. A bundle whose
    # binary is only linker-signed can appear enabled in Privacy & Security > Accessibility while
    # macOS still denies it. Ad-hoc identities change on every build: re-grant access after rebuilding.
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "SIGNING_IDENTITY is not set; the app is ad-hoc signed (not Developer ID signed or notarized)."
fi

mkdir -p "$BUILD_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$BUILD_DIR/Move Mouse-macOS.zip"
DMG_STAGE="$(mktemp -d "$BUILD_DIR/dmg-stage.XXXXXX")"
trap 'rm -rf "$DMG_STAGE"' EXIT
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "Move Mouse" -srcfolder "$DMG_STAGE" -ov -format UDZO "$BUILD_DIR/Move Mouse-macOS.dmg"

echo "Created: $APP_BUNDLE"
echo "Created: $BUILD_DIR/Move Mouse-macOS.zip"
echo "Created: $BUILD_DIR/Move Mouse-macOS.dmg"
