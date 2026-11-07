#!/bin/bash
# Builds "Wasevo Cleaner.app" into ./dist and (optionally) installs it to ~/Applications.
# Usage: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.4.0"
APP="dist/Wasevo Cleaner.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WasevoCleaner"

if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/make-icon.swift
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WasevoCleaner"
cp Resources/AppIcon.icns Resources/wasevo-logo.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Wasevo Cleaner</string>
  <key>CFBundleDisplayName</key><string>Wasevo Cleaner</string>
  <key>CFBundleIdentifier</key><string>com.wasevo.cleaner</string>
  <key>CFBundleExecutable</key><string>WasevoCleaner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>© Wasevo · Built by Waqas Ahmed Waseer, CEO of Wasevo · MIT License</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# Ad-hoc signature with a STABLE identity (the bundle id) instead of the default per-build hash,
# so macOS remembers your "Allow" answers across rebuilds instead of asking again every time.
codesign --force --deep -s - -r='designated => identifier "com.wasevo.cleaner"' "$APP"
echo "✓ built $APP"

if [ "${1:-}" = "--install" ]; then
  osascript -e 'quit app id "com.wasevo.cleaner"' 2>/dev/null || true
  sleep 1
  rm -rf "$HOME/Applications/Wasevo Cleaner.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "✓ installed to ~/Applications/Wasevo Cleaner.app"
  open "$HOME/Applications/Wasevo Cleaner.app"
fi
