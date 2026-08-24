#!/bin/sh
set -u

ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
RUNTIME="/var/local/mesquite/GhostGuardNative.kpm-launch.sh"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"
DB="/var/local/appreg.db"
STATE_DIR="$ROOT/.dcpro_ghostguard_native"
LAUNCHER="$ROOT/documents/DCPRO_GhostGuard_Native.sh"
ASSET_DIR="$ROOT/dcpro/ghostguard-native"

if command -v lipc-set-prop >/dev/null 2>&1; then
    lipc-set-prop com.lab126.appmgrd stop "app://$APP_ID" >/dev/null 2>&1 || true
fi

if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
    sqlite3 "$DB" <<EOF
BEGIN;
DELETE FROM properties WHERE handlerId='$APP_ID';
DELETE FROM handlerIds WHERE handlerId='$APP_ID';
COMMIT;
EOF
fi

rm -rf "$TARGET"
rm -f "$RUNTIME" "$PROBE" 2>/dev/null || true
rm -f "$LAUNCHER" 2>/dev/null || true
rm -rf "$ASSET_DIR" 2>/dev/null || true
rm -rf "$STATE_DIR" 2>/dev/null || true
sync 2>/dev/null || true

echo "GhostGuard Native removed."
echo "GhostGuard Native Library launcher removed."
echo "No KOReader package or GhostGuard KOReader data was touched."
exit 0
