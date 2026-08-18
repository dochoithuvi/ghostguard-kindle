#!/bin/sh
set -u

TARGET="/var/local/mesquite/KindleForge"
STAGING="/var/local/mesquite/.KindleForge.kpm-new.$$"
BACKUP="/var/local/mesquite/.KindleForge.kpm-old"
DB="/var/local/appreg.db"
APP_ID="xyz.penguins184.kindleforge"
STATE_DIR="/mnt/us/.dcpro_kindleforge"

fail() {
    echo "KindleForge install: $1" >&2
    rm -rf "$STAGING" 2>/dev/null || true
    if [ -d "$BACKUP" ] && [ ! -d "$TARGET" ]; then
        mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fi
    exit 1
}

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 not found"
command -v lipc-set-prop >/dev/null 2>&1 || fail "lipc-set-prop not found"
[ -x /usr/bin/mesquite ] || fail "Mesquite runtime not found"
[ -f "$DB" ] || fail "appreg.db not found"
[ -f "payload/KindleForge/config.xml" ] || fail "config.xml missing"
[ -f "payload/KindleForge/index.html" ] || fail "index.html missing"
[ -f "payload/KindleForge/script.js" ] || fail "script.js missing"
[ -f "payload/KindleForge/binaries/KFPM" ] || fail "KFPM missing"
[ -f "payload/KindleForge/binaries/UtildHF" ] || fail "UtildHF missing"
[ -f "payload/KindleForge/binaries/UtildSF" ] || fail "UtildSF missing"

rm -rf "$STAGING"
cp -Rp "payload/KindleForge" "$STAGING" || fail "cannot stage KindleForge"
chmod 755 "$STAGING/binaries/KFPM" "$STAGING/binaries/UtildHF" "$STAGING/binaries/UtildSF" 2>/dev/null || true

rm -rf "$BACKUP"
if [ -d "$TARGET" ]; then
    mv "$TARGET" "$BACKUP" || fail "cannot backup existing KindleForge"
fi
if ! mv "$STAGING" "$TARGET"; then
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "cannot activate KindleForge"
fi

if ! sqlite3 "$DB" <<EOF
BEGIN;
INSERT OR IGNORE INTO interfaces(interface) VALUES('application');
INSERT OR IGNORE INTO handlerIds(handlerId) VALUES('$APP_ID');
INSERT OR REPLACE INTO properties(handlerId,name,value) VALUES('$APP_ID','lipcId','$APP_ID');
INSERT OR REPLACE INTO properties(handlerId,name,value) VALUES('$APP_ID','command','/usr/bin/mesquite -l $APP_ID -c file://$TARGET/');
INSERT OR REPLACE INTO properties(handlerId,name,value) VALUES('$APP_ID','supportedOrientation','U');
COMMIT;
EOF
then
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "cannot register KindleForge in appreg.db"
fi

REGISTERED="$(sqlite3 "$DB" "SELECT COUNT(*) FROM handlerIds WHERE handlerId='$APP_ID';" 2>/dev/null || echo 0)"
[ "$REGISTERED" = "1" ] || {
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "app registration verification failed"
}

rm -rf "$BACKUP"
mkdir -p "$STATE_DIR" 2>/dev/null || true
printf 'PACKAGE_ID=kindleforge\nVERSION=4.1.0\nAPP_ID=%s\nTARGET=%s\nINSTALLED_UTC=%s\n' \
    "$APP_ID" "$TARGET" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
    > "$STATE_DIR/KPM_INSTALL_OK" 2>/dev/null || true

echo "KindleForge 4.1.0 installed: $TARGET"
echo "App ID: $APP_ID"
exit 0
