#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexHistorySync"
APP="$ROOT/dist/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
cd "$ROOT"
swift build
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build --show-bin-path)/$APP_NAME" "$BIN"
cp history_manager.py sync_backend.py "$APP/Contents/"
RESOURCE_BUNDLE="$(swift build --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  rm -rf "$APP/Contents/Resources"
  mkdir -p "$APP/Contents/Resources"
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi
chmod +x "$BIN"
/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" -c "Add :CFBundleIdentifier string com.godgod126.CodexHistorySync" -c "Add :CFBundleName string $APP_NAME" -c "Add :CFBundlePackageType string APPL" -c "Add :LSMinimumSystemVersion string 13.0" -c "Add :NSPrincipalClass string NSApplication" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
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

case "$MODE" in
  run) open -n "$APP" ;;
  --debug|debug) lldb -- "$BIN" ;;
  --logs|logs) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate "process == '$APP_NAME'" ;;
  --verify|verify) open -n "$APP"; sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "用法: $0 [run|--debug|--logs|--verify]" >&2; exit 2 ;;
esac
