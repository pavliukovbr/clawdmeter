#!/bin/sh
# Wrap Clawdmeter.app in a Debian package a jailbroken iPhone can install from Cydia.
#
#   ./package.sh          build the app if it is not there yet, then the .deb
#   ./package.sh clean    throw away the packaging leftovers
#
# The archive is put together by hand with ar and tar, since macOS ships no dpkg. A .deb
# is an ar archive holding three members in this order: debian-binary, control.tar.gz
# and data.tar.gz. That is all this makes. When dpkg-deb happens to be on the machine it
# is used at the end to read the result back, as a second opinion, never to write it.
#
# Everything lands in ./build, which git ignores.
set -e

# The version, in one place. Bump this line and nothing else.
VERSION=1.0.0

PACKAGE=com.pavliukovbr.clawdmeter
REPO=https://github.com/pavliukovbr/clawdmeter

HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/build"
APP="$BUILD/Clawdmeter.app"
STAGE="$BUILD/deb"
DEB="$BUILD/Clawdmeter_${VERSION}_iphoneos-arm.deb"

if [ "$1" = "clean" ]; then
    rm -rf "$STAGE" "$BUILD"/Clawdmeter_*_iphoneos-arm.deb
    echo "cleaned"
    exit 0
fi

command -v ar >/dev/null || { echo "ar is missing; install the Xcode command line tools"; exit 1; }

# 1. The app itself. build.sh already knows when there is nothing to do.
[ -d "$APP" ] || "$HERE/build.sh"

# BSD tar and GNU tar spell the ownership override differently, and only BSD tar has to
# be told to leave the Finder metadata out.
if tar --version 2>/dev/null | grep -qi bsdtar; then
    OWNED="--uid 0 --gid 0 --uname root --gname wheel --no-mac-metadata"
else
    OWNED="--owner=root:0 --group=wheel:0"
fi
COPYFILE_DISABLE=1
export COPYFILE_DISABLE

# 2. The payload, laid out the way it will sit on the phone.
rm -rf "$STAGE"
mkdir -p "$STAGE/data/Applications" "$STAGE/control"
cp -R "$APP" "$STAGE/data/Applications/Clawdmeter.app"

# Anything the Mac left behind is not part of the app.
find "$STAGE/data" -name '.DS_Store' -delete
if command -v xattr >/dev/null; then
    xattr -cr "$STAGE/data"
fi

# The settings file is somebody's own PC address and key. It is never shipped: the phone
# asks for those on a long press.
rm -f "$STAGE/data/Applications/Clawdmeter.app/Settings.plist"

find "$STAGE/data" -type d -exec chmod 755 {} +
find "$STAGE/data" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/data/Applications/Clawdmeter.app/Clawdmeter"

SIZE_KB=$(du -sk "$STAGE/data" | cut -f1)

# 3. The control file. Description continuation lines start with one space, and a lone
# dot on a spaced line is how a blank line is written in there.
cat > "$STAGE/control/control" <<CONTROL
Package: $PACKAGE
Name: Clawdmeter
Version: $VERSION
Architecture: iphoneos-arm
Depends: uikittools
Section: Utilities
Priority: optional
Installed-Size: $SIZE_KB
Author: pavliukovbr
Maintainer: pavliukovbr
Homepage: $REPO
Depiction: $REPO/tree/main/oldphone
Description: Claude plan usage on a phone you stopped using
 Stand a retired iPhone on your desk and it turns into a little dashboard: the big
 percentage, which limit it is, how long until it resets, the bars and the day total.
 Clawd walks along the bottom of the screen, carries a laptop while Claude types, a
 book while it reads, a hard hat while it builds, and curls up for a nap when nothing
 is happening.
 .
 The numbers come from the Clawdmeter app on your PC over your own network, so the
 phone never signs in to anything. Open it, hold a finger on the screen and type the
 address of the PC and the key.
 .
 Built for armv7 and iOS 9, so an iPhone 4S, a 4 or a 3GS is enough.
CONTROL

# 4. What dpkg runs on the phone, before and after.
cat > "$STAGE/control/postinst" <<'POSTINST'
#!/bin/sh
# Tell SpringBoard there is a new app, so the icon turns up without a respring.
if [ -x /usr/bin/uicache ]; then
    /usr/bin/uicache -p /Applications/Clawdmeter.app >/dev/null 2>&1 || /usr/bin/uicache >/dev/null 2>&1
fi
exit 0
POSTINST

cat > "$STAGE/control/prerm" <<'PRERM'
#!/bin/sh
# dpkg runs this before it takes the files away, on an upgrade as well as on a removal,
# so only a real removal gets to clear anything out.
case "$1" in
    remove|purge)
        killall -9 Clawdmeter >/dev/null 2>&1
        # The app writes what you typed on the phone here, and install.sh used to leave a
        # Settings.plist inside the bundle. Neither belongs to the package, so dpkg would
        # walk past both and leave the folder standing.
        rm -f /var/mobile/Library/Preferences/com.clawdmeter.oldphone.plist
        rm -rf /Applications/Clawdmeter.app
        if [ -x /usr/bin/uicache ]; then
            /usr/bin/uicache >/dev/null 2>&1
        fi
        ;;
esac
exit 0
PRERM

chmod 644 "$STAGE/control/control"
chmod 755 "$STAGE/control/postinst" "$STAGE/control/prerm"

# 5. The three members, then the archive. Root owns everything inside, group wheel, the
# way the phone wants it, whoever happens to be running this.
printf '2.0\n' > "$STAGE/debian-binary"

(cd "$STAGE/control" && tar $OWNED --format ustar -czf "$STAGE/control.tar.gz" ./control ./postinst ./prerm)
(cd "$STAGE/data" && tar $OWNED --format ustar -czf "$STAGE/data.tar.gz" ./Applications)

rm -f "$DEB"
# q appends in the order given, c keeps quiet about making a new archive, S leaves out
# the symbol table that BSD ar would otherwise put in front of debian-binary.
(cd "$STAGE" && ar -q -c -S "$DEB" debian-binary control.tar.gz data.tar.gz)

# 6. Proof it is what it claims to be.
echo
echo "members:"
ar t "$DEB" | sed 's/^/  /'
echo
echo "control:"
sed 's/^/  /' "$STAGE/control/control"
echo
echo "payload:"
tar -tvzf "$STAGE/data.tar.gz" | sed 's/^/  /'

if command -v dpkg-deb >/dev/null; then
    echo
    echo "dpkg-deb reads it back:"
    dpkg-deb -I "$DEB" | sed -n '1,3p' | sed 's/^/  /'
fi

echo
echo "size: $(du -h "$DEB" | cut -f1)"
echo "built $DEB"
