#!/bin/bash
# Builds RaicodePet.app (ad-hoc signed) and installs it to ~/Applications.
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
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.matthias.raicode-pet</string>
  <key>CFBundleName</key><string>Raicode Pet</string>
  <key>CFBundleDisplayName</key><string>Raicode Pet</string>
  <key>CFBundleExecutable</key><string>RaicodePet</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
  mkdir -p ~/Applications
  pkill -x RaicodePet 2>/dev/null || true
  rm -rf ~/Applications/RaicodePet.app
  cp -R "$APP" ~/Applications/
  echo "Installed ~/Applications/RaicodePet.app"
fi
