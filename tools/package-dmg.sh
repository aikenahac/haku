#!/usr/bin/env bash
# Builds a Release Haku.app and wraps it in a drag-to-install Haku.dmg at the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="build/DerivedData"
STAGE="build/dmg"
APP="$DERIVED/Build/Products/Release/Haku.app"
DMG="Haku.dmg"

xcodebuild -project Haku.xcodeproj -scheme Haku -configuration Release \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates build | tail -n 5

codesign --verify --deep --strict "$APP"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Haku.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname Haku -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Created $ROOT/$DMG"
