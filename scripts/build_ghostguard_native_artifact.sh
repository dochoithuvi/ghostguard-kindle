#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard-native/source"
OUT="$ROOT/packages/ghostguard-native/artifacts"
STABLE_LAUNCHER="$ROOT/packages/ghostguard/source/scriptlets/DCPRO_GhostGuard.sh"
STABLE_COVER="$ROOT/packages/ghostguard/source/assets/ghostguard_library_600x960.jpg"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.2.2
PKG="$OUT/ghostguard-native_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"

for f in manifest.json install.sh launch.sh uninstall.sh runtime.sh probe.sh README.md; do
    [ -f "$SRC/$f" ] || { echo "GhostGuard Native build: missing $f" >&2; exit 1; }
done
for f in config.xml index.html style.css script.js watch.sh; do
    [ -f "$SRC/payload/GhostGuardNative/$f" ] || { echo "GhostGuard Native build: missing payload/$f" >&2; exit 1; }
done
[ -f "$STABLE_LAUNCHER" ] || { echo "GhostGuard Native build: stable GhostGuard launcher/icon source missing" >&2; exit 1; }
[ -f "$STABLE_COVER" ] || { echo "GhostGuard Native build: stable GhostGuard Library artwork missing" >&2; exit 1; }

for script in "$SRC/install.sh" "$SRC/launch.sh" "$SRC/uninstall.sh" "$SRC/runtime.sh" "$SRC/probe.sh" "$SRC/payload/GhostGuardNative/watch.sh"; do
    sh -n "$script"
done

# v0.2.x may read a selected event node, but it must remain passive: no input
# grabs, no uinput injection and no references to stable KOReader internals.
if grep -Ei 'EVIOCGRAB|/dev/uinput|/mnt/us/koreader|dcghostguardpro\.koplugin' \
    "$SRC/install.sh" "$SRC/launch.sh" "$SRC/uninstall.sh" "$SRC/runtime.sh" >/dev/null 2>&1; then
    echo "GhostGuard Native build: prohibited invasive/stable-path reference" >&2
    exit 1
fi
if grep -Ei 'EVIOCGRAB|/dev/uinput' "$SRC/payload/GhostGuardNative/watch.sh" | grep -v '^.*echo ' >/dev/null 2>&1; then
    echo "GhostGuard Native build: passive watcher contains invasive input operation" >&2
    exit 1
fi

grep -q '"id": "ghostguard-native"' "$SRC/manifest.json"
grep -q '"version": \[0, 2, 2\]' "$SRC/manifest.json"
grep -q 'version="1.0"' "$SRC/payload/GhostGuardNative/config.xml"
grep -q 'kindle:permission name="local-port-access"' "$SRC/payload/GhostGuardNative/config.xml"
grep -q 'param name="messaging" value="yes"' "$SRC/payload/GhostGuardNative/config.xml"
grep -q 'MODE=READ_ONLY_METADATA' "$SRC/probe.sh"
grep -q 'EVENT_NODE_OPEN=NO' "$SRC/probe.sh"
grep -q 'MODE=PASSIVE_EVENT_WATCH' "$SRC/payload/GhostGuardNative/watch.sh"
grep -q 'EVENT_NODE_OPEN=READ_ONLY' "$SRC/payload/GhostGuardNative/watch.sh"
grep -q 'INPUT_GRAB=OFF' "$SRC/payload/GhostGuardNative/watch.sh"
grep -q 'EVENT_INJECTION=OFF' "$SRC/payload/GhostGuardNative/watch.sh"
grep -q 'dd if="$DEVICE"' "$SRC/payload/GhostGuardNative/watch.sh"
grep -q 'STATE_DIR="/mnt/us/.dcpro_ghostguard_native"' "$SRC/runtime.sh"
grep -q 'LAUNCH_LOG="$STATE_DIR/launch.log"' "$SRC/runtime.sh"
grep -q 'MESQUITE_EXIT rc=' "$SRC/runtime.sh"

mkdir -p "$OUT"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp "$SRC/manifest.json" "$TMP/manifest.json"
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/uninstall.sh" "$TMP/uninstall.sh"
cp "$SRC/runtime.sh" "$TMP/runtime.sh"
cp "$SRC/probe.sh" "$TMP/probe.sh"
cp "$SRC/README.md" "$TMP/README.md"
cp -Rp "$SRC/payload" "$TMP/payload"
mkdir -p "$TMP/scriptlets" "$TMP/assets"

# Reuse the stable GhostGuard artwork, but keep Native's launcher and state
# entirely separate. The launcher records appmgr acceptance/failure so a
# return-to-Home can be diagnosed from USB without touching KOReader logs.
{
    sed -n '1,4p' "$STABLE_LAUNCHER" | sed 's/^# Name:.*/# Name: DCPRO GhostGuard Native/'
    cat <<'EOF'
APP_ID="com.dcpro.ghostguardnative"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"
LAUNCH_LOG="$STATE_DIR/launch.log"
mkdir -p "$STATE_DIR" 2>/dev/null || true
log() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$*" >> "$LAUNCH_LOG" 2>/dev/null || true
}
if command -v lipc-set-prop >/dev/null 2>&1; then
    log "LIBRARY_LAUNCH request app://$APP_ID"
    lipc-set-prop com.lab126.appmgrd start "app://$APP_ID" >> "$LAUNCH_LOG" 2>&1
    RC=$?
    log "LIBRARY_LAUNCH appmgrd_rc=$RC"
    exit "$RC"
fi
log "LIBRARY_LAUNCH_FAIL lipc-set-prop missing"
echo "GhostGuard Native launcher: lipc-set-prop not found" >&2
exit 1
EOF
} > "$TMP/scriptlets/DCPRO_GhostGuard_Native.sh"
cp -p "$STABLE_COVER" "$TMP/assets/ghostguard_native_library_600x960.jpg"

chmod 755 "$TMP/install.sh" "$TMP/launch.sh" "$TMP/uninstall.sh" "$TMP/runtime.sh" "$TMP/probe.sh" \
    "$TMP/payload/GhostGuardNative/watch.sh" "$TMP/scriptlets/DCPRO_GhostGuard_Native.sh"
chmod 644 "$TMP/assets/ghostguard_native_library_600x960.jpg" 2>/dev/null || true

# Build-time launcher regression: preserve the embedded PNG icon, use a Native
# title, launch only the Native Mesquite app and write only Native diagnostics.
grep -q '^# Name: DCPRO GhostGuard Native$' "$TMP/scriptlets/DCPRO_GhostGuard_Native.sh"
grep -q '^# Icon: data:image/png;base64,' "$TMP/scriptlets/DCPRO_GhostGuard_Native.sh"
grep -q 'app://\$APP_ID' "$TMP/scriptlets/DCPRO_GhostGuard_Native.sh"
grep -q 'com.dcpro.ghostguardnative' "$TMP/scriptlets/DCPRO_GhostGuard_Native.sh"
grep -q '/mnt/us/.dcpro_ghostguard_native' "$TMP/scriptlets/DCPRO_GhostGuard_Native.sh"
[ -s "$TMP/assets/ghostguard_native_library_600x960.jpg" ]

tar -C "$TMP" -czf "$PKG" manifest.json payload scriptlets assets install.sh launch.sh uninstall.sh runtime.sh probe.sh README.md
printf '%s\n' "$PKG"
