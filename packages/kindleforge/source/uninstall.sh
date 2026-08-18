#!/bin/sh
set -u

DOCS="/mnt/us/documents/KindleForge"
DOCS_SCRIPT="/mnt/us/documents/KindleForge.sh"
TARGET="/var/local/mesquite/KindleForge"
RUNTIME="/var/local/mesquite/KindleForge.kpm-launch.sh"
DB="/var/local/appreg.db"
APP_ID="xyz.penguins184.kindleforge"
STATE_DIR="/mnt/us/.dcpro_kindleforge"

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

rm -rf "$TARGET" "$DOCS"
rm -f "$RUNTIME" "$DOCS_SCRIPT" 2>/dev/null || true
rm -f "$STATE_DIR/KPM_INSTALL_OK" 2>/dev/null || true
rmdir "$STATE_DIR" 2>/dev/null || true

# Preserve /mnt/us/.KFPM because it may describe packages the customer installed
# through KindleForge. Also preserve /var/local/kmc/UtildHF|UtildSF because the
# messaging endpoint is shared by other Kindle apps and is not owned exclusively
# by this KPM package.
echo "KindleForge removed. Shared KFPM state and Utild binaries were preserved."
exit 0
