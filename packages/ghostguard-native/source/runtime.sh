#!/bin/sh
set -u

APP_ID="com.dcpro.ghostguardnative"
TARGET="/var/local/mesquite/GhostGuardNative"
PROBE="/var/local/mesquite/GhostGuardNative.kpm-probe.sh"
WATCH="$TARGET/watch.sh"

[ -d "$TARGET" ] || { echo "GhostGuard Native runtime: app payload missing" >&2; exit 1; }
[ -x /usr/bin/mesquite ] || { echo "GhostGuard Native runtime: Mesquite missing" >&2; exit 1; }

# Refresh metadata before the panel opens.
if [ -x "$PROBE" ]; then
    "$PROBE" >/dev/null 2>&1 || true
fi

# v0.2 starts one short-lived passive read-only capture. It does not grab the
# touchscreen, block Amazon's reader, or inject events. The watcher exits by
# itself after its capture window and is not a resident daemon.
if [ -x "$WATCH" ]; then
    "$WATCH" >/dev/null 2>&1 &
fi

exec /usr/bin/mesquite -l "$APP_ID" -c "file://$TARGET/"
