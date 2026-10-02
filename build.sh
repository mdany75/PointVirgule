#!/bin/bash
# Construit PointVirgule.app (Apple Silicon + Intel) et l'image disque à distribuer.
# Requiert seulement les outils de ligne de commande d'Apple : xcode-select --install
#
#   ./build.sh             construit build/PointVirgule.dmg
#   ./build.sh --install   construit, puis installe l'app dans /Applications et l'ouvre
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PointVirgule"
BUNDLE_ID="com.danymenard.PointVirgule"
MIN_MACOS="13.0"
DMG="build/$APP_NAME.dmg"

INSTALL=false
if [[ "${1:-}" == "--install" ]]; then
  INSTALL=true
elif [[ $# -gt 0 ]]; then
  echo "usage : ./build.sh [--install]" >&2
  exit 1
fi

# L'app est assemblée hors du dossier du projet : iCloud Drive ajoute aux dossiers
# des attributs que codesign refuse (« detritus not allowed »).
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fr.lproj"

echo "› Tests"
swiftc -swift-version 5 Sources/KeyRemapper.swift Sources/KeyboardLayout.swift Tests/main.swift -o "$WORK/tests"
"$WORK/tests"

echo "› Compilation"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" \
    Sources/*.swift -o "$WORK/$APP_NAME-$arch"
done
lipo -create "$WORK/$APP_NAME-arm64" "$WORK/$APP_NAME-x86_64" \
  -output "$APP/Contents/MacOS/$APP_NAME"

echo "› Icône"
swiftc -swift-version 5 scripts/make_icon.swift -o "$WORK/make_icon"
"$WORK/make_icon" "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "› Signature"
# Signature locale (ad hoc). Avec un compte Apple Developer, remplacer « - » par
# l'identité « Developer ID Application: … », puis notariser l'image disque.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "› Image disque"
STAGING="$WORK/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
cp Resources/Lisez-moi.txt "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO -quiet "$WORK/$APP_NAME.dmg"
rm -rf build
mkdir -p build
cp "$WORK/$APP_NAME.dmg" "$DMG"
echo "✓ $DMG"

if $INSTALL; then
  echo "› Installation"
  INSTALLED="/Applications/$APP_NAME.app"
  pkill -x "$APP_NAME" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.5
  done
  rm -rf "$INSTALLED"
  ditto "$APP" "$INSTALLED"
  codesign --verify --strict "$INSTALLED"
  open "$INSTALLED"
  echo "✓ $INSTALLED"
  echo "  Après une mise à jour, macOS exige de redonner l'autorisation Accessibilité :"
  echo "  dans la fenêtre de PointVirgule, cliquez sur « Réinitialiser l'autorisation »."
fi
