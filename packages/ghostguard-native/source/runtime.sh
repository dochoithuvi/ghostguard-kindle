#!/bin/sh
set -u

APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"

[ -d "$TARGET" ] || { echo "GhostGuard Native runtime: app payload missing" >&2; exit 1; }
[ -x /usr/bin/mesquite ] || { echo "GhostGuard Native runtime: Mesquite missing" >&2; exit 1; }

# Refresh a read-only metadata snapshot before every control-panel launch.
# Probe v0.1.0 never opens event nodes and never grabs/injects input.
if [ -x "$PROBE" ]; then
    "$PROBE" >/dev/null 2>&1 || true
fi

exec /usr/bin/mesquite -l "$APP_ID" -c "file://$TARGET/"
