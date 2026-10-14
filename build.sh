#!/bin/bash
# Builds Todaytape.app: a menu bar app with no Dock icon.
#
#   ./build.sh                  build for this Mac into build/Todaytape.app
#   ./build.sh --install        also copy it to /Applications and open it
#   ./build.sh --universal      Apple silicon + Intel binary
#   ./build.sh --release        universal, plus build/Todaytape-<version>.zip
#
# Needs only the Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Todaytape"
BUNDLE_ID="com.elliotkoh.todaytape"
VERSION="${TODAYTAPE_VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
BUILD_NUMBER="${TODAYTAPE_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE="build/${APP_NAME}.app"

INSTALL=0
UNIVERSAL=0
ZIP=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    --release) UNIVERSAL=1; ZIP=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

if ! command -v swift >/dev/null; then
  echo "Swift isn't installed. Run: xcode-select --install" >&2
  exit 1
fi

if [ "$UNIVERSAL" = 1 ]; then
  echo "Building ${APP_NAME} ${VERSION} for Apple silicon and Intel…"
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  BIN="build/${APP_NAME}-universal"
  mkdir -p build
  lipo -create -output "$BIN" \
    ".build/arm64-apple-macosx/release/${APP_NAME}" \
    ".build/x86_64-apple-macosx/release/${APP_NAME}"
else
  echo "Building ${APP_NAME} ${VERSION}…"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
fi

echo "Assembling ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/${APP_NAME}"
cp Resources/Todaytape.icns "$BUNDLE/Contents/Resources/Todaytape.icns"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>        <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>         <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>         <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>           <string>Todaytape</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>            <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>LSApplicationCategoryType</key>  <string>public.app-category.productivity</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSHumanReadableCopyright</key>   <string>Copyright © 2026 Elliot Koh. MIT License.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally. It is not notarised (see README).
codesign --force --deep --sign - "$BUNDLE"

if [ "$ZIP" = 1 ]; then
  ZIP_PATH="build/${APP_NAME}-${VERSION}.zip"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$BUNDLE" "$ZIP_PATH"
  shasum -a 256 "$ZIP_PATH" | tee "$ZIP_PATH.sha256"
fi

echo
echo "Built $BUNDLE ($(lipo -archs "$BUNDLE/Contents/MacOS/${APP_NAME}"))"

if [ "$INSTALL" = 1 ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$BUNDLE" /Applications/
  open "/Applications/${APP_NAME}.app"
  echo "Installed to /Applications and opened. Look for the calendar icon in your menu bar."
else
  echo "Run it:      open $BUNDLE"
  echo "Install it:  ./build.sh --install"
fi
