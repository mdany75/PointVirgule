#!/bin/bash
# Construit PointVirgule.app (Apple Silicon + Intel) et l'image disque à distribuer.
# Requiert seulement les outils de ligne de commande d'Apple : xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PointVirgule"
BUNDLE_ID="com.danymenard.PointVirgule"
MIN_MACOS="13.0"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
DMG="$BUILD/$APP_NAME.dmg"

rm -rf "$BUILD"
mkdir -p "$BUILD/obj" "$APP/Contents/MacOS" "$APP/Contents/Resources/fr.lproj"

echo "› Tests"
swiftc -swift-version 5 Sources/KeyRemapper.swift Tests/main.swift -o "$BUILD/obj/tests"
"$BUILD/obj/tests"

echo "› Compilation"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" \
    Sources/*.swift -o "$BUILD/obj/$APP_NAME-$arch"
done
lipo -create "$BUILD/obj/$APP_NAME-arm64" "$BUILD/obj/$APP_NAME-x86_64" \
  -output "$APP/Contents/MacOS/$APP_NAME"

echo "› Icône"
swiftc -swift-version 5 scripts/make_icon.swift -o "$BUILD/obj/make_icon"
"$BUILD/obj/make_icon" "$BUILD/obj/AppIcon.iconset"
iconutil -c icns "$BUILD/obj/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "› Signature"
# Signature locale (ad hoc). Avec un compte Apple Developer, remplacer « - » par
# l'identité « Developer ID Application: … », puis notariser l'image disque.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "› Image disque"
STAGING="$BUILD/obj/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
cp Resources/Lisez-moi.txt "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"

rm -rf "$BUILD/obj"
echo "✓ $APP"
echo "✓ $DMG"
