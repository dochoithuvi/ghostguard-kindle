#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard/source"
OUT="$ROOT/packages/ghostguard/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.6.12
PKG="$OUT/ghostguard_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/payload" "$TMP/scriptlets" "$TMP/assets"
cp -R "$SRC/payload/dcghostguardpro.koplugin" "$TMP/payload/"
# Safety repair for the 0.6.11 main.lua typo that prevented KOReader from
# loading the plugin at all. Keep this in the builder so every future artifact
# is self-healing even if an older source copy is present.
python3 - "$TMP/payload/dcghostguardpro.koplugin/main.lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
bad = "\nend    return true\nend\n"
if bad in s:
    s = s.replace(bad, "\nend\n", 1)
    open(p, "w", encoding="utf-8").write(s)
PY
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/scriptlets/DCPRO_GhostGuard.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
if [ -f "$SRC/assets/ghostguard_library_600x960.jpg" ]; then
  cp "$SRC/assets/ghostguard_library_600x960.jpg" "$TMP/assets/ghostguard_library_600x960.jpg"
fi
chmod +x "$TMP/install.sh" "$TMP/launch.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
for f in main.lua license_manager.lua keys/keyring.lua adaptive_bootstrap.lua; do
  test -f "$TMP/payload/dcghostguardpro.koplugin/$f"
done
test -f "$TMP/scriptlets/DCPRO_GhostGuard.sh"
test -f "$TMP/assets/ghostguard_library_600x960.jpg"
# Fail the build if the known loader-breaking sequence somehow returns.
! grep -q 'end    return true' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
tar -C "$TMP" -czf "$PKG" payload install.sh launch.sh scriptlets assets
printf '%s\n' "$PKG"
