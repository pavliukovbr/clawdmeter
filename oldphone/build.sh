#!/bin/sh
# Build Clawdmeter.app for an armv7 iPhone, iOS 8.0 and up.
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

# 2. Compile, then link. The two steps are separate on purpose: the driver asks for
#    libarclite when ARC and linking meet on one command line with a deployment target
#    this old, and no toolchain has shipped that library for years. Building against
#    8.0 is also what makes clang refuse anything the 9.3 headers mark as newer.
rm -rf "$APP" "$BUILD/obj"
mkdir -p "$APP" "$BUILD/obj"

for SOURCE in "$HERE"/Clawdmeter/*.m; do
    NAME=$(basename "$SOURCE" .m)
    # ARM only, no Thumb. Today's linker gets the switch between the two wrong on armv7,
    # so the whole app stays in one instruction set and never has to switch.
    xcrun clang -c \
        -target armv7-apple-ios8.0 \
        -marm \
        -isysroot "$SDK" \
        -fobjc-arc -fvisibility=hidden \
        -Wall -Wextra -Wno-unused-parameter -Werror=implicit-function-declaration \
        -Werror=unguarded-availability -Werror=unguarded-availability-new \
        -Os \
        "$SOURCE" -o "$BUILD/obj/$NAME.o"
done

xcrun clang \
    -target armv7-apple-ios8.0 \
    -isysroot "$SDK" \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -framework QuartzCore -framework AudioToolbox \
    -framework CFNetwork \
    "$BUILD"/obj/*.o \
    -o "$BIN"

# 3. Refuse to ship a binary with any Thumb code in it, since that is what crashed.
if nm -m "$BIN" | grep -q "\[Thumb\]"; then
    echo "Thumb code found in the binary, the old phone would crash on it"
    exit 1
fi

# 4. Icons, drawn by a small script so the repository carries no binaries.
python3 "$HERE/Resources/mkicon.py" "$APP/AppIcon60x60@2x.png" 120
python3 "$HERE/Resources/mkicon.py" "$APP/AppIcon40x40@2x.png" 80
python3 "$HERE/Resources/mkicon.py" "$APP/AppIcon29x29@2x.png" 58

# 5. Info.plist. iOS 9 reads either form; binary is what a real bundle ships.
cp "$HERE/Resources/Info.plist" "$APP/Info.plist"
plutil -convert binary1 "$APP/Info.plist"

# 6. The ad hoc signature a jailbroken device expects.
ldid -S"$HERE/Resources/ent.xml" -Icom.clawdmeter.oldphone "$BIN"
chmod 755 "$BIN"

# 7. Proof it is what it claims to be.
echo
file "$BIN"
xcrun otool -l "$BIN" | grep -A3 LC_VERSION_MIN_IPHONEOS | head -5
xcrun otool -l "$BIN" | grep -A2 LC_MAIN | head -3
python3 "$HERE/Resources/checksyms.py" "$SDK" "$BIN"
echo "app size: $(du -sh "$APP" | cut -f1)"
echo "built $APP"
