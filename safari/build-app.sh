#!/bin/bash
# Builds "Reddit Enhancement Suite.app", the Mac app that carries RES as a
# Safari web extension, and signs it with the Developer ID.
#
#   safari/build-app.sh                       build and sign
#   safari/build-app.sh --notarize            ...then notarise and staple
#   safari/build-app.sh --notarize --install  ...then put it in /Applications and open it
#
# Safari drops a Developer ID extension that is not notarised, so an app meant
# for Safari needs --notarize. Notarisation uses a notarytool keychain profile:
#   xcrun notarytool store-credentials <profile> --apple-id ... --team-id ...
# named by RES_NOTARY_PROFILE (default rewired-notary). RES_SIGN_ID picks the
# signing certificate by SHA-1; by default it is the Developer ID Application
# certificate that expires last.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$ROOT/dist/safari-app"
NAME="Reddit Enhancement Suite"
APP="$B/$NAME.app"
APPEX="$APP/Contents/PlugIns/$NAME Extension.appex"
APP_ID="${RES_APP_ID:-hu.triglavmodular.RES}"
EXT_ID="$APP_ID.Extension"
MIN_MACOS="13.5"
PROFILE="${RES_NOTARY_PROFILE:-rewired-notary}"
VERSION="$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/package.json")"

NOTARIZE=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=1 ;;
        --install) INSTALL=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
if [ "$INSTALL" = 1 ] && [ "$NOTARIZE" = 0 ]; then
    echo "--install needs --notarize: Safari drops an extension that is not notarised." >&2
    exit 2
fi

IDENTITY="${RES_SIGN_ID:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Developer ID Application/ {print $2}' \
        | while read -r h; do
              end=$(security find-certificate -a -Z -p -c "Developer ID Application" 2>/dev/null \
                    | awk -v h="$h" '/SHA-1 hash:/ { want = ($3 == h) } /BEGIN CERT/,/END CERT/ { if (want) print }' \
                    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
              [ -n "$end" ] && printf '%s\t%s\n' "$(date -j -f '%b %e %T %Y %Z' "$end" +%s 2>/dev/null || echo 0)" "$h"
          done | sort -rn | head -1 | cut -f2)"
fi
[ -n "$IDENTITY" ] || { echo "No 'Developer ID Application' certificate in the keychain." >&2; exit 1; }

echo "== extension"
cd "$ROOT"
corepack yarn build --browsers safari
rm -rf "$B"
mkdir -p "$B/obj" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
# The extension's files, without source maps.
rsync -a --exclude '*.map' "$ROOT/dist/safari/" "$APPEX/Contents/Resources/"

echo "== icon"
ICONSET="$B/obj/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/images/icon512.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    if [ "$double" -le 512 ]; then
        sips -z "$double" "$double" "$ROOT/images/icon512.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

echo "== compile"
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" -parse-as-library -application-extension \
        -module-name RESExtension "$ROOT/safari/app/Handler.swift" \
        -Xlinker -e -Xlinker _NSExtensionMain -o "$B/obj/ext-$arch"
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" -module-name RES \
        "$ROOT/safari/app/App.swift" -o "$B/obj/app-$arch"
done
lipo -create "$B/obj/ext-arm64" "$B/obj/ext-x86_64" -output "$APPEX/Contents/MacOS/$NAME Extension"
lipo -create "$B/obj/app-arm64" "$B/obj/app-x86_64" -output "$APP/Contents/MacOS/$NAME"

set_key() { /usr/bin/plutil -insert "$2" "-$3" "$4" "$1"; }

P="$APPEX/Contents/Info.plist"
/usr/bin/plutil -create xml1 "$P"
set_key "$P" CFBundleIdentifier string "$EXT_ID"
set_key "$P" CFBundleExecutable string "$NAME Extension"
set_key "$P" CFBundleName string "$NAME Extension"
set_key "$P" CFBundleDisplayName string "$NAME"
set_key "$P" CFBundlePackageType string 'XPC!'
set_key "$P" CFBundleShortVersionString string "$VERSION"
set_key "$P" CFBundleVersion string "$VERSION"
set_key "$P" CFBundleInfoDictionaryVersion string "6.0"
set_key "$P" LSMinimumSystemVersion string "$MIN_MACOS"
set_key "$P" NSExtension json '{"NSExtensionPointIdentifier":"com.apple.Safari.web-extension","NSExtensionPrincipalClass":"SafariWebExtensionHandler"}'

P="$APP/Contents/Info.plist"
/usr/bin/plutil -create xml1 "$P"
set_key "$P" CFBundleIdentifier string "$APP_ID"
set_key "$P" CFBundleExecutable string "$NAME"
set_key "$P" CFBundleName string "$NAME"
set_key "$P" CFBundleDisplayName string "$NAME"
set_key "$P" NSHumanReadableCopyright string "Reddit Enhancement Suite contributors. GPL-3.0."
set_key "$P" CFBundlePackageType string APPL
set_key "$P" CFBundleShortVersionString string "$VERSION"
set_key "$P" CFBundleVersion string "$VERSION"
set_key "$P" CFBundleInfoDictionaryVersion string "6.0"
set_key "$P" CFBundleIconFile string AppIcon
set_key "$P" LSMinimumSystemVersion string "$MIN_MACOS"
set_key "$P" LSApplicationCategoryType string public.app-category.utilities
set_key "$P" NSPrincipalClass string NSApplication
set_key "$P" NSHighResolutionCapable bool true

echo "== sign"
ENT="$B/obj/sandbox.entitlements"
cat > "$ENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
EOF
# Safari refuses an extension that is not sandboxed, and notarisation refuses
# get-task-allow, so the entitlements are exactly the sandbox.
codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$APPEX"
codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"
echo "signed: $APP"

[ "$NOTARIZE" = 1 ] || exit 0

echo "== notarise"
ZIP="$B/obj/RES.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
out="$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1)" || { printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out"
case "$out" in *"status: Accepted"*) ;; *) echo "Not accepted." >&2; exit 1 ;; esac
xcrun stapler staple "$APP"
spctl -a -vv -t exec "$APP"
rm -f "$ZIP"

[ "$INSTALL" = 1 ] || exit 0

echo "== install"
DEST="/Applications/$NAME.app"
if [ -d "$DEST" ]; then
    osascript -e "tell application id \"$APP_ID\" to quit" >/dev/null 2>&1 || true
    rm -rf "$DEST"
fi
ditto "$APP" "$DEST"
open "$DEST"
echo "installed: $DEST"
