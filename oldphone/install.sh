#!/bin/sh
# Put Clawdmeter.app on a jailbroken iPhone over SSH and tell it where the PC is.
#
#   ./install.sh root@192.168.1.31 192.168.1.20:47848 mykey
#
# or with the environment instead of arguments:
#
#   PHONE=root@192.168.1.31 PC=192.168.1.20:47848 KEY=mykey ./install.sh
#
# The phone needs a jailbreak with OpenSSH from Cydia. Nothing is stored in this script.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
APP="$HERE/build/Clawdmeter.app"

PHONE=${1:-$PHONE}
PC=${2:-$PC}
KEY=${3:-$KEY}

if [ -z "$PHONE" ]; then
    echo "usage: $0 user@phone [pc-address[:port]] [key]"
    echo "       PHONE, PC and KEY work as environment variables too"
    exit 1
fi

[ -d "$APP" ] || { echo "no build yet, run ./build.sh first"; exit 1; }

# The settings the app reads on launch. Left out of the repository on purpose: the
# address of somebody's PC and the key to it are not source code.
if [ -n "$PC" ]; then
    cat > "$APP/Settings.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>address</key>
	<string>$PC</string>
	<key>key</key>
	<string>$KEY</string>
</dict>
</plist>
PLIST
    echo "settings point at $PC"
else
    echo "no PC address given, hold a finger on the screen to type one on the phone"
fi

echo "copying to $PHONE"
ssh "$PHONE" 'rm -rf /Applications/Clawdmeter.app'
scp -r "$APP" "$PHONE:/Applications/"

ssh "$PHONE" '
  chown -R root:wheel /Applications/Clawdmeter.app
  find /Applications/Clawdmeter.app -type d -exec chmod 755 {} +
  find /Applications/Clawdmeter.app -type f -exec chmod 644 {} +
  chmod 755 /Applications/Clawdmeter.app/Clawdmeter
  uicache
'

echo "installed. If the icon does not show up: ssh $PHONE killall -9 SpringBoard"
