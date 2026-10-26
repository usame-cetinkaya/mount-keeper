#!/usr/bin/env bash
# Builds "Mount Keeper.app" (Apple Silicon) and a .dmg into dist/.
#
#   scripts/build.sh                       release build + dmg
#   CONFIGURATION=debug scripts/build.sh   debug build, no dmg, no login item
#   VERSION=1.2.3 scripts/build.sh         override the version in Info.plist
#   CODESIGN_IDENTITY="Developer ID Application: ..." scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Mount Keeper"
EXECUTABLE="MountKeeper"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"
DIST="dist"
APP="$DIST/$APP_NAME.app"

# Command Line Tools without Xcode can't run SwiftPM's default build system.
BUILD_FLAGS=(-c "$CONFIGURATION" --arch arm64)
if ! xcodebuild -version >/dev/null 2>&1; then
  BUILD_FLAGS+=(--build-system native)
fi

swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"

if [ "$CONFIGURATION" = "release" ]; then
  strip -x "$APP/Contents/MacOS/$EXECUTABLE"
fi

# Ad-hoc signature by default; Apple Silicon refuses to run unsigned code.
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"

if [ "$CONFIGURATION" = "release" ]; then
  STAGING="$(mktemp -d)"
  trap 'rm -rf "$STAGING"' EXIT
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format ULMO -ov \
    "$DIST/Mount-Keeper-$VERSION-arm64.dmg"
fi

du -sh "$DIST"/*
