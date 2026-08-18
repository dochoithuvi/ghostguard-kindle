#!/bin/sh
# DCPRO GhostGuard OneClick v12.1 bootstrap
# Purpose: avoid stale/cached local copies of v12 by downloading the latest fixed
# DCPRO_GhostGuard_OneClick_Installer_v12.sh from main before execution.

ROOT=/mnt/us
TMP="$ROOT/.dcpro_ghostguard"
URL="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/DCPRO_GhostGuard_OneClick_Installer_v12.sh"
OUT="$TMP/DCPRO_GhostGuard_OneClick_Installer_v12.latest.sh"

mkdir -p "$TMP" 2>/dev/null || exit 1
rm -f "$OUT" 2>/dev/null || true

if command -v curl >/dev/null 2>&1; then
    curl -L --fail --silent --show-error "$URL" -o "$OUT" || exit 1
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$OUT" "$URL" || exit 1
else
    echo "v12.1: curl/wget not found" >&2
    exit 1
fi

# Refuse to execute an old/cached v12. The fixed v12 normalizes multi-line JSON
# into ghostguard_manifest.compact.json before validating GhostGuard 0.6.14.
grep -q 'ghostguard_manifest.compact.json' "$OUT" || {
    echo "v12.1: downloaded v12 is not the fixed revision" >&2
    rm -f "$OUT" 2>/dev/null || true
    exit 1
}

echo "DCPRO GhostGuard OneClick v12.1: latest fixed v12 downloaded; starting..."
exec /bin/sh "$OUT"
