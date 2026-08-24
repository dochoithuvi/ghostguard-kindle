#!/bin/sh
set -u

APP_ID="com.dcpro.ghostguardnative"
RUNTIME="/var/local/mesquite/GhostGuardNative.kpm-launch.sh"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"
LAUNCH_LOG="$STATE_DIR/launch.log"

mkdir -p "$STATE_DIR" 2>/dev/null || true
log() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$*" >> "$LAUNCH_LOG" 2>/dev/null || true
}

[ -x "$RUNTIME" ] || { log "KPM_LAUNCH_FAIL runtime wrapper missing"; echo "GhostGuard Native launch: runtime wrapper missing" >&2; exit 1; }
command -v lipc-set-prop >/dev/null 2>&1 || { log "KPM_LAUNCH_FAIL lipc-set-prop missing"; echo "GhostGuard Native launch: lipc-set-prop not found" >&2; exit 1; }

log "KPM_LAUNCH request app://$APP_ID"
lipc-set-prop com.lab126.appmgrd start "app://$APP_ID" >> "$LAUNCH_LOG" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
    log "KPM_LAUNCH_FAIL appmgrd rc=$RC"
    echo "GhostGuard Native launch: appmgrd refused start request" >&2
    exit "$RC"
fi
log "KPM_LAUNCH accepted"
exit 0
