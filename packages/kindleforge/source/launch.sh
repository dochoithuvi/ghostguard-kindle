#!/bin/sh
set -u

APP_ID="xyz.penguins184.kindleforge"
RUNTIME="/var/local/mesquite/KindleForge.kpm-launch.sh"

[ -x "$RUNTIME" ] || { echo "KindleForge launch: runtime wrapper missing" >&2; exit 1; }
command -v lipc-set-prop >/dev/null 2>&1 || { echo "KindleForge launch: lipc-set-prop not found" >&2; exit 1; }

# appreg points the KindleForge application at the KPM runtime wrapper. Starting
# through appmgr therefore applies any bundle downloaded by Update KForge before
# Mesquite is launched.
lipc-set-prop com.lab126.appmgrd start "app://$APP_ID" >/dev/null 2>&1 || {
    echo "KindleForge launch: appmgrd refused start request" >&2
    exit 1
}
exit 0
