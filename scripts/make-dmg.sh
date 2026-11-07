#!/bin/bash
# Builds a drag-to-install DMG: dist/Wasevo-Cleaner-<version>.dmg
# Branded background, the app on the left, Applications on the right.
# Usage: scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 '^VERSION=' scripts/build-app.sh | cut -d'"' -f2)
NAME="Wasevo Cleaner"
APP="dist/$NAME.app"
DMG="dist/Wasevo-Cleaner-$VERSION.dmg"
STAGE="build/dmg-stage"
RW="build/dmg-rw.dmg"

[ -d "$APP" ] || scripts/build-app.sh
swift scripts/make-dmg-background.swift build/dmg >/dev/null

rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# one HiDPI-aware background (1x + 2x)
tiffutil -cathidpicheck build/dmg/background.png build/dmg/background@2x.png -out "$STAGE/.background/background.tiff" >/dev/null
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

hdiutil create -quiet -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW -size 200m "$RW"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
MNT="/Volumes/$NAME"
sleep 1
# custom volume icon
SetFile -a C "$MNT" 2>/dev/null || true

# window layout (Finder draws the background and places the icons)
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 568}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:background.tiff"
    set position of item "$NAME.app" of container window to {170, 210}
    set position of item "Applications" of container window to {490, 210}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach -quiet "$DEV"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"
echo "✓ $DMG"
