#!/bin/sh
set -u

APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"
WATCH="$TARGET/watch.sh"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"
LAUNCH_LOG="$STATE_DIR/launch.log"

mkdir -p "$STATE_DIR" 2>/dev/null || true

log() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$*" >> "$LAUNCH_LOG" 2>/dev/null || true
}

[ -d "$TARGET" ] || { log "FAIL app payload missing: $TARGET"; exit 1; }
[ -x /usr/bin/mesquite ] || { log "FAIL Mesquite missing"; exit 1; }

log "START version=0.2.2 app_id=$APP_ID target=$TARGET"

# Refresh metadata before the panel opens. Failures stay non-fatal so a probe
# problem cannot prevent the control panel from opening.
if [ -x "$PROBE" ]; then
    "$PROBE" >> "$LAUNCH_LOG" 2>&1 || log "WARN metadata probe failed rc=$?"
else
    log "WARN probe wrapper missing"
fi

# Passive Watch remains short-lived and read-only. It never grabs the physical
# input device and never injects replacement events.
if [ -x "$WATCH" ]; then
    "$WATCH" >> "$LAUNCH_LOG" 2>&1 &
    log "WATCH started pid=$!"
else
    log "WARN passive watcher missing"
fi

# Do not exec here: retaining the wrapper lets us record Mesquite's exit code on
# devices where the app immediately falls back to Home.
/usr/bin/mesquite -l "$APP_ID" -c "file://$TARGET/" >> "$LAUNCH_LOG" 2>&1
RC=$?
log "MESQUITE_EXIT rc=$RC"
exit "$RC"
