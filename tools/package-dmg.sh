#!/usr/bin/env bash
# Builds a Release Haku.app and wraps it in a styled drag-to-install Haku.dmg at the repo root.
# The window art is tools/dmg/background*.png, rendered by PromoImageTests/testRenderDMGBackground.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="build/DerivedData"
STAGE="build/dmg"
RW="build/Haku-rw.dmg"
APP="$DERIVED/Build/Products/Release/Haku.app"
ICONSET="Haku/Resources/Assets.xcassets/AppIcon.appiconset"
DMG="Haku.dmg"
VOL="Haku"
MNT="/Volumes/$VOL"

xcodebuild -project Haku.xcodeproj -scheme Haku -configuration Release \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates build | tail -n 3

codesign --verify --deep --strict "$APP"

rm -rf "$STAGE" "$RW"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Haku.app"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck tools/dmg/background.png tools/dmg/background@2x.png -out "$STAGE/.background/background.tiff"

ICNS_DIR="build/VolumeIcon.iconset"
rm -rf "$ICNS_DIR" && mkdir -p "$ICNS_DIR"
cp "$ICONSET"/icon_*.png "$ICNS_DIR/"
iconutil -c icns "$ICNS_DIR" -o "$STAGE/.VolumeIcon.icns"

[ -d "$MNT" ] && hdiutil detach "$MNT" -force -quiet || true
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" -quiet
hdiutil attach "$RW" -readwrite -noverify -noautoopen -quiet

osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Haku"
    open
    set w to container window
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 120, 860, 548}
    set opts to icon view options of w
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Haku.app" of w to {170, 196}
    set position of item "Applications" of w to {490, 196}
    update without registering applications
  end tell
end tell
APPLESCRIPT

# Finder saves the layout while the window is open but resets the view options when it closes
# or unmounts, so snapshot the good .DS_Store, then write it back with the image hidden from Finder.
for _ in $(seq 40); do
  grep -q backgroundImageAlias "$MNT/.DS_Store" 2>/dev/null && grep -q Iloc "$MNT/.DS_Store" && break
  sleep 0.5
done
grep -q backgroundImageAlias "$MNT/.DS_Store" || { echo "Finder didn't save the window layout" >&2; exit 1; }
sleep 1
cp "$MNT/.DS_Store" build/DS_Store.layout
osascript -e 'tell application "Finder" to close container window of disk "Haku"'
hdiutil detach "$MNT" -quiet

hdiutil attach "$RW" -readwrite -noverify -noautoopen -nobrowse -quiet
cp build/DS_Store.layout "$MNT/.DS_Store"
cp "$STAGE/.VolumeIcon.icns" "$MNT/.VolumeIcon.icns"
SetFile -a C "$MNT"
rm -rf "$MNT/.fseventsd" "$MNT/.Trashes"
sync
hdiutil detach "$MNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" -quiet
rm -f "$RW"
echo "Created $ROOT/$DMG"
