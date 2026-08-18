#!/bin/sh
set -u

DOCS="/mnt/us/documents/KindleForge"
TARGET="/var/local/mesquite/KindleForge"
RUNTIME="/var/local/mesquite/KindleForge.kpm-launch.sh"
DB="/var/local/appreg.db"
APP_ID="xyz.penguins184.kindleforge"
STATE_DIR="/mnt/us/.dcpro_kindleforge"
DOCS_STAGING="/mnt/us/documents/.KindleForge.kpm-new.$$"
DOCS_BACKUP="/mnt/us/documents/.KindleForge.kpm-old"
TARGET_STAGING="/var/local/mesquite/.KindleForge.kpm-new.$$"
TARGET_BACKUP="/var/local/mesquite/.KindleForge.kpm-old"

rollback() {
    rm -rf "$DOCS_STAGING" "$TARGET_STAGING" 2>/dev/null || true
    if [ -d "$DOCS_BACKUP" ] && [ ! -d "$DOCS" ]; then mv "$DOCS_BACKUP" "$DOCS" 2>/dev/null || true; fi
    if [ -d "$TARGET_BACKUP" ] && [ ! -d "$TARGET" ]; then mv "$TARGET_BACKUP" "$TARGET" 2>/dev/null || true; fi
}

fail() {
    echo "KindleForge install: $1" >&2
    rollback
    exit 1
}

valid_bundle() {
    [ -f "$1/config.xml" ] && [ -f "$1/index.html" ] && [ -f "$1/script.js" ] && \
    [ -f "$1/binaries/KFPM" ] && [ -f "$1/binaries/UtildHF" ] && [ -f "$1/binaries/UtildSF" ]
}

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 not found"
command -v lipc-set-prop >/dev/null 2>&1 || fail "lipc-set-prop not found"
[ -x /usr/bin/mesquite ] || fail "Mesquite runtime not found"
[ -f "$DB" ] || fail "appreg.db not found"
valid_bundle "payload/KindleForge" || fail "official KindleForge bundle incomplete"
[ -f "runtime.sh" ] || fail "KPM runtime wrapper missing"

rm -rf "$DOCS_STAGING" "$TARGET_STAGING" "$DOCS_BACKUP" "$TARGET_BACKUP"
cp -Rp "payload/KindleForge" "$DOCS_STAGING" || fail "cannot stage documents bundle"
cp -Rp "payload/KindleForge" "$TARGET_STAGING" || fail "cannot stage Mesquite bundle"
chmod 755 "$DOCS_STAGING/binaries/KFPM" "$DOCS_STAGING/binaries/UtildHF" "$DOCS_STAGING/binaries/UtildSF" 2>/dev/null || true
chmod 755 "$TARGET_STAGING/binaries/KFPM" "$TARGET_STAGING/binaries/UtildHF" "$TARGET_STAGING/binaries/UtildSF" 2>/dev/null || true

[ -d "$DOCS" ] && mv "$DOCS" "$DOCS_BACKUP" || true
[ -d "$TARGET" ] && mv "$TARGET" "$TARGET_BACKUP" || true
mv "$DOCS_STAGING" "$DOCS" || fail "cannot activate documents bundle"
mv "$TARGET_STAGING" "$TARGET" || fail "cannot activate Mesquite bundle"

cp -p "runtime.sh" "$RUNTIME" || fail "cannot install runtime wrapper"
chmod 755 "$RUNTIME" 2>/dev/null || true

# Match the official KindleForge installer: select the device ABI, place the
# matching Utild endpoint under /var/local/kmc, and start it before first use.
if [ -e /lib/ld-linux-armhf.so.3 ]; then
    UTILD_NAME="UtildHF"
    OTHER_NAME="UtildSF"
else
    UTILD_NAME="UtildSF"
    OTHER_NAME="UtildHF"
fi
mkdir -p /var/local/kmc 2>/dev/null || true
cp -p "$TARGET/binaries/$UTILD_NAME" "/var/local/kmc/$UTILD_NAME" || fail "cannot install $UTILD_NAME"
chmod 755 "/var/local/kmc/$UTILD_NAME" 2>/dev/null || true
killall "$OTHER_NAME" >/dev/null 2>&1 || true
"/var/local/kmc/$UTILD_NAME" >/dev/null 2>&1 || true

if ! sqlite3 "$DB" <<EOF
BEGIN;
INSERT OR IGNORE INTO interfaces(interface) VALUES('application');
INSERT OR IGNORE INTO handlerIds(handlerId) VALUES('$APP_ID');
INSERT OR REPLACE INTO properties(handlerId,name,value) VALUES('$APP_ID','lipcId','$APP_ID');
INSERT OR REPLACE INTO properties(handlerId,name,value) VALUES('$APP_ID','command','/bin/sh $RUNTIME');
INSERT OR REPLACE INTO properties(handlerId,name,value) VALUES('$APP_ID','supportedOrientation','U');
COMMIT;
EOF
then
    fail "cannot register KindleForge in appreg.db"
fi

REGISTERED="$(sqlite3 "$DB" "SELECT COUNT(*) FROM handlerIds WHERE handlerId='$APP_ID';" 2>/dev/null || echo 0)"
[ "$REGISTERED" = "1" ] || fail "app registration verification failed"

rm -rf "$DOCS_BACKUP" "$TARGET_BACKUP"
mkdir -p "$STATE_DIR" 2>/dev/null || true
printf 'PACKAGE_ID=kindleforge\nPACKAGE_REVISION=4.1.1\nUPSTREAM_VERSION=4.1.0\nAPP_ID=%s\nTARGET=%s\nDOCUMENTS_BUNDLE=%s\nUTILD=%s\nINSTALLED_UTC=%s\n' \
    "$APP_ID" "$TARGET" "$DOCS" "$UTILD_NAME" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
    > "$STATE_DIR/KPM_INSTALL_OK" 2>/dev/null || true

echo "KindleForge upstream 4.1.0 installed (KPM revision 4.1.1)."
echo "In-app Update KForge downloads are applied automatically on the next app launch."
exit 0
