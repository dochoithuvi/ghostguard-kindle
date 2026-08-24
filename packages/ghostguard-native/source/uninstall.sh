#!/bin/sh
set -u

APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
RUNTIME="/var/local/mesquite/GhostGuardNative.kpm-launch.sh"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"
DB="/var/local/appreg.db"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"

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
rm -rf "$STATE_DIR" 2>/dev/null || true

echo "GhostGuard Native Probe removed."
echo "No KOReader package or GhostGuard KOReader data was touched."
exit 0
