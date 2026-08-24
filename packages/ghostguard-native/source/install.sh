#!/bin/sh
set -eu

ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
RUNTIME="/var/local/mesquite/GhostGuardNative.kpm-launch.sh"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"
DB="/var/local/appreg.db"
STATE_DIR="$ROOT/.dcpro_ghostguard_native"
LAUNCHER="$ROOT/documents/DCPRO_GhostGuard_Native.sh"
ASSET_DIR="$ROOT/dcpro/ghostguard-native/assets"
LIBRARY_COVER="$ASSET_DIR/ghostguard_native_library_600x960.jpg"
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
    [ -f "$1/style.css" ] && [ -f "$1/script.js" ] && [ -f "$1/watch.sh" ]
}

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 not found"
command -v lipc-set-prop >/dev/null 2>&1 || fail "lipc-set-prop not found"
[ -x /usr/bin/mesquite ] || fail "Mesquite runtime not found"
[ -f "$DB" ] || fail "appreg.db not found"
valid_payload "payload/GhostGuardNative" || fail "Mesquite payload incomplete"
[ -f runtime.sh ] || fail "runtime.sh missing"
[ -f probe.sh ] || fail "probe.sh missing"
[ -f scriptlets/DCPRO_GhostGuard_Native.sh ] || fail "Library launcher missing"
[ -f assets/ghostguard_native_library_600x960.jpg ] || fail "Library cover missing"

REGISTERED_BEFORE="$(sqlite3 "$DB" "SELECT COUNT(*) FROM handlerIds WHERE handlerId='$APP_ID';" 2>/dev/null || echo 0)"
[ "$REGISTERED_BEFORE" = "1" ] || REGISTERED_BEFORE=0

# Native owns only its private Mesquite target, wrappers, app registration,
# Library launcher and state directory. Stable KOReader GhostGuard and
# KindleForge stay untouched.
cleanup_staging
rm -rf "$BACKUP" 2>/dev/null || true
rm -f "$RUNTIME_BACKUP" "$PROBE_BACKUP" 2>/dev/null || true

cp -Rp payload/GhostGuardNative "$STAGING" || fail "cannot stage Mesquite payload"
chmod 755 "$STAGING/watch.sh" 2>/dev/null || fail "cannot make passive watcher executable"
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
mkdir -p "$ROOT/documents" "$ASSET_DIR" || fail "cannot create Library launcher directories"

# Match the stable GhostGuard Library behavior: put the cover in place before
# rewriting/touching the .sh launcher so SH_Integration can index the tile with
# the same user-provided GhostGuard artwork instead of caching a blank entry.
COVER_TMP="$ASSET_DIR/.ghostguard_native_library_600x960.jpg.kpm-new.$$"
LAUNCHER_TMP="$ROOT/documents/.DCPRO_GhostGuard_Native.sh.kpm-new.$$"
rm -f "$COVER_TMP" "$LAUNCHER_TMP" 2>/dev/null || true
cp -p assets/ghostguard_native_library_600x960.jpg "$COVER_TMP" || fail "cannot stage Library cover"
chmod 644 "$COVER_TMP" 2>/dev/null || true
mv -f "$COVER_TMP" "$LIBRARY_COVER" || fail "cannot install Library cover"
sync 2>/dev/null || true

cp -p scriptlets/DCPRO_GhostGuard_Native.sh "$LAUNCHER_TMP" || fail "cannot stage Library launcher"
chmod 755 "$LAUNCHER_TMP" 2>/dev/null || true
mv -f "$LAUNCHER_TMP" "$LAUNCHER" || fail "cannot install Library launcher"
touch "$LAUNCHER" 2>/dev/null || true
sync 2>/dev/null || true

# Generate metadata immediately; passive event capture starts only when the
# Native control panel is launched from KPM or from the new Library icon.
"$PROBE" >/dev/null 2>&1 || true

printf 'PACKAGE_ID=ghostguard-native\nPACKAGE_VERSION=0.2.1\nMODE=PASSIVE_EVENT_WATCH\nAPP_ID=%s\nTARGET=%s\nLIBRARY_LAUNCHER=%s\nLIBRARY_COVER=%s\nINSTALLED_UTC=%s\n' \
    "$APP_ID" "$TARGET" "$LAUNCHER" "$LIBRARY_COVER" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
    > "$STATE_DIR/KPM_INSTALL_OK" 2>/dev/null || true

echo "GhostGuard Native 0.2.1 installed."
echo "Safety mode: passive read-only evdev watch; input grab and injection are OFF."
echo "GhostGuard Native Library launcher: $LAUNCHER"
echo "You can now open GhostGuard Native directly from the Kindle Library/Home."
echo "Existing GhostGuard/reader packages were not modified."
exit 0
