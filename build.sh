#!/bin/bash
# Construit PointVirgule.app (Apple Silicon + Intel) et l'image disque à distribuer.
# Requiert seulement les outils de ligne de commande d'Apple : xcode-select --install
#
#   ./build.sh             construit build/PointVirgule.dmg
#   ./build.sh --install   construit, puis installe l'app dans /Applications et l'ouvre
#
#   SIGN_IDENTITY="-"      signature ad hoc même si un certificat est présent
#   SKIP_NOTARIZE=1        signe avec le certificat mais ne notarise pas (essai rapide)
#   NOTARY_PROFILE=nom     profil de « xcrun notarytool store-credentials » (défaut : notarisation)
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

# --- Signature et notarisation ------------------------------------------------
#
# Avec le certificat « Developer ID Application » dans le trousseau, le code est signé avec
# le runtime durci, puis ce qui est distribué est notarisé chez Apple : il s'ouvre sans
# avertissement sur n'importe quel Mac, et macOS conserve les autorisations accordées d'une
# version à l'autre (l'identité ne change plus). Sans certificat (autre machine), signature
# ad hoc et pas de notarisation.

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarisation}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    SIGN_ARGS=(--sign -)
    NOTARIZE=0; NOTARIZE_WHY="signature ad hoc, aucun certificat Developer ID"
elif [[ "${SKIP_NOTARIZE:-0}" != "0" ]]; then
    SIGN_ARGS=(--options runtime --timestamp --sign "${SIGN_IDENTITY}")
    NOTARIZE=0; NOTARIZE_WHY="SKIP_NOTARIZE=1"
else
    SIGN_ARGS=(--options runtime --timestamp --sign "${SIGN_IDENTITY}")
    NOTARIZE=1; NOTARIZE_WHY=""
fi

# sign_code OPTIONS… CHEMIN : signe, puis vérifie. Le serveur d'horodatage d'Apple renvoie
# parfois une heure décalée de quelques minutes, que « codesign --verify --strict » refuse
# (« timestamps differ ») : on signe alors de nouveau, jusqu'à trois fois.
sign_code() {
    local attempt
    for attempt in 1 2 3; do
        codesign --force "$@"
        codesign --verify --deep --strict "${@:$#}" && return 0
        printf 'Vérification de la signature refusée (essai %s/3), nouvelle signature…\n' "${attempt}" >&2
        sleep 2
    done
    echo "Erreur : signature impossible à vérifier : ${@:$#}" >&2
    exit 1
}

# notarize_file FICHIER : soumet l'archive ou l'image disque à Apple et attend le verdict
# (quelques minutes).
notarize_file() {
    local file="$1" output id
    echo "› Notarisation de « $(basename "${file}") » (profil « ${NOTARY_PROFILE} »), quelques minutes"
    if ! output="$(xcrun notarytool submit "${file}" --keychain-profile "${NOTARY_PROFILE}" --wait 2>&1)"; then
        printf '%s\n' "${output}" >&2
        echo "Erreur : notarisation impossible : session verrouillée (le profil n'est lisible qu'écran déverrouillé) ou profil « ${NOTARY_PROFILE} » absent (xcrun notarytool store-credentials)." >&2
        exit 1
    fi
    printf '%s\n' "${output}"
    if ! grep -q '^ *status: Accepted' <<< "${output}"; then
        id="$(sed -n 's/^ *id: //p' <<< "${output}" | head -n 1)"
        [[ -z "${id}" ]] || xcrun notarytool log "${id}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
        echo "Erreur : notarisation refusée par Apple (détail ci-dessus)." >&2
        exit 1
    fi
}

# finalize_dmg FICHIER : signe l'image disque, la notarise, agrafe le ticket et vérifie que
# Gatekeeper l'accepte. Sans notarisation, dit seulement pourquoi.
finalize_dmg() {
    local dmg="$1"
    if [[ "${NOTARIZE}" -eq 0 ]]; then
        echo "› Image disque non notarisée (${NOTARIZE_WHY}) : avertissement de macOS sur un autre Mac"
        return 0
    fi
    sign_code --timestamp --sign "${SIGN_IDENTITY}" "${dmg}"
    notarize_file "${dmg}"
    echo "› Agrafage du ticket et vérification Gatekeeper"
    xcrun stapler staple "${dmg}"
    spctl -a -t open --context context:primary-signature -vv "${dmg}"
}

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

echo "› Signature ($SIGN_IDENTITY)"
sign_code "${SIGN_ARGS[@]}" --identifier "$BUNDLE_ID" "$APP"

echo "› Image disque"
STAGING="$WORK/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
cp Resources/Lisez-moi.txt "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO -quiet "$WORK/$APP_NAME.dmg"
finalize_dmg "$WORK/$APP_NAME.dmg"
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
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "  Signature ad hoc : macOS exige de redonner l'autorisation Accessibilité."
    echo "  Dans la fenêtre de PointVirgule, cliquez sur « Réinitialiser l'autorisation »."
  fi
fi
