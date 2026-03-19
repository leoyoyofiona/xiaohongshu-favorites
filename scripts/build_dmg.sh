#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="小红书收藏导航"
BUNDLE_NAME="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
APP_DIR="$DIST_DIR/$BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
RELEASE_BINARY="$BUILD_DIR/arm64-apple-macosx/release/XHSOrganizerApp"
STAGING_DIR="$DIST_DIR/dmg-staging"
ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
ICON_ICNS="$ROOT_DIR/Resources/AppIcon.icns"

echo "==> Building release binary"
cd "$ROOT_DIR"
python3 "$ROOT_DIR/scripts/generate_app_icon.py" >/dev/null
rm -f "$ICON_ICNS"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
swift build -c release --product XHSOrganizerApp

if [[ ! -x "$RELEASE_BINARY" ]]; then
  echo "Release binary not found: $RELEASE_BINARY" >&2
  exit 1
fi

echo "==> Preparing app bundle"
rm -rf "$APP_DIR" "$STAGING_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$STAGING_DIR"
cp "$RELEASE_BINARY" "$MACOS_DIR/XHSOrganizerApp"
chmod +x "$MACOS_DIR/XHSOrganizerApp"
cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"

cat > "$INFO_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>小红书收藏导航</string>
  <key>CFBundleExecutable</key>
  <string>XHSOrganizerApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.codex.xhsorganizer</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>小红书收藏导航</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing app bundle"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Preparing DMG staging"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME"

echo "==> Creating DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$DMG_NAME" >/dev/null

rm -rf "$STAGING_DIR"

echo "==> Done"
echo "$DIST_DIR/$DMG_NAME"
