#!/bin/sh
set -eu

APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
RUNTIME="/var/local/mesquite/GhostGuardNative.kpm-launch.sh"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"
DB="/var/local/appreg.db"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"
STAGING="/var/local/mesquite/.GhostGuardNative.kpm-new.$$"
BACKUP="/var/local/mesquite/.GhostGuardNative.kpm-old.$$"
RUNTIME_STAGING="${RUNTIME}.new.$$"
PROBE_STAGING="${PROBE}.new.$$"
RUNTIME_BACKUP="${RUNTIME}.old.$$"
PROBE_BACKUP="${PROBE}.old.$$"
TARGET_ACTIVATED=0
TARGET_BACKED_UP=0
RUNTIME_ACTIVATED=0
RUNTIME_BACKED_UP=0
PROBE_ACTIVATED=0
PROBE_BACKED_UP=0
REGISTERED_BEFORE=0

cleanup_staging() {
    rm -rf "$STAGING" 2>/dev/null || true
    rm -f "$RUNTIME_STAGING" "$PROBE_STAGING" 2>/dev/null || true
}

rollback() {
    cleanup_staging

    if [ "$PROBE_ACTIVATED" = "1" ]; then rm -f "$PROBE" 2>/dev/null || true; fi
    if [ "$PROBE_BACKED_UP" = "1" ] && [ -f "$PROBE_BACKUP" ]; then mv "$PROBE_BACKUP" "$PROBE" 2>/dev/null || true; fi

    if [ "$RUNTIME_ACTIVATED" = "1" ]; then rm -f "$RUNTIME" 2>/dev/null || true; fi
    if [ "$RUNTIME_BACKED_UP" = "1" ] && [ -f "$RUNTIME_BACKUP" ]; then mv "$RUNTIME_BACKUP" "$RUNTIME" 2>/dev/null || true; fi

    if [ "$TARGET_ACTIVATED" = "1" ]; then rm -rf "$TARGET" 2>/dev/null || true; fi
    if [ "$TARGET_BACKED_UP" = "1" ] && [ -d "$BACKUP" ]; then mv "$BACKUP" "$TARGET" 2>/dev/null || true; fi

    if [ "$REGISTERED_BEFORE" = "0" ] && command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
        sqlite3 "$DB" "DELETE FROM properties WHERE handlerId='$APP_ID'; DELETE FROM handlerIds WHERE handlerId='$APP_ID';" >/dev/null 2>&1 || true
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

REGISTERED_BEFORE="$(sqlite3 "$DB" "SELECT COUNT(*) FROM handlerIds WHERE handlerId='$APP_ID';" 2>/dev/null || echo 0)"
[ "$REGISTERED_BEFORE" = "1" ] || REGISTERED_BEFORE=0

# v0.1.0 owns only its private Mesquite target, wrappers, app registration and
# state directory. Stable reader/protection packages are outside its ownership.
cleanup_staging
rm -rf "$BACKUP" 2>/dev/null || true
rm -f "$RUNTIME_BACKUP" "$PROBE_BACKUP" 2>/dev/null || true

cp -Rp payload/GhostGuardNative "$STAGING" || fail "cannot stage Mesquite payload"
cp -p runtime.sh "$RUNTIME_STAGING" || fail "cannot stage runtime wrapper"
cp -p probe.sh "$PROBE_STAGING" || fail "cannot stage probe wrapper"
chmod 755 "$RUNTIME_STAGING" "$PROBE_STAGING" 2>/dev/null || true

if [ -d "$TARGET" ]; then
    mv "$TARGET" "$BACKUP" || fail "cannot back up existing Mesquite payload"
    TARGET_BACKED_UP=1
fi
if [ -f "$RUNTIME" ]; then
    mv "$RUNTIME" "$RUNTIME_BACKUP" || fail "cannot back up existing runtime wrapper"
    RUNTIME_BACKED_UP=1
fi
if [ -f "$PROBE" ]; then
    mv "$PROBE" "$PROBE_BACKUP" || fail "cannot back up existing probe wrapper"
    PROBE_BACKED_UP=1
fi

mv "$STAGING" "$TARGET" || fail "cannot activate Mesquite payload"
TARGET_ACTIVATED=1
mv "$RUNTIME_STAGING" "$RUNTIME" || fail "cannot activate runtime wrapper"
RUNTIME_ACTIVATED=1
mv "$PROBE_STAGING" "$PROBE" || fail "cannot activate probe wrapper"
PROBE_ACTIVATED=1

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

rm -rf "$BACKUP" 2>/dev/null || true
rm -f "$RUNTIME_BACKUP" "$PROBE_BACKUP" 2>/dev/null || true
cleanup_staging

mkdir -p "$STATE_DIR" || fail "cannot create state directory"

# Generate an initial metadata-only snapshot. The probe inspects proc/sysfs
# metadata and leaves the live input stream untouched.
"$PROBE" >/dev/null 2>&1 || true

printf 'PACKAGE_ID=ghostguard-native\nPACKAGE_VERSION=0.1.0\nMODE=READ_ONLY_PROBE\nAPP_ID=%s\nTARGET=%s\nINSTALLED_UTC=%s\n' \
    "$APP_ID" "$TARGET" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
    > "$STATE_DIR/KPM_INSTALL_OK" 2>/dev/null || true

echo "GhostGuard Native Probe 0.1.0 installed."
echo "Safety mode: read-only input metadata probe; Protect is OFF."
echo "Existing GhostGuard/reader packages were not modified."
exit 0
