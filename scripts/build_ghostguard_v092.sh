#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$HERE/.." && pwd)"
SRC="$ROOT/packages/ghostguard/source"
# Keep the historical intermediate path because the golden publisher and
# OneClick release gate already consume it. KPM versioning comes from the
# package manifest inside the archive (0.9.3), not this staging filename.
OUT="$ROOT/packages/ghostguard/artifacts/ghostguard_0.9.2_kindle5-kindlepw2-kindlehf.kpkg"
TMP="${TMPDIR:-/tmp}/ghostguard-093-kpm-build.$$"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT INT TERM
mkdir -p "$TMP/pkg" "$(dirname "$OUT")"

# GhostGuard is a KOReader-only plugin now. Do not package the old Kindle
# Library scriptlet/icon; KOReader remains the single Library entry point.
for item in manifest.json install.sh uninstall.sh launch.sh payload system RELEASE_NOTES_0.9.2.md; do
    cp -R "$SRC/$item" "$TMP/pkg/$item"
done

mkdir -p "$TMP/pkg/assets"
set -- "$SRC"/assets/ghostguard_library_600x960.jpg.b64.*
if [ -e "$1" ]; then
    if command -v base64 >/dev/null 2>&1; then
        cat "$SRC"/assets/ghostguard_library_600x960.jpg.b64.* | tr -d '\r\n' | base64 -d > "$TMP/pkg/assets/ghostguard_library_600x960.jpg"
    else
        python3 - "$SRC/assets" "$TMP/pkg/assets/ghostguard_library_600x960.jpg" <<'PY'
import base64, pathlib, sys
srcdir, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
parts = sorted(srcdir.glob("ghostguard_library_600x960.jpg.b64.*"))
if not parts:
    raise SystemExit("missing cover chunks")
dst.write_bytes(base64.b64decode("".join(p.read_text().strip() for p in parts)))
PY
    fi
elif [ -s "$SRC/assets/ghostguard_library_600x960.jpg" ]; then
    cp "$SRC/assets/ghostguard_library_600x960.jpg" "$TMP/pkg/assets/ghostguard_library_600x960.jpg"
else
    echo "Missing GhostGuard compatibility artwork" >&2
    exit 1
fi

cp "$TMP/pkg/assets/ghostguard_library_600x960.jpg" \
   "$TMP/pkg/payload/dcghostguardpro.koplugin/assets/ghostguard_library_600x960.jpg"

chmod 755 "$TMP/pkg/install.sh" "$TMP/pkg/uninstall.sh" "$TMP/pkg/launch.sh" 2>/dev/null || true
chmod 755 "$TMP/pkg/system/ghostguard-service.sh" \
    "$TMP/pkg/system/ghostguard-native-capture.sh" 2>/dev/null || true

(
    cd "$TMP/pkg"
    tar --sort=name --mtime='UTC 2026-09-02 00:00:00' \
        --owner=0 --group=0 --numeric-owner -cf - \
        manifest.json install.sh uninstall.sh launch.sh payload assets system RELEASE_NOTES_0.9.2.md
) | gzip -n -9 > "$OUT"

echo "$OUT"
