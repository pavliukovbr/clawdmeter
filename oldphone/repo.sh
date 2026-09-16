#!/bin/sh
# Build the Cydia repository that lives in docs/cydia, so a phone can install Clawdmeter
# from Cydia instead of waiting for a Mac with SSH.
#
#   ./repo.sh
#
# It packages the app, drops the .deb in docs/cydia/debs, then writes the three files a
# Cydia source is made of: Packages, Packages.gz and Release, plus a page for anybody who
# opens the address in a browser. Everything it writes is small enough to keep in git,
# which is the point: GitHub Pages serves docs/ and that is the whole server.
#
# There is no signing key here. Cydia takes an unsigned source and says so once.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CYDIA="$ROOT/docs/cydia"
DEBS="$CYDIA/debs"

REPO=https://github.com/pavliukovbr/clawdmeter
SOURCE=https://pavliukovbr.github.io/clawdmeter/cydia/

# The version lives in package.sh and only there.
VERSION=$(sed -n 's/^VERSION=//p' "$HERE/package.sh" | head -1)
[ -n "$VERSION" ] || { echo "could not read VERSION out of package.sh"; exit 1; }

# Whatever is around: BSD and GNU name these differently.
sum_md5() {
    if command -v md5 >/dev/null; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi
}
sum_sha() {
    if command -v shasum >/dev/null; then
        shasum -a "$1" "$2" | cut -d' ' -f1
    else
        "sha$1sum" "$2" | cut -d' ' -f1
    fi
}

# 1. The package.
"$HERE/package.sh" >/dev/null
DEB="$HERE/build/Clawdmeter_${VERSION}_iphoneos-arm.deb"
[ -f "$DEB" ] || { echo "package.sh did not leave $DEB behind"; exit 1; }

mkdir -p "$DEBS"
cp "$DEB" "$DEBS/"

# 2. Packages. Every .deb in the folder gets a paragraph: its own control file, then
# where to find it and what it should hash to. Cydia refuses anything that does not match.
PACKAGES="$CYDIA/Packages"
: > "$PACKAGES"

count=0
for deb in "$DEBS"/*.deb; do
    [ -f "$deb" ] || continue
    [ "$count" -eq 0 ] || printf '\n' >> "$PACKAGES"
    count=$((count + 1))

    ar p "$deb" control.tar.gz | tar -xzO -f - ./control >> "$PACKAGES"
    {
        printf 'Filename: debs/%s\n' "$(basename "$deb")"
        printf 'Size: %s\n' "$(wc -c < "$deb" | tr -d ' ')"
        printf 'MD5sum: %s\n' "$(sum_md5 "$deb")"
        printf 'SHA1: %s\n' "$(sum_sha 1 "$deb")"
        printf 'SHA256: %s\n' "$(sum_sha 256 "$deb")"
    } >> "$PACKAGES"
done

[ "$count" -gt 0 ] || { echo "no .deb files to index"; exit 1; }

# n keeps the name and the timestamp out, so rebuilding the same package leaves the file
# byte for byte the same and git has nothing to record.
gzip -9 -n -c "$PACKAGES" > "$CYDIA/Packages.gz"

# 3. Release. What Cydia puts under the source name in the list.
cat > "$CYDIA/Release" <<RELEASE
Origin: Clawdmeter
Label: Clawdmeter
Suite: stable
Version: 1.0
Codename: clawdmeter
Architectures: iphoneos-arm
Components: main
Description: Clawd and your Claude plan usage on an iPhone that is too old for anything else
RELEASE

# 4. A page for whoever opens the address in a browser instead of in Cydia.
cat > "$CYDIA/index.html" <<PAGE
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Clawdmeter for Cydia</title>
<style>
body {
  margin: 0;
  padding: 48px 20px 64px;
  background: #1d1917;
  color: #efe4e0;
  font: 16px/1.6 "Helvetica Neue", Helvetica, Arial, sans-serif;
  -webkit-text-size-adjust: 100%;
}
.wrap { max-width: 640px; margin: 0 auto; }
h1 { margin: 18px 0 6px; font-size: 34px; letter-spacing: -0.5px; }
h2 { margin: 34px 0 10px; font-size: 17px; color: #ec9676; letter-spacing: 0.3px; }
p, li { color: #d8cac5; }
.lead { color: #a3908a; margin: 0 0 28px; }
b { color: #efe4e0; font-weight: 600; }
a { color: #ec9676; }
.source {
  background: #2a2320;
  border: 1px solid #3b3029;
  border-radius: 10px;
  padding: 16px 18px;
}
.source .label {
  display: block;
  font-size: 11px;
  letter-spacing: 2px;
  text-transform: uppercase;
  color: #a3908a;
  margin-bottom: 8px;
}
.source code {
  font: 15px/1.4 "SF Mono", Menlo, Consolas, monospace;
  color: #ec9676;
  word-break: break-all;
}
ol, ul { padding-left: 22px; }
li { margin: 6px 0; }
.note {
  border-left: 3px solid #d77757;
  padding: 2px 0 2px 16px;
  color: #a3908a;
}
.foot {
  margin-top: 40px;
  padding-top: 18px;
  border-top: 1px solid #2a2320;
  font-size: 14px;
  color: #a3908a;
}
</style>
</head>
<body>
<div class="wrap">

<svg width="112" height="70" viewBox="0 0 16 10" shape-rendering="crispEdges" aria-label="Clawd">
  <rect x="2" y="0" width="12" height="8" fill="#d77757"/>
  <rect x="3" y="0" width="10" height="1" fill="#ec9676"/>
  <rect x="0" y="4" width="2" height="2" fill="#be5c3e"/>
  <rect x="14" y="4" width="2" height="2" fill="#be5c3e"/>
  <rect x="4" y="2" width="1" height="2" fill="#17120f"/>
  <rect x="11" y="2" width="1" height="2" fill="#17120f"/>
  <rect x="3" y="7" width="1" height="3" fill="#be5c3e"/>
  <rect x="5" y="7" width="1" height="3" fill="#be5c3e"/>
  <rect x="10" y="7" width="1" height="3" fill="#be5c3e"/>
  <rect x="12" y="7" width="1" height="3" fill="#be5c3e"/>
</svg>

<h1>Clawdmeter</h1>
<p class="lead">Your Claude plan usage on an iPhone you stopped using, with Clawd walking along the bottom of the screen. Built for iOS 9 and armv7.</p>

<div class="source">
  <span class="label">Cydia source</span>
  <code>$SOURCE</code>
</div>

<h2>Adding it</h2>
<ol>
  <li>Open Cydia, go to <b>Sources</b>, tap <b>Edit</b> and then <b>Add</b>.</li>
  <li>Type the address above and tap <b>Add Source</b>.</li>
  <li>Open the source, pick <b>Clawdmeter</b> and tap <b>Install</b>.</li>
  <li>Open the app on the Home Screen, hold a finger anywhere on the screen and type the address of your PC and the key.</li>
</ol>

<h2>What it needs</h2>
<ul>
  <li>A jailbroken iPhone on iOS 9. An iPhone 4S, a 4 or a 3GS is plenty, and anything newer still on 9 works too.</li>
  <li>uikittools, which Cydia installs with it.</li>
  <li>The Clawdmeter app on a Windows PC on the same network, with the screen for an old phone turned on. That is where the numbers come from, so the phone never signs in to anything.</li>
</ul>

<h2>It is not signed</h2>
<p class="note">There is no signing key on this source, so Cydia warns once that it cannot check where the files came from and asks you to confirm. That is normal for a small repository and nothing is hidden: the package, the list and this page are all in the open on GitHub, and the list carries the checksums Cydia compares the download against.</p>

<p class="foot">Version $VERSION. Source and build scripts on <a href="$REPO/tree/main/oldphone">GitHub</a>. There is an SSH way to install it too, for phones without Cydia.</p>

</div>
</body>
</html>
PAGE

# 5. Proof.
echo "repository in docs/cydia"
echo "  source: $SOURCE"
echo "  packages indexed: $count"
ls -l "$CYDIA" "$DEBS" | sed 's/^/  /'
