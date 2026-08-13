#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
TARGET="$ROOT/koreader/plugins/dcghostguardpro.koplugin"
DATA="$ROOT/.dcpro_ghostguard"
LAUNCHER="$ROOT/documents/DCPRO_GhostGuard.sh"
ASSET="$ROOT/dcpro/ghostguard/assets/ghostguard_library_600x960.jpg"
mkdir -p "$DATA" 2>/dev/null || true

if [ "${1:-}" = "upgrade" ]; then
    echo "GhostGuard upgrade: active plugin and license preserved for transactional replacement."
    exit 0
fi

# Full uninstall: fail-safe first and preserve the purchased key outside the removed plugin.
printf 'DCPRO_GHOSTGUARD_SAFE_MODE=1\nREASON=kpm-uninstall\n' > "$DATA/SAFE_MODE" 2>/dev/null || true
if [ -s "$TARGET/license.key" ]; then
    umask 077
    cp -p "$TARGET/license.key" "$DATA/license.key.kpm-backup" 2>/dev/null || true
fi
rm -rf "$TARGET"
if [ -f "$LAUNCHER" ] && grep -q 'DCPRO GhostGuard' "$LAUNCHER" 2>/dev/null; then rm -f "$LAUNCHER"; fi
rm -f "$ASSET"
rm -f "$DATA/KPM_INSTALL_OK"
echo "GhostGuard removed. Reports/profile/license backup kept in $DATA. SAFE_MODE left ON."
exit 0
