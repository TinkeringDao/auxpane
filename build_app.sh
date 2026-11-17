#!/bin/zsh
# SPDX-License-Identifier: MIT
# Build StretchTheMac.app (menu bar & window app) and the dockctl CLI into ./dist.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP="dist/StretchTheMac.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/StretchTheMac" "$APP/Contents/MacOS/StretchTheMac"
cp "$BIN/dockctl" dist/dockctl

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Stretch the Mac</string>
	<key>CFBundleDisplayName</key><string>Stretch the Mac</string>
	<key>CFBundleIdentifier</key><string>io.github.tinkeringdao.stretch-the-mac</string>
	<key>CFBundleExecutable</key><string>StretchTheMac</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 TinkeringDao. MIT License.</string>
</dict>
</plist>
PLIST

SIGN_ID="-"
codesign --force --sign "$SIGN_ID" "$APP"
codesign --force --sign "$SIGN_ID" dist/dockctl
echo "signed with: $SIGN_ID"
echo "built: $APP and dist/dockctl"
