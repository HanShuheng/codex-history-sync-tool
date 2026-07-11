#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexHistorySync"
BUNDLE_ID="com.godgod126.CodexHistorySync"
MINIMUM_MACOS="13.0"
APP="$ROOT/dist/$APP_NAME.app"
ARCHIVE="$ROOT/dist/$APP_NAME.zip"
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

/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleExecutable string $APP_NAME" \
  -c "Add :CFBundleIdentifier string $BUNDLE_ID" \
  -c "Add :CFBundleName string Codex History Sync" \
  -c "Add :CFBundleDisplayName string Codex History Sync" \
  -c "Add :CFBundleDevelopmentRegion string en" \
  -c "Add :CFBundleLocalizations array" \
  -c "Add :CFBundleLocalizations:0 string en" \
  -c "Add :CFBundleLocalizations:1 string zh-Hans" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :LSHasLocalizedDisplayName bool true" \
  -c "Add :LSMinimumSystemVersion string $MINIMUM_MACOS" \
  -c "Add :NSPrincipalClass string NSApplication" \
  -c "Add :CFBundleIconFile string AppIcon" \
  "$APP/Contents/Info.plist"

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
ditto -c -k --keepParent "$APP" "$ARCHIVE"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ "$SIGNING_IDENTITY" != "-" ]] || { echo "公证需要 SIGNING_IDENTITY。" >&2; exit 2; }
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ARCHIVE"
  spctl --assess --type execute --verbose=4 "$APP"
fi

echo "发布包：$APP"
echo "压缩包：$ARCHIVE"
