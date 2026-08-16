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
mkdir -p "$TMP/payload" "$TMP/scriptlets" "$TMP/assets"
cp -R "$SRC/payload/dcghostguardpro.koplugin" "$TMP/payload/"
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
# Include the Library launcher script and its cover asset in the KPM artifact.
# install.sh consumes both paths relative to the package root.
cp "$SRC/scriptlets/DCPRO_GhostGuard.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
if [ -f "$SRC/assets/ghostguard_library_600x960.jpg" ]; then
  cp "$SRC/assets/ghostguard_library_600x960.jpg" "$TMP/assets/ghostguard_library_600x960.jpg"
fi
chmod +x "$TMP/install.sh" "$TMP/launch.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
# Validate payload before packaging.
for f in main.lua license_manager.lua keys/keyring.lua adaptive_bootstrap.lua; do
  test -f "$TMP/payload/dcghostguardpro.koplugin/$f"
done
test -f "$TMP/scriptlets/DCPRO_GhostGuard.sh"
test -f "$TMP/assets/ghostguard_library_600x960.jpg"
# KPM package is a tar.gz payload with install/launch hooks and Library launcher assets.
tar -C "$TMP" -czf "$PKG" payload install.sh launch.sh scriptlets assets
printf '%s\n' "$PKG"
