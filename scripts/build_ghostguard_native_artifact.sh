#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard-native/source"
OUT="$ROOT/packages/ghostguard-native/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.1.0
PKG="$OUT/ghostguard-native_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"

for f in manifest.json install.sh launch.sh uninstall.sh runtime.sh probe.sh README.md; do
    [ -f "$SRC/$f" ] || { echo "GhostGuard Native build: missing $f" >&2; exit 1; }
done
for f in config.xml index.html style.css script.js; do
    [ -f "$SRC/payload/GhostGuardNative/$f" ] || { echo "GhostGuard Native build: missing payload/$f" >&2; exit 1; }
done

for script in "$SRC/install.sh" "$SRC/launch.sh" "$SRC/uninstall.sh" "$SRC/runtime.sh" "$SRC/probe.sh"; do
    sh -n "$script"
done

# v0.1 is intentionally non-invasive. Fail the build if any operational script
# attempts to grab/inject input or references the stable KOReader installation.
if grep -Ei 'EVIOCGRAB|/dev/uinput|/mnt/us/koreader|dcghostguardpro\.koplugin' \
    "$SRC/install.sh" "$SRC/launch.sh" "$SRC/uninstall.sh" "$SRC/runtime.sh" >/dev/null 2>&1; then
    echo "GhostGuard Native build: prohibited invasive/stable-path reference" >&2
    exit 1
fi
if grep -Ei 'EVIOCGRAB|/dev/uinput' "$SRC/probe.sh" | grep -v '^.*echo ' >/dev/null 2>&1; then
    echo "GhostGuard Native build: probe contains invasive input operation" >&2
    exit 1
fi

grep -q '"id": "ghostguard-native"' "$SRC/manifest.json"
grep -q '"version": \[0, 1, 0\]' "$SRC/manifest.json"
grep -q 'EVENT_NODE_OPEN=NO' "$SRC/probe.sh"
grep -q 'INPUT_GRAB=OFF' "$SRC/probe.sh"
grep -q 'background daemon: NO' "$SRC/probe.sh"

mkdir -p "$OUT"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp "$SRC/manifest.json" "$TMP/manifest.json"
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/uninstall.sh" "$TMP/uninstall.sh"
cp "$SRC/runtime.sh" "$TMP/runtime.sh"
cp "$SRC/probe.sh" "$TMP/probe.sh"
cp "$SRC/README.md" "$TMP/README.md"
cp -Rp "$SRC/payload" "$TMP/payload"
chmod 755 "$TMP/install.sh" "$TMP/launch.sh" "$TMP/uninstall.sh" "$TMP/runtime.sh" "$TMP/probe.sh"

tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh launch.sh uninstall.sh runtime.sh probe.sh README.md
printf '%s\n' "$PKG"
