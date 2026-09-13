#!/bin/sh
# Builds a universal Clawdmeter.app from the last commit and packs it for a GitHub release.
# The build happens in a temporary folder, so no local paths end up inside the app.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$ROOT/Clawdmeter.xcodeproj/project.pbxproj" | head -n 1)
WORK=$(mktemp -d /tmp/clawdmeter.XXXXXX)
OUT="$ROOT/dist"

git clone -q "$ROOT" "$WORK/src"
cd "$WORK/src"
xcodebuild -quiet -project Clawdmeter.xcodeproj -scheme Clawdmeter -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$WORK/build" \
    DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global build
APP="$WORK/build/Build/Products/Release/Clawdmeter.app"

mkdir -p "$OUT"
rm -f "$OUT/Clawdmeter.zip" "$OUT/Clawdmeter.zip.sha256" "$OUT/Clawdmeter.dmg"
(cd "$(dirname "$APP")" && zip -qry "$OUT/Clawdmeter.zip" Clawdmeter.app)
shasum -a 256 "$OUT/Clawdmeter.zip" | awk '{print $1}' > "$OUT/Clawdmeter.zip.sha256"

mkdir "$WORK/disk"
cp -R "$APP" "$WORK/disk/"
ln -s /Applications "$WORK/disk/Applications"
hdiutil create -quiet -volname Clawdmeter -srcfolder "$WORK/disk" -ov -format UDZO "$OUT/Clawdmeter.dmg"

rm -rf "$WORK"
echo "Clawdmeter $VERSION is ready in dist"
