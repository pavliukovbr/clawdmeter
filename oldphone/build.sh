#!/bin/sh
# Build Clawdmeter.app for an armv7 iPhone on iOS 9.
#
# Everything lands in ./build, which git ignores. The iOS 9.3 SDK is fetched once from
# the theos SDK mirror; Xcode has not shipped one since version 10.
#
#   ./build.sh          build
#   ./build.sh clean    throw away the build folder, SDK included
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/build"
MIRROR="$BUILD/sdks"
SDK="$BUILD/iPhoneOS9.3.sdk"
APP="$BUILD/Clawdmeter.app"
BIN="$APP/Clawdmeter"

if [ "$1" = "clean" ]; then
    rm -rf "$BUILD"
    echo "cleaned"
    exit 0
fi

command -v xcrun >/dev/null || { echo "xcrun is missing; install the Xcode command line tools"; exit 1; }
command -v ldid >/dev/null || { echo "ldid is missing; brew install ldid"; exit 1; }

mkdir -p "$BUILD"

# 1. The SDK. One sparse, blobless clone of the one version we want.
if [ ! -d "$SDK" ]; then
    echo "fetching the iOS 9.3 SDK, this happens once"
    rm -rf "$MIRROR"
    git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git "$MIRROR"
    git -C "$MIRROR" sparse-checkout set iPhoneOS9.3.sdk
    [ -d "$MIRROR/iPhoneOS9.3.sdk" ] || { echo "the mirror did not contain iPhoneOS9.3.sdk"; exit 1; }

    cp -R "$MIRROR/iPhoneOS9.3.sdk" "$SDK"
    rm -rf "$MIRROR"

    # The stub libraries claim simulator slices that this SDK does not actually carry,
    # and a current linker stops on them. Drop those two architectures from every stub.
    echo "patching the stub libraries"
    python3 "$HERE/Resources/striparchs.py" "$SDK"
fi

# 2. Compile and link. One translation unit per source, armv7, nothing newer than 9.0.
rm -rf "$APP"
mkdir -p "$APP"

xcrun clang \
    -target armv7-apple-ios9.0 \
    -isysroot "$SDK" \
    -fobjc-arc -fvisibility=hidden \
    -Wall -Wextra -Wno-unused-parameter -Werror=implicit-function-declaration \
    -Os \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -framework QuartzCore -framework AudioToolbox \
    -framework CFNetwork \
    "$HERE"/Clawdmeter/*.m \
    -o "$BIN"

# 3. Icons, drawn by a small script so the repository carries no binaries.
python3 "$HERE/Resources/mkicon.py" "$APP/AppIcon60x60@2x.png" 120
python3 "$HERE/Resources/mkicon.py" "$APP/AppIcon40x40@2x.png" 80
python3 "$HERE/Resources/mkicon.py" "$APP/AppIcon29x29@2x.png" 58

# 4. Info.plist. iOS 9 reads either form; binary is what a real bundle ships.
cp "$HERE/Resources/Info.plist" "$APP/Info.plist"
plutil -convert binary1 "$APP/Info.plist"

# 5. The ad hoc signature a jailbroken device expects.
ldid -S"$HERE/Resources/ent.xml" -Icom.clawdmeter.oldphone "$BIN"
chmod 755 "$BIN"

# 6. Proof it is what it claims to be.
echo
file "$BIN"
xcrun otool -l "$BIN" | grep -A3 LC_VERSION_MIN_IPHONEOS | head -5
python3 "$HERE/Resources/checksyms.py" "$SDK" "$BIN"
echo "app size: $(du -sh "$APP" | cut -f1)"
echo "built $APP"
