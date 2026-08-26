#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"

KO_ROOT=""
for candidate in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -d "$candidate/plugins" ]; then KO_ROOT="$candidate"; break; fi
done
[ -n "$KO_ROOT" ] || { echo "GhostGuard install: KOReader plugins directory not found" >&2; exit 1; }

TARGET="$KO_ROOT/plugins/dcghostguardpro.koplugin"
STAGING="$KO_ROOT/plugins/.dcghostguardpro.kpm-new.$$"
BACKUP="$KO_ROOT/plugins/.dcghostguardpro.kpm-old"
DATA="$ROOT/.dcpro_ghostguard"
LICENSE_BACKUP="$DATA/license.key.kpm-backup"
LAUNCHER="$ROOT/documents/DCPRO_GhostGuard.sh"
LAUNCHER_SDR="$LAUNCHER.sdr"
ASSET_DIR="$ROOT/dcpro/ghostguard/assets"
LIBRARY_COVER="$ASSET_DIR/ghostguard_library_600x960.jpg"
SERVICE_DIR="$DATA/service"
SERVICE_SCRIPT="$SERVICE_DIR/ghostguard-service.sh"
NATIVE_CAPTURE="$SERVICE_DIR/ghostguard-native-capture.sh"
NATIVE_SHADOW="$SERVICE_DIR/ghostguard-native-shadow.lua"
SERVICE_CONFIG="$SERVICE_DIR/config.env"
UPSTART_JOB="/etc/upstart/dcpro-ghostguard.conf"

fail() { echo "GhostGuard install: $1" >&2; rm -rf "$STAGING" 2>/dev/null || true; exit 1; }
[ -f "payload/dcghostguardpro.koplugin/main.lua" ] || fail "package payload incomplete"
[ -f "payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua" ] || fail "adaptive runtime missing"
[ -f "payload/dcghostguardpro.koplugin/system_service.lua" ] || fail "system-service bridge missing"
[ -f "system/ghostguard-service.sh" ] || fail "system supervisor missing"
[ -f "system/ghostguard-native-capture.sh" ] || fail "integrated native diagnostics missing"
[ -f "system/ghostguard-native-shadow.lua" ] || fail "native shadow observer missing"
[ -f "system/dcpro-ghostguard.conf" ] || fail "Upstart job missing"
mkdir -p "$DATA" || fail "cannot create data directory"
rm -rf "$STAGING"
cp -Rp "payload/dcghostguardpro.koplugin" "$STAGING" || fail "cannot stage plugin"

if [ -s "$TARGET/license.key" ]; then
    cp -p "$TARGET/license.key" "$STAGING/license.key" || fail "cannot preserve legacy license.key"
elif [ -s "$LICENSE_BACKUP" ]; then
    cp -p "$LICENSE_BACKUP" "$STAGING/license.key" || fail "cannot restore legacy license.key"
fi

rm -rf "$BACKUP"
if [ -d "$TARGET" ]; then mv "$TARGET" "$BACKUP" || fail "cannot backup previous plugin"; fi
if ! mv "$STAGING" "$TARGET"; then
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "cannot activate staged plugin"
fi

[ -d "$TARGET" ] && [ -f "$TARGET/main.lua" ] && [ -f "$TARGET/_meta.lua" ] && \
[ -f "$TARGET/license_manager.lua" ] && [ -f "$TARGET/keys/keyring.lua" ] && \
[ -f "$TARGET/adaptive_bootstrap.lua" ] && [ -f "$TARGET/system_service.lua" ] || {
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "active KOReader plugin verification failed"
}
rm -rf "$BACKUP"

mkdir -p "$SERVICE_DIR" || fail "cannot create service directory"
cp -p "system/ghostguard-service.sh" "$SERVICE_SCRIPT" || fail "cannot install system supervisor"
cp -p "system/ghostguard-native-capture.sh" "$NATIVE_CAPTURE" || fail "cannot install native diagnostic capture"
cp -p "system/ghostguard-native-shadow.lua" "$NATIVE_SHADOW" || fail "cannot install native shadow observer"
chmod 755 "$SERVICE_SCRIPT" "$NATIVE_CAPTURE" 2>/dev/null || true
chmod 644 "$NATIVE_SHADOW" 2>/dev/null || true
if [ ! -f "$SERVICE_CONFIG" ]; then
    cat > "$SERVICE_CONFIG" <<'EOF'
# DCPRO GhostGuard v0.9 persistent service policy
ENABLED=1
AUTOSTART=1
RESUME_AFTER_WAKE=1
PAUSE_DURING_SLEEP=1
NATIVE_SHADOW=1
DESIRED_MODE=AUTO
EOF
fi

install_upstart_job() {
    [ -d /etc/upstart ] || return 1
    method=""
    if command -v mntroot >/dev/null 2>&1 && mntroot rw >/dev/null 2>&1; then method="mntroot"
    elif mount -o remount,rw / >/dev/null 2>&1; then method="mount"
    else return 1; fi
    tmp="${UPSTART_JOB}.new.$$"; ok=0
    cp -p "system/dcpro-ghostguard.conf" "$tmp" 2>/dev/null || ok=1
    if [ "$ok" = "0" ]; then chmod 644 "$tmp" 2>/dev/null || true; mv -f "$tmp" "$UPSTART_JOB" 2>/dev/null || ok=1; fi
    rm -f "$tmp" 2>/dev/null || true
    if [ "$method" = "mntroot" ]; then mntroot ro >/dev/null 2>&1 || true
    else mount -o remount,ro / >/dev/null 2>&1 || true; fi
    [ "$ok" = "0" ]
}

UPSTART_OK=0
if install_upstart_job; then UPSTART_OK=1; fi
SERVICE_STARTED=0
if [ "$UPSTART_OK" = "1" ] && command -v initctl >/dev/null 2>&1; then
    initctl stop dcpro-ghostguard >/dev/null 2>&1 || true
    if initctl start dcpro-ghostguard >/dev/null 2>&1; then SERVICE_STARTED=1; fi
fi
if [ "$SERVICE_STARTED" = "0" ]; then /bin/sh "$SERVICE_SCRIPT" >/dev/null 2>&1 & SERVICE_STARTED=1; fi

# v0.8.1 Library icon fix retained in v0.8.2.
[ -f "assets/ghostguard_library_600x960.jpg" ] || fail "library cover missing from package"
mkdir -p "$ASSET_DIR" || fail "cannot create library cover directory"
cp -p "assets/ghostguard_library_600x960.jpg" "$LIBRARY_COVER" || fail "cannot install library cover"
chmod 666 "$LIBRARY_COVER" 2>/dev/null || true
sync 2>/dev/null || true

LAUNCHER_TMP="$DATA/DCPRO_GhostGuard.launcher.$$"
rm -f "$LAUNCHER_TMP" 2>/dev/null || true
awk -v icon="$LIBRARY_COVER" '
    /^# Icon: / { print "# Icon: " icon; next }
    { print }
' "scriptlets/DCPRO_GhostGuard.sh" > "$LAUNCHER_TMP" || fail "cannot stage launcher"
grep -Fq "# Icon: $LIBRARY_COVER" "$LAUNCHER_TMP" || fail "file-backed icon header missing"
chmod 755 "$LAUNCHER_TMP" 2>/dev/null || true

rm -f "$LAUNCHER" 2>/dev/null || true
rm -rf "$LAUNCHER_SDR" 2>/dev/null || true
sync 2>/dev/null || true
sleep 2
cp -p "$LAUNCHER_TMP" "$LAUNCHER" || fail "cannot install launcher"
rm -f "$LAUNCHER_TMP" 2>/dev/null || true
chmod 755 "$LAUNCHER" 2>/dev/null || true
touch "$LAUNCHER" 2>/dev/null || true
sync 2>/dev/null || true

find "$TARGET/bin" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true

printf 'PACKAGE_ID=ghostguard\nPACKAGE_VERSION=0.9.0\nKO_READER_ROOT=%s\nKO_READER_PLUGIN=%s\nLICENSE_FORMAT=4\nADAPTIVE_PROFILE=1\nSYSTEM_SERVICE=1\nSYSTEM_SERVICE_STARTED=%s\nUPSTART_INSTALLED=%s\nUPSTART_JOB=%s\nNATIVE_INTEGRATED=1\nNATIVE_SHADOW=1\nNATIVE_FILTER=SHADOW_ONLY\nINPUT_GRAB=OFF\nEVENT_INJECTION=OFF\nLIBRARY_LAUNCHER=%s\nLIBRARY_COVER=%s\nLIBRARY_ICON_MODE=FILE_PATH_FORCE_REINDEX\nREPORT_MODE=LOCAL_ONLY\nCLOUD_UPLOAD=DISABLED_PUBLIC_BUILD\nINSTALL_MODE=ATOMIC_REPLACE_FAIL_OPEN_SERVICE\nINSTALLED_UTC=%s\n' \
    "$KO_ROOT" "$TARGET" "$SERVICE_STARTED" "$UPSTART_OK" "$UPSTART_JOB" "$LAUNCHER" "$LIBRARY_COVER" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$DATA/KPM_INSTALL_OK"

echo "GhostGuard v0.9.0 installed. KOReader root: $KO_ROOT"
echo "GhostGuard plugin: $TARGET"
echo "GhostGuard system supervisor: $SERVICE_SCRIPT"
echo "GhostGuard Native diagnostics integrated: $NATIVE_CAPTURE"
echo "GhostGuard Native shadow observer: $NATIVE_SHADOW (read-only, event-driven)"
echo "GhostGuard Library icon: $LIBRARY_COVER (forced clean re-index)"
echo "Reports: local-only in public build; no Cloud .conf file is required."
if [ "$UPSTART_OK" = "1" ]; then echo "Auto-start on Kindle boot: enabled via $UPSTART_JOB"
else echo "Auto-start on Kindle boot: Upstart install unavailable; current-boot supervisor started fail-open."; fi
echo "Safety: Native filter is SHADOW_ONLY; input grab/injection are OFF; actual blocking remains in the tested KOReader bridge."
echo "Restart KOReader once after upgrading to v0.9.0."
exit 0
