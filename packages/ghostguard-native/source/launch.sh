#!/bin/sh
set -u

APP_ID="com.dcpro.ghostguardnative"
RUNTIME="/var/local/mesquite/GhostGuardNative.kpm-launch.sh"

[ -x "$RUNTIME" ] || { echo "GhostGuard Native launch: runtime wrapper missing" >&2; exit 1; }
command -v lipc-set-prop >/dev/null 2>&1 || { echo "GhostGuard Native launch: lipc-set-prop not found" >&2; exit 1; }

lipc-set-prop com.lab126.appmgrd start "app://$APP_ID" >/dev/null 2>&1 || {
    echo "GhostGuard Native launch: appmgrd refused start request" >&2
    exit 1
}
exit 0
