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

fail() { echo "GhostGuard install: $1" >&2; rm -rf "$STAGING" 2>/dev/null || true; exit 1; }
[ -f "payload/dcghostguardpro.koplugin/main.lua" ] || fail "package payload incomplete"
[ -f "payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua" ] || fail "adaptive runtime missing"
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
# contain exactly the tested plugin source. Runtime/adaptive bootstrap is loaded
# by the plugin itself, not injected by KPM with sed.

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
[ -f "$TARGET/adaptive_bootstrap.lua" ] || {
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "active KOReader plugin verification failed"
}
rm -rf "$BACKUP"

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

printf 'PACKAGE_ID=ghostguard\nKO_READER_ROOT=%s\nKO_READER_PLUGIN=%s\nLICENSE_FORMAT=4\nADAPTIVE_PROFILE=1\nLIBRARY_LAUNCHER=%s\nLIBRARY_COVER=%s\nINSTALL_MODE=ATOMIC_REPLACE\nINSTALLED_UTC=%s\n' "$KO_ROOT" "$TARGET" "$LAUNCHER" "$LIBRARY_COVER" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$DATA/KPM_INSTALL_OK"
echo "GhostGuard installed. KOReader root: $KO_ROOT"
echo "GhostGuard plugin: $TARGET"
echo "GhostGuard Library launcher: $LAUNCHER"
echo "GhostGuard Library cover: $LIBRARY_COVER"
echo "GhostGuard installed. Restart KOReader before enabling GhostGuard."
exit 0
