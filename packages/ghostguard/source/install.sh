#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
TARGET="$ROOT/koreader/plugins/dcghostguardpro.koplugin"
STAGING="$ROOT/koreader/plugins/.dcghostguardpro.kpm-new.$$"
BACKUP="$ROOT/koreader/plugins/.dcghostguardpro.kpm-old"
DATA="$ROOT/.dcpro_ghostguard"
LICENSE_BACKUP="$DATA/license.key.kpm-backup"
LAUNCHER="$ROOT/documents/DCPRO_GhostGuard.sh"
ASSET_DIR="$ROOT/dcpro/ghostguard/assets"

fail() { echo "GhostGuard install: $1" >&2; rm -rf "$STAGING" 2>/dev/null || true; exit 1; }
[ -d "$ROOT/koreader/plugins" ] || fail "KOReader plugins directory not found"
[ -f "payload/dcghostguardpro.koplugin/main.lua" ] || fail "package payload incomplete"
mkdir -p "$DATA" || fail "cannot create data directory"
rm -rf "$STAGING"
cp -Rp "payload/dcghostguardpro.koplugin" "$STAGING" || fail "cannot stage plugin"

# Keep an existing paid per-device license across KPM updates.
if [ -s "$TARGET/license.key" ]; then
    cp -p "$TARGET/license.key" "$STAGING/license.key" || fail "cannot preserve license.key"
elif [ -s "$LICENSE_BACKUP" ]; then
    cp -p "$LICENSE_BACKUP" "$STAGING/license.key" || fail "cannot restore backed-up license.key"
fi

rm -rf "$BACKUP"
if [ -d "$TARGET" ]; then mv "$TARGET" "$BACKUP" || fail "cannot backup previous plugin"; fi
if ! mv "$STAGING" "$TARGET"; then
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "cannot activate staged plugin"
fi
[ -f "$TARGET/main.lua" ] && [ -f "$TARGET/license_manager.lua" ] && [ -f "$TARGET/keys/keyring.lua" ] || {
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "active tree verification failed"
}
rm -rf "$BACKUP"
cp -p "scriptlets/DCPRO_GhostGuard.sh" "$LAUNCHER" || fail "cannot install launcher"
[ ! -f "assets/ghostguard_library_600x960.jpg" ] || { mkdir -p "$ASSET_DIR" && cp -p "assets/ghostguard_library_600x960.jpg" "$ASSET_DIR/ghostguard_library_600x960.jpg"; } || true
chmod 755 "$LAUNCHER" 2>/dev/null || true
find "$TARGET/bin" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true
printf 'PACKAGE_ID=ghostguard\nLICENSE_FORMAT=4\nINSTALLED_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$DATA/KPM_INSTALL_OK"
echo "GhostGuard installed. Restart KOReader before enabling GhostGuard."
exit 0
