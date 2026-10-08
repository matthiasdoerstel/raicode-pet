#!/bin/bash
# Builds RaicodePet.app (ad-hoc signed) and installs it to /Applications.
# Usage: ./build_app.sh            build + install
#        ./build_app.sh --no-install
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=$(swift build -c release --show-bin-path)/RaicodePet
APP=build/RaicodePet.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RaicodePet"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Compile an asset catalog too — Notification Center on recent macOS resolves the
# icon via CFBundleIconName/Assets.car and shows a blank tile with only an .icns.
XCA=build/Assets.xcassets
SET=$XCA/AppIcon.appiconset
rm -rf build/AppIcon.iconset "$XCA"
iconutil -c iconset Resources/AppIcon.icns -o build/AppIcon.iconset
mkdir -p "$SET"
cp build/AppIcon.iconset/*.png "$SET/"
echo '{"info":{"author":"xcode","version":1}}' > "$XCA/Contents.json"
cat > "$SET/Contents.json" <<JSON
{"images":[
  {"idiom":"mac","size":"16x16","scale":"1x","filename":"icon_16x16.png"},
  {"idiom":"mac","size":"16x16","scale":"2x","filename":"icon_16x16@2x.png"},
  {"idiom":"mac","size":"32x32","scale":"1x","filename":"icon_32x32.png"},
  {"idiom":"mac","size":"32x32","scale":"2x","filename":"icon_32x32@2x.png"},
  {"idiom":"mac","size":"128x128","scale":"1x","filename":"icon_128x128.png"},
  {"idiom":"mac","size":"128x128","scale":"2x","filename":"icon_128x128@2x.png"},
  {"idiom":"mac","size":"256x256","scale":"1x","filename":"icon_256x256.png"},
  {"idiom":"mac","size":"256x256","scale":"2x","filename":"icon_256x256@2x.png"},
  {"idiom":"mac","size":"512x512","scale":"1x","filename":"icon_512x512.png"},
  {"idiom":"mac","size":"512x512","scale":"2x","filename":"icon_512x512@2x.png"}
],"info":{"author":"xcode","version":1}}
JSON
xcrun actool "$XCA" --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist build/actool-info.plist >/dev/null
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.matthias.raicodepet</string>
  <key>CFBundleName</key><string>Raicode Pet</string>
  <key>CFBundleDisplayName</key><string>Raicode Pet</string>
  <key>CFBundleExecutable</key><string>RaicodePet</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null

if [[ "${1:-}" != "--no-install" ]]; then
  mkdir -p /Applications
  pkill -x RaicodePet 2>/dev/null || true
  rm -rf /Applications/RaicodePet.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/RaicodePet.app"
fi
