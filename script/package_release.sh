#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexHistorySync"
APP_VERSION="0.1.4"
BUNDLE_ID="com.hanshuheng.CodexHistorySync"
MINIMUM_MACOS="13.0"
APP="$ROOT/dist/$APP_NAME.app"
ARCHIVE="$ROOT/dist/$APP_NAME.dmg"
ARM_BUILD="$ROOT/.build/release-arm64"
INTEL_BUILD="$ROOT/.build/release-x86_64"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

cd "$ROOT"
export SWIFT_MODULECACHE_PATH="$ROOT/.build/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
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
  codesign --force --entitlements "$ROOT/macos/CodexHistorySync.entitlements" --sign - "$APP"
else
  codesign --force --options runtime --timestamp --entitlements "$ROOT/macos/CodexHistorySync.entitlements" --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
DMG_WORK="$(mktemp -d)"
DMG_ROOT="$DMG_WORK/root"
RW_ARCHIVE="$DMG_WORK/$APP_NAME.rw.dmg"
ATTACH_PLIST="$DMG_WORK/attach.plist"
BACKGROUND="$ROOT/script/dmg_background.png"
VOLUME_NAME="$APP_NAME $APP_VERSION"
MOUNT_POINT=""
cleanup() {
  [[ -z "$MOUNT_POINT" ]] || hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rm -rf "$DMG_WORK"
}
trap cleanup EXIT
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
mkdir -p "$DMG_ROOT/.background"
cp "$BACKGROUND" "$DMG_ROOT/.background/background.png"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$DMG_ROOT" -ov -format UDRW "$RW_ARCHIVE"
hdiutil attach -plist "$RW_ARCHIVE" -nobrowse -noautoopen > "$ATTACH_PLIST"
for index in 0 1 2 3 4; do
  MOUNT_POINT="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$ATTACH_PLIST" 2>/dev/null || true)"
  [[ -n "$MOUNT_POINT" ]] && break
done
[[ -n "$MOUNT_POINT" ]] || { echo "无法找到 DMG 挂载点。" >&2; exit 2; }
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 900, 600}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" to {220, 260}
    set position of item "Applications" to {680, 260}
    close container window
  end tell
end tell
APPLESCRIPT
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""
hdiutil convert "$RW_ARCHIVE" -format UDZO -o "$ARCHIVE" -ov >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ "$SIGNING_IDENTITY" != "-" ]] || { echo "公证需要 SIGNING_IDENTITY。" >&2; exit 2; }
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$ARCHIVE"
  spctl --assess --type open --verbose=4 "$ARCHIVE"
fi

echo "发布包：$APP"
echo "磁盘映像：$ARCHIVE"
