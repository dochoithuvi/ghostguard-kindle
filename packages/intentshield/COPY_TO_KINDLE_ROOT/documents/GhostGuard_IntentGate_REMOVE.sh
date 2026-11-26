#!/bin/sh
set -eu
ROOT=/mnt/us
touch "$ROOT/DISABLE_INTENTSHIELD_BOOT" "$ROOT/DISABLE_INTENTGATE"
rm -f "$ROOT/ENABLE_INTENTSHIELD_BOOT" "$ROOT/ENABLE_INTENTSHIELD_GLOBAL"
REPORT="$ROOT/GhostGuard_Reports/IntentGate"
mkdir -p "$REPORT"
exec >>"$REPORT/install.log" 2>&1
# First set kill switch: no new trial can start until removed manually.
printf '%s\n' 'IntentGate disabled' > "$ROOT/DISABLE_INTENTGATE"
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) echo 'Close KOReader first; disable marker set'; exit 1;; esac
done
N=0
for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    T="$d/plugins/dcprointentgate.koplugin"
    if [ -d "$T" ]; then
        B="$ROOT/GhostGuardIntentTrial/removed-$(date +%Y%m%d-%H%M%S)-$$-$N"
        mkdir -p "$ROOT/GhostGuardIntentTrial"
        mv "$T" "$B"
        echo "IntentGate removed to backup: $B"
        N=$((N+1))
    fi
done
sync
