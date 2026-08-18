#!/bin/sh
set -u

TARGET="/var/local/mesquite/KindleForge"
DB="/var/local/appreg.db"
APP_ID="xyz.penguins184.kindleforge"
STATE_DIR="/mnt/us/.dcpro_kindleforge"

# Best-effort close request. Failure is non-fatal because appmgr behavior varies
# across Kindle firmware generations.
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
rm -f "$STATE_DIR/KPM_INSTALL_OK" 2>/dev/null || true
rmdir "$STATE_DIR" 2>/dev/null || true

# Intentionally preserve /mnt/us/.KFPM. It belongs to KindleForge/KFPM package
# state and may describe apps the customer installed separately.
echo "KindleForge removed. /mnt/us/.KFPM was preserved."
exit 0
