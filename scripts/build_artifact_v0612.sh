#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard/source"
OUT="$ROOT/packages/ghostguard/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.6.11
PKG="$OUT/ghostguard_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/payload"
cp -R "$SRC/payload/dcghostguardpro.koplugin" "$TMP/payload/"
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
chmod +x "$TMP/install.sh" "$TMP/launch.sh"
# Validate payload before packaging.
for f in main.lua license_manager.lua keys/keyring.lua adaptive_bootstrap.lua; do
  test -f "$TMP/payload/dcghostguardpro.koplugin/$f"
done
# KPM package is a tar.gz payload with install/launch hooks.
tar -C "$TMP" -czf "$PKG" payload install.sh launch.sh
printf '%s\n' "$PKG"
