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
REPORT_DIR="$ROOT/GhostGuard_Reports"
LICENSE_BACKUP="$DATA/license.key.kpm-backup"
LEGACY_LAUNCHER="$ROOT/documents/DCPRO_GhostGuard.sh"
LEGACY_LAUNCHER_SDR="$LEGACY_LAUNCHER.sdr"
LEGACY_ASSET_DIR="$ROOT/dcpro/ghostguard/assets"
LEGACY_LIBRARY_COVER="$LEGACY_ASSET_DIR/ghostguard_library_600x960.jpg"
SERVICE_DIR="$DATA/service"
SERVICE_SCRIPT="$SERVICE_DIR/ghostguard-service.sh"
NATIVE_CAPTURE="$SERVICE_DIR/ghostguard-native-capture.sh"
NATIVE_SHADOW="$SERVICE_DIR/ghostguard-native-shadow.lua"
SERVICE_CONFIG="$SERVICE_DIR/config.env"
UPSTART_JOB="/etc/upstart/dcpro-ghostguard.conf"

fail() { echo "GhostGuard install: $1" >&2; rm -rf "$STAGING" 2>/dev/null || true; exit 1; }

copy_file_compat() {
    src="$1"; dst="$2"
    if cp -p "$src" "$dst" 2>/dev/null; then :
    elif cp "$src" "$dst" 2>/dev/null; then :
    elif cat "$src" > "$dst" 2>/dev/null; then :
    else return 1
    fi
    cmp "$src" "$dst" >/dev/null 2>&1
}

copy_tree_compat() {
    src="$1"; dst="$2"
    rm -rf "$dst" 2>/dev/null || true
    if cp -Rp "$src" "$dst" 2>/dev/null; then return 0; fi
    rm -rf "$dst" 2>/dev/null || true
    cp -R "$src" "$dst" 2>/dev/null
}

[ -f "payload/dcghostguardpro.koplugin/main.lua" ] || fail "package payload incomplete"
[ -f "payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua" ] || fail "adaptive runtime missing"
[ -f "payload/dcghostguardpro.koplugin/system_service.lua" ] || fail "system-service bridge missing"
[ -f "payload/dcghostguardpro.koplugin/goodix_crashshield.lua" ] || fail "Goodix crash shield missing"
[ -f "system/ghostguard-service.sh" ] || fail "system supervisor missing"
[ -f "system/ghostguard-native-capture.sh" ] || fail "integrated native diagnostics missing"
[ -f "system/ghostguard-native-shadow.lua" ] || fail "native shadow observer missing"
[ -f "system/dcpro-ghostguard.conf" ] || fail "Upstart job missing"
mkdir -p "$DATA" "$REPORT_DIR" || fail "cannot create data/report directory"
copy_tree_compat "payload/dcghostguardpro.koplugin" "$STAGING" || fail "cannot stage plugin"

if [ -s "$TARGET/license.key" ]; then
    copy_file_compat "$TARGET/license.key" "$STAGING/license.key" || fail "cannot preserve legacy license.key"
elif [ -s "$LICENSE_BACKUP" ]; then
    copy_file_compat "$LICENSE_BACKUP" "$STAGING/license.key" || fail "cannot restore legacy license.key"
fi

rm -rf "$BACKUP"
if [ -d "$TARGET" ]; then mv "$TARGET" "$BACKUP" || fail "cannot backup previous plugin"; fi
if ! mv "$STAGING" "$TARGET"; then
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "cannot activate staged plugin"
fi

[ -d "$TARGET" ] && [ -f "$TARGET/main.lua" ] && [ -f "$TARGET/_meta.lua" ] && \
[ -f "$TARGET/license_manager.lua" ] && [ -f "$TARGET/keys/keyring.lua" ] && \
[ -f "$TARGET/adaptive_bootstrap.lua" ] && [ -f "$TARGET/system_service.lua" ] && \
[ -f "$TARGET/goodix_crashshield.lua" ] || {
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "active KOReader plugin verification failed"
}
rm -rf "$BACKUP"

# Local-first cleanup. Reports stay outside /documents so Kindle Library does
# not index them as books. Remove obsolete Cloud/ZenUI leftovers without
# touching learned profiles or online-license cache.
rm -f \
  "$ROOT/documents/GhostGuard_ContinuousLearning_Status.txt" \
  "$ROOT/documents/GhostGuard_ContinuousLearning_Changes.log" \
  "$ROOT/documents/GhostGuard_ActiveProfile_AutoLearned.txt" \
  "$ROOT/documents/GhostGuard_MTGuard3_Install.txt" \
  "$ROOT/documents/GhostGuard_MTGuard3_Verify.txt" \
  "$ROOT/documents/GhostGuard_MTGuard4_Install.txt" \
  "$ROOT/documents/GhostGuard_MTGuard4_Verify.txt" \
  "$ROOT/documents/GhostGuard_MTGuard5_Install.txt" \
  "$ROOT/documents/GhostGuard_MTGuard5_Verify.txt" 2>/dev/null || true
rm -rf "$DATA/cloud_outbox" 2>/dev/null || true
rm -f "$DATA/cloud_target.txt" "$DATA/CLOUD_UPLOAD_STATUS.txt" \
      "$DATA/CLOUD_UPLOAD.lock" "$ROOT/documents/dochoithuvi_drive_token.conf" \
      2>/dev/null || true

# KOReader is now the only Library entry point. Remove the old DC-GhostGuard
# document launcher, SH_Integration cache and standalone cover from older builds.
# GhostGuard remains installed only as a KOReader plugin.
rm -f "$LEGACY_LAUNCHER" 2>/dev/null || true
rm -rf "$LEGACY_LAUNCHER_SDR" 2>/dev/null || true
rm -f "$LEGACY_LIBRARY_COVER" 2>/dev/null || true
rmdir "$LEGACY_ASSET_DIR" 2>/dev/null || true
rmdir "$ROOT/dcpro/ghostguard" 2>/dev/null || true
sync 2>/dev/null || true

mkdir -p "$SERVICE_DIR" || fail "cannot create service directory"
copy_file_compat "system/ghostguard-service.sh" "$SERVICE_SCRIPT" || fail "cannot install system supervisor"
copy_file_compat "system/ghostguard-native-capture.sh" "$NATIVE_CAPTURE" || fail "cannot install native diagnostic capture"
copy_file_compat "system/ghostguard-native-shadow.lua" "$NATIVE_SHADOW" || fail "cannot install native shadow observer"
chmod 755 "$SERVICE_SCRIPT" "$NATIVE_CAPTURE" 2>/dev/null || true
chmod 644 "$NATIVE_SHADOW" 2>/dev/null || true
if [ ! -f "$SERVICE_CONFIG" ]; then
    cat > "$SERVICE_CONFIG" <<'EOF'
# DCPRO GhostGuard v0.9.2 persistent service policy
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
    copy_file_compat "system/dcpro-ghostguard.conf" "$tmp" || ok=1
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

find "$TARGET/bin" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true

printf 'PACKAGE_ID=ghostguard\nPACKAGE_VERSION=0.9.2\nRUNTIME=MTGUARD5_ADAPTIVE_V3\nKO_READER_ROOT=%s\nKO_READER_PLUGIN=%s\nLICENSE_FORMAT=4\nADAPTIVE_PROFILE=1\nADAPTIVE_AUTO_PROMOTE=1\nADAPTIVE_CHECKPOINT_SAMPLES=4\nADAPTIVE_CHECKPOINT_SECONDS=30\nADAPTIVE_EXTERNAL_REPORT_SECONDS=5\nADAPTIVE_PROMOTION_MIN_CLUSTER=4\nADAPTIVE_PROMOTION_MIN_AGE_SECONDS=15\nMT_GUARD=1\nGOODIX_CRASH_SHIELD=1\nTOUCH_SHIELD_MODE=PASS_THROUGH_SAFE\nSYSTEM_SERVICE=1\nSYSTEM_SERVICE_STARTED=%s\nUPSTART_INSTALLED=%s\nUPSTART_JOB=%s\nNATIVE_INTEGRATED=1\nNATIVE_SHADOW=1\nNATIVE_FILTER=SHADOW_ONLY\nINPUT_GRAB=OFF\nEVENT_INJECTION=OFF\nLIBRARY_ENTRY=KO_READER_ONLY\nGHOSTGUARD_LIBRARY_LAUNCHER=REMOVED\nGHOSTGUARD_LIBRARY_ICON=REMOVED\nREPORT_DIR=%s\nREPORT_MODE=LOCAL_ONLY_NON_LIBRARY\nCLOUD_UPLOAD=REMOVED\nZENUI=REMOVED\nINSTALL_MODE=ATOMIC_REPLACE_FAIL_OPEN_SERVICE\nCOPY_MODE=PRESERVE_WITH_CONTENT_FALLBACK\nINSTALLED_UTC=%s\n' \
    "$KO_ROOT" "$TARGET" "$SERVICE_STARTED" "$UPSTART_OK" "$UPSTART_JOB" "$REPORT_DIR" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$DATA/KPM_INSTALL_OK"

echo "GhostGuard v0.9.2 package installed. KOReader root: $KO_ROOT"
echo "GhostGuard plugin: $TARGET"
echo "GhostGuard Goodix crash shield: enabled (pass-through safe outside Protect)"
echo "GhostGuard system supervisor: $SERVICE_SCRIPT"
echo "GhostGuard Native diagnostics integrated: $NATIVE_CAPTURE"
echo "GhostGuard Native shadow observer: $NATIVE_SHADOW (read-only, event-driven)"
echo "Kindle Library entry: KOReader only; legacy DC-GhostGuard icon removed."
echo "Continuous learning: faster checkpoint/report/promotion cadence with unchanged Protect thresholds."
echo "Reports: $REPORT_DIR (local-only; kept outside Kindle Library indexing)."
if [ "$UPSTART_OK" = "1" ]; then echo "GhostGuard supervisor on Kindle boot: enabled via $UPSTART_JOB"
else echo "GhostGuard supervisor Upstart unavailable; current-boot supervisor started fail-open."; fi
echo "KPM copy compatibility: metadata-preserving copy falls back to verified content copy on /mnt/us."
echo "Safety: Native filter is SHADOW_ONLY; input grab/injection are OFF; actual blocking remains in the tested KOReader bridge."
echo "Use the KOReader icon to enter GhostGuard."
exit 0
