#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard/source"
OUT="$ROOT/packages/ghostguard/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.8.0
PKG="$OUT/ghostguard_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT" "$TMP/payload" "$TMP/scriptlets" "$TMP/assets" "$TMP/system"
cp "$SRC/manifest.json" "$TMP/manifest.json"
cp -R "$SRC/payload/dcghostguardpro.koplugin" "$TMP/payload/"
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/uninstall.sh" "$TMP/uninstall.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/scriptlets/DCPRO_GhostGuard.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
cp "$SRC/assets/ghostguard_library_600x960.jpg" "$TMP/assets/ghostguard_library_600x960.jpg"
cp "$SRC/system/ghostguard-service.sh" "$TMP/system/ghostguard-service.sh"
cp "$SRC/system/ghostguard-native-capture.sh" "$TMP/system/ghostguard-native-capture.sh"
cp "$SRC/system/dcpro-ghostguard.conf" "$TMP/system/dcpro-ghostguard.conf"

chmod +x "$TMP/install.sh" "$TMP/uninstall.sh" "$TMP/launch.sh" \
    "$TMP/scriptlets/DCPRO_GhostGuard.sh" \
    "$TMP/system/ghostguard-service.sh" "$TMP/system/ghostguard-native-capture.sh"

PLUGIN="$TMP/payload/dcghostguardpro.koplugin"
for f in _meta.lua main.lua ghostguard.lua ghostguard_core.lua defaults.lua profile_manager.lua \
    touch_observer.lua license_manager.lua keys/keyring.lua adaptive_bootstrap.lua \
    simpleui_bridge.lua zenui_bridge.lua system_service.lua; do
    test -f "$PLUGIN/$f"
done

grep -q 'version = "0.8.0"' "$PLUGIN/defaults.lua"
grep -q 'runtime_revision = "system-service-v1"' "$PLUGIN/defaults.lua"
grep -q 'GhostGuard v0.8.0' "$PLUGIN/_meta.lua"
grep -q 'controller fingerprint changed; fail-open' "$PLUGIN/ghostguard.lua"
grep -q 'system_service_resume_retry_delays' "$PLUGIN/defaults.lua"
grep -q 'controller identity unavailable after wake' "$PLUGIN/system_service.lua"
grep -q 'PENDING_RELEARN' "$PLUGIN/system_service.lua"
grep -q 'pid_is_ghostguard_service' "$TMP/system/ghostguard-service.sh"
grep -q 'marker is sticky until profile approval' "$TMP/system/ghostguard-service.sh"
grep -q 'pid_is_ghostguard_service' "$TMP/uninstall.sh"
grep -q 'INPUT_GRAB=OFF' "$TMP/system/ghostguard-service.sh"
grep -q 'EVENT_INJECTION=OFF' "$TMP/system/ghostguard-service.sh"
grep -q 'start on mounted_userstore' "$TMP/system/dcpro-ghostguard.conf"
grep -q 'respawn limit 3 60' "$TMP/system/dcpro-ghostguard.conf"
! grep -Eq 'EVIOCGRAB|/dev/uinput|uinput' "$TMP/system/ghostguard-service.sh"

if command -v luajit >/dev/null 2>&1; then
    for f in "$PLUGIN"/*.lua "$PLUGIN"/keys/*.lua; do
        luajit -b "$f" /dev/null
    done
fi

for f in "$TMP/install.sh" "$TMP/uninstall.sh" "$TMP/launch.sh" \
    "$TMP/system/ghostguard-service.sh" "$TMP/system/ghostguard-native-capture.sh"; do
    sh -n "$f"
done

rm -f "$PKG"
tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh uninstall.sh launch.sh scriptlets assets system
printf '%s\n' "$PKG"
