#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/kindleforge/source"
OUT="$ROOT/packages/kindleforge/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=4.1.1
PKG="$OUT/kindleforge_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"

UPSTREAM_VERSION=4.1.0
RELEASE_URL="https://github.com/KindleTweaks/KindleForge/releases/download/v${UPSTREAM_VERSION}/KindleForge.zip"

mkdir -p "$OUT"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
RELEASE_ZIP="$TMP/KindleForge.zip"
RELEASE_DIR="$TMP/release"
PAYLOAD="$TMP/payload/KindleForge"
mkdir -p "$RELEASE_DIR" "$TMP/payload"

for script in "$SRC/install.sh" "$SRC/launch.sh" "$SRC/uninstall.sh" "$SRC/runtime.sh"; do
    sh -n "$script"
done

fetch() {
    url="$1"
    out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --silent --show-error "$url" -o "$out"
    else
        wget -q -O "$out" "$url"
    fi
}

# Use the exact upstream release asset consumed by KindleForge's own
# "Update KForge" flow, rather than reconstructing a bundle from Git blobs.
fetch "$RELEASE_URL" "$RELEASE_ZIP"
unzip -q "$RELEASE_ZIP" -d "$RELEASE_DIR"
CONFIG_PATH=$(find "$RELEASE_DIR" -type f -name config.xml | head -1)
[ -n "$CONFIG_PATH" ] || { echo "KindleForge build: release config.xml not found" >&2; exit 1; }
BUNDLE=$(dirname "$CONFIG_PATH")

for f in config.xml index.html script.js style.css assets/polyfill.js assets/inter.ttf assets/libre-baskerville.ttf binaries/KFPM binaries/UtildHF binaries/UtildSF; do
    [ -f "$BUNDLE/$f" ] || { echo "KindleForge build: release missing $f" >&2; exit 1; }
done

cp -Rp "$BUNDLE" "$PAYLOAD"
chmod 755 "$PAYLOAD/binaries/KFPM" "$PAYLOAD/binaries/UtildHF" "$PAYLOAD/binaries/UtildSF"

grep -q 'Version 4.1.0 stable' "$PAYLOAD/index.html"
grep -q 'xyz.penguins184.kindleforge' "$PAYLOAD/config.xml"
grep -q 'Update KForge' "$PAYLOAD/script.js"
grep -q '/var/local/mesquite/KindleForge/binaries/KFPM' "$PAYLOAD/script.js"
[ -s "$PAYLOAD/binaries/KFPM" ]
[ -s "$PAYLOAD/binaries/UtildHF" ]
[ -s "$PAYLOAD/binaries/UtildSF" ]

cp "$SRC/manifest.json" "$TMP/manifest.json"
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/uninstall.sh" "$TMP/uninstall.sh"
cp "$SRC/runtime.sh" "$TMP/runtime.sh"
cp "$SRC/UPSTREAM.md" "$TMP/UPSTREAM.md"
sha256sum "$RELEASE_ZIP" | awk '{print $1 "  KindleForge-v4.1.0-release.zip"}' > "$TMP/UPSTREAM_RELEASE_SHA256"
chmod 755 "$TMP/install.sh" "$TMP/launch.sh" "$TMP/uninstall.sh" "$TMP/runtime.sh"

tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh launch.sh uninstall.sh runtime.sh UPSTREAM.md UPSTREAM_RELEASE_SHA256
printf '%s\n' "$PKG"
