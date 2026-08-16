#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"

# Resolve the actual KOReader root instead of assuming /mnt/us/koreader.
# Different KOReader installs may live under /mnt/us/koreader or /mnt/us/extensions/koreader.
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

fail() { echo "GhostGuard install: $1" >&2; rm -rf "$STAGING" 2>/dev/null || true; exit 1; }
[ -f "payload/dcghostguardpro.koplugin/main.lua" ] || fail "package payload incomplete"
[ -f "payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua" ] || fail "adaptive runtime missing"
mkdir -p "$DATA" || fail "cannot create data directory"
rm -rf "$STAGING"
cp -Rp "payload/dcghostguardpro.koplugin" "$STAGING" || fail "cannot stage plugin"

# Keep an existing paid per-device key only for backward compatibility.
# Online registry + verified cache is the normal activation path.
if [ -s "$TARGET/license.key" ]; then
    cp -p "$TARGET/license.key" "$STAGING/license.key" || fail "cannot preserve legacy license.key"
elif [ -s "$LICENSE_BACKUP" ]; then
    cp -p "$LICENSE_BACKUP" "$STAGING/license.key" || fail "cannot restore legacy license.key"
fi

# Install the adaptive runtime without replacing the large production main.lua.
if ! grep -q 'adaptive_bootstrap.lua' "$STAGING/main.lua" 2>/dev/null; then
    sed -i '/self.config, self.guard = config, guard_or_err/a\    pcall(function() dofile(plugin_dir .. "adaptive_bootstrap.lua")(self.guard, self.config) end)' "$STAGING/main.lua" 2>/dev/null \
      || fail "cannot install adaptive bootstrap hook"
fi

after_patch="$(grep -c 'adaptive_bootstrap.lua' "$STAGING/main.lua" 2>/dev/null || echo 0)"
[ "$after_patch" -ge 1 ] || fail "adaptive bootstrap hook verification failed"

rm -rf "$BACKUP"
if [ -d "$TARGET" ]; then mv "$TARGET" "$BACKUP" || fail "cannot backup previous plugin"; fi
if ! mv "$STAGING" "$TARGET"; then
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "cannot activate staged plugin"
fi

# Hard verification: KPM must not report success unless KOReader can actually see the plugin tree.
[ -d "$TARGET" ] && [ -f "$TARGET/main.lua" ] && [ -f "$TARGET/license_manager.lua" ] && [ -f "$TARGET/keys/keyring.lua" ] && [ -f "$TARGET/adaptive_bootstrap.lua" ] || {
    rm -rf "$TARGET"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    fail "active KOReader plugin verification failed"
}
rm -rf "$BACKUP"

cp -p "scriptlets/DCPRO_GhostGuard.sh" "$LAUNCHER" || fail "cannot install launcher"
[ ! -f "assets/ghostguard_library_600x960.jpg" ] || { mkdir -p "$ASSET_DIR" && cp -p "assets/ghostguard_library_600x960.jpg" "$ASSET_DIR/ghostguard_library_600x960.jpg"; } || true
chmod 755 "$LAUNCHER" 2>/dev/null || true
find "$TARGET/bin" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true

printf 'PACKAGE_ID=ghostguard\nKO_READER_ROOT=%s\nKO_READER_PLUGIN=%s\nLICENSE_FORMAT=4\nADAPTIVE_PROFILE=1\nINSTALLED_UTC=%s\n' "$KO_ROOT" "$TARGET" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$DATA/KPM_INSTALL_OK"
echo "GhostGuard installed. KOReader root: $KO_ROOT"
echo "GhostGuard plugin: $TARGET"
echo "GhostGuard installed. Restart KOReader before enabling GhostGuard."
exit 0
