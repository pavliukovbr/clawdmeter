#!/bin/sh
# Builds Clawdmeter for Windows and packs it for a GitHub release.
# Runs anywhere the .NET SDK is installed, the build happens in a temporary folder
# so no local paths end up inside the app.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECT="windows/Clawdmeter/Clawdmeter.csproj"
VERSION=$(sed -n 's/.*<Version>\(.*\)<\/Version>.*/\1/p' "$ROOT/$PROJECT" | head -n 1)
WORK=$(mktemp -d /tmp/clawdmeter-windows.XXXXXX)
OUT="$ROOT/dist"

git clone -q "$ROOT" "$WORK/src"
cd "$WORK/src"
dotnet publish "$PROJECT" -c Release -r win-x64 --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:EnableCompressionInSingleFile=true \
    -p:DebugType=none \
    -o "$WORK/publish"

mkdir -p "$OUT"
rm -f "$OUT/Clawdmeter-Windows.zip" "$OUT/Clawdmeter-Windows.zip.sha256"
(cd "$WORK/publish" && zip -qry "$OUT/Clawdmeter-Windows.zip" .)
shasum -a 256 "$OUT/Clawdmeter-Windows.zip" | awk '{print $1}' > "$OUT/Clawdmeter-Windows.zip.sha256"

rm -rf "$WORK"
echo "Clawdmeter for Windows $VERSION is ready in dist"
