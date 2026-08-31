#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$HERE/.." && pwd)"
SRC="$ROOT/packages/ghostguard/source"
OUT="$ROOT/packages/ghostguard/artifacts/ghostguard_0.9.2_kindle5-kindlepw2-kindlehf.kpkg"
TMP="${TMPDIR:-/tmp}/ghostguard-092-build.$$"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT INT TERM
mkdir -p "$TMP/pkg" "$(dirname "$OUT")"

for item in manifest.json install.sh uninstall.sh launch.sh payload scriptlets system RELEASE_NOTES_0.9.2.md; do
    cp -R "$SRC/$item" "$TMP/pkg/$item"
done

mkdir -p "$TMP/pkg/assets"
if command -v base64 >/dev/null 2>&1; then
    cat "$SRC"/assets/ghostguard_library_600x960.jpg.b64.* | tr -d '\r\n' | base64 -d > "$TMP/pkg/assets/ghostguard_library_600x960.jpg"
else
    python3 - "$SRC/assets" "$TMP/pkg/assets/ghostguard_library_600x960.jpg" <<'PY'
import base64, pathlib, sys
srcdir, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
parts = sorted(srcdir.glob("ghostguard_library_600x960.jpg.b64.*"))
dst.write_bytes(base64.b64decode("".join(p.read_text().strip() for p in parts)))
PY
fi
cp "$TMP/pkg/assets/ghostguard_library_600x960.jpg" \
   "$TMP/pkg/payload/dcghostguardpro.koplugin/assets/ghostguard_library_600x960.jpg"

chmod 755 "$TMP/pkg/install.sh" "$TMP/pkg/uninstall.sh" "$TMP/pkg/launch.sh" \
    "$TMP/pkg/scriptlets/DCPRO_GhostGuard.sh" 2>/dev/null || true
chmod 755 "$TMP/pkg/system/ghostguard-service.sh" \
    "$TMP/pkg/system/ghostguard-native-capture.sh" 2>/dev/null || true

(
    cd "$TMP/pkg"
    tar --sort=name --mtime='UTC 2026-08-31 00:00:00' \
        --owner=0 --group=0 --numeric-owner -cf - \
        manifest.json install.sh uninstall.sh launch.sh payload scriptlets assets system RELEASE_NOTES_0.9.2.md
) | gzip -n -9 > "$OUT"

echo "$OUT"
