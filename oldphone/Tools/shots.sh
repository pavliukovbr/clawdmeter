#!/bin/sh
# Render the app screens to PNG files on this Mac, at the exact point size the phone uses.
#
#   ./Tools/shots.sh [output folder]
#
# It compiles the same sources for Mac Catalyst together with shots.m, which draws each
# state offscreen and writes a file. Nothing here touches the phone build: build.sh only
# ever compiles Clawdmeter/*.m, and main.m is left out of this one.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
WORK="$ROOT/build/shots"
OUT=${1:-$WORK/png}

SDK=$(xcrun --sdk macosx --show-sdk-path)
APP="$WORK/Shots.app"

mkdir -p "$OUT" "$APP/Contents/MacOS"

SOURCES=$(ls "$ROOT"/Clawdmeter/*.m | grep -v '/main\.m$')

xcrun clang \
    -target arm64-apple-ios14.0-macabi \
    -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -isystem "$SDK/System/iOSSupport/usr/include" \
    -I "$ROOT/Clawdmeter" \
    -fobjc-arc -Wall -Wno-deprecated-declarations -O0 \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -framework QuartzCore -framework AudioToolbox \
    $SOURCES "$HERE/shots.m" \
    -o "$APP/Contents/MacOS/Shots"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Shots</string>
	<key>CFBundleIdentifier</key><string>com.clawdmeter.oldphone.shots</string>
	<key>CFBundleName</key><string>Shots</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>LSBackgroundOnly</key><true/>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1

"$APP/Contents/MacOS/Shots" "$OUT"
echo "screens in $OUT"
