#!/bin/sh
set -eu

APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
RUNTIME="/var/local/mesquite/GhostGuardNative.kpm-launch.sh"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"
DB="/var/local/appreg.db"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"
STAGING="/var/local/mesquite/.GhostGuardNative.kpm-new.$$"
BACKUP="/var/local/mesquite/.GhostGuardNative.kpm-old"

rollback() {
    rm -rf "$STAGING" 2>/dev/null || true
    if [ -d "$BACKUP" ] && [ ! -d "$TARGET" ]; then
        mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fi
}

fail() {
    echo "GhostGuard Native install: $1" >&2
    rollback
    exit 1
}

valid_payload() {
    [ -f "$1/config.xml" ] && [ -f "$1/index.html" ] && \
    [ -f "$1/style.css" ] && [ -f "$1/script.js" ]
}

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 not found"
command -v lipc-set-prop >/dev/null 2>&1 || fail "lipc-set-prop not found"
[ -x /usr/bin/mesquite ] || fail "Mesquite runtime not found"
[ -f "$DB" ] || fail "appreg.db not found"
valid_payload "payload/GhostGuardNative" || fail "Mesquite payload incomplete"
[ -f runtime.sh ] || fail "runtime.sh missing"
[ -f probe.sh ] || fail "probe.sh missing"

# Safety boundary for v0.1.0: this package is deliberately isolated from
# GhostGuard KOReader. It must not patch, replace, move, or delete anything
# under /mnt/us/koreader or dcghostguardpro.koplugin.
if grep -E '/mnt/us/koreader|dcghostguardpro\.koplugin' install.sh runtime.sh probe.sh >/dev/null 2>&1; then
    fail "safety check rejected KOReader path reference"
fi

rm -rf "$STAGING" "$BACKUP"
cp -Rp payload/GhostGuardNative "$STAGING" || fail "cannot stage Mesquite payload"

[ -d "$TARGET" ] && mv "$TARGET" "$BACKUP" || true
mv "$STAGING" "$TARGET" || fail "cannot activate Mesquite payload"

cp -p runtime.sh "$RUNTIME" || fail "cannot install runtime wrapper"
cp -p probe.sh "$PROBE" || fail "cannot install probe wrapper"
chmod 755 "$RUNTIME" "$PROBE" 2>/dev/null || true

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
    fail "cannot register Mesquite application"
fi

REGISTERED="$(sqlite3 "$DB" "SELECT COUNT(*) FROM handlerIds WHERE handlerId='$APP_ID';" 2>/dev/null || echo 0)"
[ "$REGISTERED" = "1" ] || fail "application registration verification failed"

rm -rf "$BACKUP"
mkdir -p "$STATE_DIR" || fail "cannot create state directory"

# Generate an initial metadata-only probe snapshot. The probe reads proc/sysfs
# metadata only; it never opens /dev/input/event* and never issues EVIOCGRAB.
"$PROBE" >/dev/null 2>&1 || true

printf 'PACKAGE_ID=ghostguard-native\nPACKAGE_VERSION=0.1.0\nMODE=READ_ONLY_PROBE\nAPP_ID=%s\nTARGET=%s\nINSTALLED_UTC=%s\n' \
    "$APP_ID" "$TARGET" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
    > "$STATE_DIR/KPM_INSTALL_OK" 2>/dev/null || true

echo "GhostGuard Native Probe 0.1.0 installed."
echo "Safety mode: read-only input metadata probe; Protect is OFF."
echo "KOReader GhostGuard was not modified."
exit 0
