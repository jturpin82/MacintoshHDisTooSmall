#!/bin/bash
# Builds MacintoshHDisTooSmall.app (universal) into .dist/ and zips it.
# Usage: ./build.sh [version]
set -euo pipefail

VERSION="${1:-0.1}"
NAME="MacintoshHDisTooSmall"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/.dist"
APP="$DIST/$NAME.app"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compilation (arm64 + x86_64)"
swift build -c release --package-path "$ROOT" --arch arm64 --arch x86_64
BIN_PATH="$(swift build -c release --package-path "$ROOT" --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_PATH/$NAME" "$APP/Contents/MacOS/$NAME"

echo "==> Assemblage du bundle"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icône"
swift "$ROOT/Tools/make-icon.swift" "$DIST/AppIcon.iconset"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

echo "==> Signature ad-hoc"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> Archive"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME-$VERSION.zip"

echo
echo "OK  -> $APP"
echo "OK  -> $DIST/$NAME-$VERSION.zip"
