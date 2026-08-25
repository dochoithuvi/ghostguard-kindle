#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"

# Resolve the actual KOReader root instead of assuming /mnt/us/koreader.
KO_ROOT=""
for candidate in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -d "$candidate/plugins" ]; then
        KO_ROOT="$candidate"
        break
    fi
done
[ -n "$KO_ROOT" ] || { echo "GhostGuard install: KOReader plugins directory not found" >&2; exit 1; }

TARGET="$KO_ROOT/plugins/dcghostguardpro.koplugin"
STAGING="$KO_ROOT/plugins/.dcghostguardpro.kpm-new.$$"
BACKUP="$KO_ROOT/plugins/.dcghostguardpro.kpm-old"
DATA="$ROOT/.dcpro_ghostguard"
LICENSE_BACKUP="$DATA/license.key.kpm-backup"
LAUNCHER="$ROOT/documents/DCPRO_GhostGuard.sh"
ASSET_DIR="$ROOT/dcpro/ghostguard/assets"
LIBRARY_COVER="$ASSET_DIR/ghostguard_library_600x960.jpg"
SERVICE_DIR="$DATA/service"
SERVICE_SCRIPT="$SERVICE_DIR/ghostguard-service.sh"
NATIVE_CAPTURE="$SERVICE_DIR/ghostguard-native-capture.sh"
SERVICE_CONFIG="$SERVICE_DIR/config.env"
UPSTART_JOB="/etc/upstart/dcpro-ghostguard.conf"

fail() { echo "GhostGuard install: $1" >&2; rm -rf "$STAGING" 2>/dev/null || true; exit 1; }
[ -f "payload/dcghostguardpro.koplugin/main.lua" ] || fail "package payload incomplete"
[ -f "payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua" ] || fail "adaptive runtime missing"
[ -f "payload/dcghostguardpro.koplugin/system_service.lua" ] || fail "system-service bridge missing"
[ -f "system/ghostguard-service.sh" ] || fail "system supervisor missing"
[ -f "system/ghostguard-native-capture.sh" ] || fail "integrated native diagnostics missing"
[ -f "system/dcpro-ghostguard.conf" ] || fail "Upstart job missing"
mkdir -p "$DATA" || fail "cannot create data directory"
rm -rf "$STAGING"
cp -Rp "payload/dcghostguardpro.koplugin" "$STAGING" || fail "cannot stage plugin"

# Keep an existing paid per-device key only for backward compatibility.
if [ -s "$TARGET/license.key" ]; then
    cp -p "$TARGET/license.key" "$STAGING/license.key" || fail "cannot preserve legacy license.key"
elif [ -s "$LICENSE_BACKUP" ]; then
    cp -p "$LICENSE_BACKUP" "$STAGING/license.key" || fail "cannot restore legacy license.key"
fi

# IMPORTANT: never patch main.lua at install time. The published artifact must
# contain exactly the tested plugin source. Runtime/adaptive/system bootstrap is
# loaded by the plugin itself, not injected by KPM with sed.
rm -rf "$BACKUP"
if [ -d "$TARGET" ]; then mv "$TARGET" "$BACKUP" || fail "cannot backup previous plugin"; fi
if ! mv "$STAGING" "$TARGET"; then
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "cannot activate staged plugin"
fi

# Hard verification: KPM must not report success unless the exact KOReader
# plugin tree is active in the selected KOReader installation.
[ -d "$TARGET" ] && \
[ -f "$TARGET/main.lua" ] && \
[ -f "$TARGET/_meta.lua" ] && \
[ -f "$TARGET/license_manager.lua" ] && \
[ -f "$TARGET/keys/keyring.lua" ] && \
[ -f "$TARGET/adaptive_bootstrap.lua" ] && \
[ -f "$TARGET/system_service.lua" ] || {
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "active KOReader plugin verification failed"
}
rm -rf "$BACKUP"

# Install the v0.8 service/native layer in persistent userstore. This layer is
# deliberately fail-open and never grabs or injects input events.
mkdir -p "$SERVICE_DIR" || fail "cannot create service directory"
cp -p "system/ghostguard-service.sh" "$SERVICE_SCRIPT" || fail "cannot install system supervisor"
cp -p "system/ghostguard-native-capture.sh" "$NATIVE_CAPTURE" || fail "cannot install native diagnostic capture"
chmod 755 "$SERVICE_SCRIPT" "$NATIVE_CAPTURE" 2>/dev/null || true
if [ ! -f "$SERVICE_CONFIG" ]; then
    cat > "$SERVICE_CONFIG" <<'EOF'
# DCPRO GhostGuard v0.8 persistent service policy
ENABLED=1
AUTOSTART=1
RESUME_AFTER_WAKE=1
PAUSE_DURING_SLEEP=1
DESIRED_MODE=AUTO
EOF
fi

# Best-effort Upstart installation. A firmware/rootfs that refuses writes must
# not make GhostGuard fail installation or affect Kindle boot.
install_upstart_job() {
    [ -d /etc/upstart ] || return 1
    method=""
    if command -v mntroot >/dev/null 2>&1 && mntroot rw >/dev/null 2>&1; then
        method="mntroot"
    elif mount -o remount,rw / >/dev/null 2>&1; then
        method="mount"
    else
        return 1
    fi

    tmp="${UPSTART_JOB}.new.$$"
    ok=0
    cp -p "system/dcpro-ghostguard.conf" "$tmp" 2>/dev/null || ok=1
    if [ "$ok" = "0" ]; then
        chmod 644 "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$UPSTART_JOB" 2>/dev/null || ok=1
    fi
    rm -f "$tmp" 2>/dev/null || true

    if [ "$method" = "mntroot" ]; then
        mntroot ro >/dev/null 2>&1 || true
    else
        mount -o remount,ro / >/dev/null 2>&1 || true
    fi
    [ "$ok" = "0" ]
}

UPSTART_OK=0
if install_upstart_job; then UPSTART_OK=1; fi

# Start the supervisor for the current boot. init/upstart owns it on future
# boots; direct background start is a safe fallback when Upstart is unavailable.
SERVICE_STARTED=0
if [ "$UPSTART_OK" = "1" ] && command -v initctl >/dev/null 2>&1; then
    initctl stop dcpro-ghostguard >/dev/null 2>&1 || true
    if initctl start dcpro-ghostguard >/dev/null 2>&1; then SERVICE_STARTED=1; fi
fi
if [ "$SERVICE_STARTED" = "0" ]; then
    /bin/sh "$SERVICE_SCRIPT" >/dev/null 2>&1 &
    SERVICE_STARTED=1
fi

# SH_Integration reads the launcher header as soon as the .sh document is
# indexed. Put the cover in its final location first, then rewrite/touch the
# launcher so both fresh installs and reinstalls are indexed with a valid
# thumbnail instead of caching a blank Library tile.
[ -f "assets/ghostguard_library_600x960.jpg" ] || fail "library cover missing from package"
mkdir -p "$ASSET_DIR" || fail "cannot create library cover directory"
cp -p "assets/ghostguard_library_600x960.jpg" "$LIBRARY_COVER" || fail "cannot install library cover"
chmod 644 "$LIBRARY_COVER" 2>/dev/null || true
sync 2>/dev/null || true

LAUNCHER_TMP="$ROOT/documents/.DCPRO_GhostGuard.sh.kpm-new.$$"
rm -f "$LAUNCHER_TMP" 2>/dev/null || true
cp -p "scriptlets/DCPRO_GhostGuard.sh" "$LAUNCHER_TMP" || fail "cannot stage launcher"
chmod 755 "$LAUNCHER_TMP" 2>/dev/null || true
mv -f "$LAUNCHER_TMP" "$LAUNCHER" || fail "cannot install launcher"
touch "$LAUNCHER" 2>/dev/null || true
sync 2>/dev/null || true

find "$TARGET/bin" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true

printf 'PACKAGE_ID=ghostguard\nPACKAGE_VERSION=0.8.0\nKO_READER_ROOT=%s\nKO_READER_PLUGIN=%s\nLICENSE_FORMAT=4\nADAPTIVE_PROFILE=1\nSYSTEM_SERVICE=1\nSYSTEM_SERVICE_STARTED=%s\nUPSTART_INSTALLED=%s\nUPSTART_JOB=%s\nNATIVE_INTEGRATED=1\nINPUT_GRAB=OFF\nEVENT_INJECTION=OFF\nLIBRARY_LAUNCHER=%s\nLIBRARY_COVER=%s\nINSTALL_MODE=ATOMIC_REPLACE_FAIL_OPEN_SERVICE\nINSTALLED_UTC=%s\n' \
    "$KO_ROOT" "$TARGET" "$SERVICE_STARTED" "$UPSTART_OK" "$UPSTART_JOB" "$LAUNCHER" "$LIBRARY_COVER" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$DATA/KPM_INSTALL_OK"

echo "GhostGuard v0.8.0 installed. KOReader root: $KO_ROOT"
echo "GhostGuard plugin: $TARGET"
echo "GhostGuard system supervisor: $SERVICE_SCRIPT"
echo "GhostGuard Native diagnostics integrated: $NATIVE_CAPTURE"
if [ "$UPSTART_OK" = "1" ]; then
    echo "Auto-start on Kindle boot: enabled via $UPSTART_JOB"
else
    echo "Auto-start on Kindle boot: Upstart install unavailable; current-boot supervisor started fail-open."
fi
echo "Safety: system service input grab/injection are OFF; Protect remains in the tested KOReader bridge."
echo "Restart KOReader once after upgrading to v0.8.0."
exit 0
