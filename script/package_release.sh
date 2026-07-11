#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexHistorySync"
APP_VERSION="0.0.1"
BUNDLE_ID="com.hanshuheng.CodexHistorySync"
MINIMUM_MACOS="13.0"
APP="$ROOT/dist/$APP_NAME.app"
ARCHIVE="$ROOT/dist/$APP_NAME.dmg"
ARM_BUILD="$ROOT/.build/release-arm64"
INTEL_BUILD="$ROOT/.build/release-x86_64"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

cd "$ROOT"
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM_BUILD"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$INTEL_BUILD"

rm -rf "$APP" "$ARCHIVE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  "$ARM_BUILD/arm64-apple-macosx/release/$APP_NAME" \
  "$INTEL_BUILD/x86_64-apple-macosx/release/$APP_NAME" \
  -output "$APP/Contents/MacOS/$APP_NAME"

RESOURCE_BUNDLE="$ARM_BUILD/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

plutil -create xml1 "$APP/Contents/Info.plist"
add_plist() { /usr/libexec/PlistBuddy -c "$1" "$APP/Contents/Info.plist"; }
add_plist "Add :CFBundleExecutable string $APP_NAME"
add_plist "Add :CFBundleIdentifier string $BUNDLE_ID"
add_plist "Add :CFBundleName string Codex History Sync"
add_plist "Add :CFBundleDisplayName string Codex History Sync"
add_plist "Add :CFBundleShortVersionString string $APP_VERSION"
add_plist "Add :CFBundleVersion string $APP_VERSION"
add_plist "Add :CFBundleDevelopmentRegion string en"
add_plist "Add :CFBundleLocalizations array"
add_plist "Add :CFBundleLocalizations:0 string en"
add_plist "Add :CFBundleLocalizations:1 string zh-Hans"
add_plist "Add :CFBundlePackageType string APPL"
add_plist "Add :LSHasLocalizedDisplayName bool true"
add_plist "Add :LSMinimumSystemVersion string $MINIMUM_MACOS"
add_plist "Add :NSPrincipalClass string NSApplication"
add_plist "Add :CFBundleIconFile string AppIcon"

for strings in "$ROOT"/macos/Resources/*.lproj/InfoPlist.strings; do
  language="$(basename "$(dirname "$strings")")"
  mkdir -p "$APP/Contents/Resources/$language"
  cp "$strings" "$APP/Contents/Resources/$language/"
done

ICON_SOURCE="$ROOT/macos/Resources/Assets/AppIcon.png"
ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
hdiutil create -volname "$APP_NAME $APP_VERSION" -srcfolder "$APP" -ov -format UDZO "$ARCHIVE"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ "$SIGNING_IDENTITY" != "-" ]] || { echo "公证需要 SIGNING_IDENTITY。" >&2; exit 2; }
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$ARCHIVE"
  spctl --assess --type open --verbose=4 "$ARCHIVE"
fi

echo "发布包：$APP"
echo "磁盘映像：$ARCHIVE"
