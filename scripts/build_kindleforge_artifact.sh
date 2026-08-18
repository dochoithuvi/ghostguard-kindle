#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/kindleforge/source"
OUT="$ROOT/packages/kindleforge/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=4.1.0
PKG="$OUT/kindleforge_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"

TAG_REF="v4.1.0"
SCRIPT_REF="64c8e264a01277f622c32340bc448c4f1f0e7822"
TAG_BASE="https://raw.githubusercontent.com/KindleTweaks/KindleForge/$TAG_REF/KindleForge/KindleForge"
SCRIPT_BASE="https://raw.githubusercontent.com/KindleTweaks/KindleForge/$SCRIPT_REF/KindleForge/KindleForge"

mkdir -p "$OUT"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PAYLOAD="$TMP/payload/KindleForge"
mkdir -p "$PAYLOAD/assets" "$PAYLOAD/binaries"

fetch() {
    url="$1"
    out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --silent --show-error "$url" -o "$out"
    else
        wget -q -O "$out" "$url"
    fi
}

fetch "$TAG_BASE/config.xml" "$PAYLOAD/config.xml"
fetch "$TAG_BASE/index.html" "$PAYLOAD/index.html"
fetch "$SCRIPT_BASE/script.js" "$PAYLOAD/script.js"
fetch "$TAG_BASE/style.css" "$PAYLOAD/style.css"
fetch "$TAG_BASE/assets/polyfill.js" "$PAYLOAD/assets/polyfill.js"
fetch "$TAG_BASE/assets/inter.ttf" "$PAYLOAD/assets/inter.ttf"
fetch "$TAG_BASE/assets/libre-baskerville.ttf" "$PAYLOAD/assets/libre-baskerville.ttf"
fetch "$TAG_BASE/binaries/KFPM" "$PAYLOAD/binaries/KFPM"
fetch "$TAG_BASE/binaries/UtildHF" "$PAYLOAD/binaries/UtildHF"
fetch "$TAG_BASE/binaries/UtildSF" "$PAYLOAD/binaries/UtildSF"

check_sha256() {
    expected="$1"
    file="$2"
    actual=$(sha256sum "$file" | awk '{print $1}')
    [ "$actual" = "$expected" ] || {
        echo "KindleForge build: checksum mismatch for $file" >&2
        echo "expected=$expected" >&2
        echo "actual=$actual" >&2
        exit 1
    }
}

# Binary/font hashes are byte-for-byte matches to the supplied KindleForge.zip.
check_sha256 bbeb0ab7ee0b6d9acdfe6b6a3cc47634b75fd613449934356dc1f8458ecb6d7b "$PAYLOAD/binaries/KFPM"
check_sha256 c939d37262ac7b324e8deaa463a9c8152e7ceb55004f01e0511005c8661854d9 "$PAYLOAD/binaries/UtildHF"
check_sha256 a8a44e0f6c7f4869d0574197df9a304dbd25035d6fc45156f7431bcb8d72a9f8 "$PAYLOAD/binaries/UtildSF"
check_sha256 0be2399ea925f1f83ff974764761da9860ec50742ed29a5d4c1ffd0c5c7ac3a8 "$PAYLOAD/assets/inter.ttf"
check_sha256 2101302538d9e88adb679031c04623e4578b5745e89566284fd2c508d79acae0 "$PAYLOAD/assets/libre-baskerville.ttf"

# Text payload is normalized to LF. These hashes correspond to the supplied ZIP
# after CRLF normalization.
check_sha256 44fc88b4f1d93c8486c9797756558c29a535fff720209a26929294489fdc45e0 "$PAYLOAD/config.xml"
check_sha256 a42ddd5a8a983c3cfa3f3a2672e1beffd907176ece4024cbd6ceec135ec69d27 "$PAYLOAD/index.html"
check_sha256 2fe81dba2b2feaae4dbafd3d585e5fde363740812fcb7e82943ab7130f5272fc "$PAYLOAD/script.js"
check_sha256 35ea472c025dac11ab2633c76c4a7f26a294a3424d45085c9f33255f79f66395 "$PAYLOAD/style.css"
check_sha256 e466d7d47e677c4cac0ee84525d49f33c5ed97350a05e0d4a96497344123abf9 "$PAYLOAD/assets/polyfill.js"

grep -q 'Version 4.1.0 stable' "$PAYLOAD/index.html"
grep -q 'xyz.penguins184.kindleforge' "$PAYLOAD/config.xml"
grep -q '/var/local/mesquite/KindleForge/binaries/KFPM' "$PAYLOAD/script.js"

cp "$SRC/manifest.json" "$TMP/manifest.json"
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/uninstall.sh" "$TMP/uninstall.sh"
cp "$SRC/UPSTREAM.md" "$TMP/UPSTREAM.md"
chmod 755 "$TMP/install.sh" "$TMP/launch.sh" "$TMP/uninstall.sh"
chmod 755 "$PAYLOAD/binaries/KFPM" "$PAYLOAD/binaries/UtildHF" "$PAYLOAD/binaries/UtildSF"

tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh launch.sh uninstall.sh UPSTREAM.md
printf '%s\n' "$PKG"
