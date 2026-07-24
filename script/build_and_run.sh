#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexHistorySync"
APP_VERSION="0.1.3"
APP="$ROOT/dist/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
NEEDS_BUILD=true
if [[ -x "$BIN" ]] && ! find "$ROOT/macos" "$ROOT/Package.swift" "$ROOT/project.yml" -type f -newer "$BIN" -print -quit | grep -q .; then
  NEEDS_BUILD=false
fi

if [[ "$NEEDS_BUILD" == true ]]; then
  cd "$ROOT"
  swift build
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$(swift build --show-bin-path)/$APP_NAME" "$BIN"
  RESOURCE_BUNDLE="$(swift build --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"
  if [[ -d "$RESOURCE_BUNDLE" ]]; then
    rm -rf "$APP/Contents/Resources"
    mkdir -p "$APP/Contents/Resources"
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
  fi
  chmod +x "$BIN"
plutil -create xml1 "$APP/Contents/Info.plist"
add_plist() { /usr/libexec/PlistBuddy -c "$1" "$APP/Contents/Info.plist"; }
add_plist "Add :CFBundleExecutable string $APP_NAME"
add_plist "Add :CFBundleIdentifier string com.hanshuheng.CodexHistorySync"
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
add_plist "Add :LSMinimumSystemVersion string 13.0"
add_plist "Add :NSPrincipalClass string NSApplication"
add_plist "Add :CFBundleIconFile string AppIcon"
mkdir -p "$APP/Contents/Resources"
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
codesign --force --sign - "$APP"
fi

case "$MODE" in
  run) open -n "$APP" ;;
  --debug|debug) lldb -- "$BIN" ;;
  --logs|logs) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate "process == '$APP_NAME'" ;;
  --telemetry|telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate "subsystem == 'com.hanshuheng.CodexHistorySync'" ;;
  --verify|verify) open -n "$APP"; sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "用法: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
