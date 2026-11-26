#!/bin/sh
set -eu
ROOT=/mnt/us
BASE="$ROOT/GhostGuardIntentTrial"
REPORT="$ROOT/GhostGuard_Reports/IntentGate"
mkdir -p "$REPORT"
exec >>"$REPORT/install.log" 2>&1
printf '%s\n' 'IntentGate disabled during rollback' > "$ROOT/DISABLE_INTENTGATE"
touch "$ROOT/DISABLE_INTENTSHIELD_BOOT"
rm -f "$ROOT/ENABLE_INTENTSHIELD_BOOT" "$ROOT/ENABLE_INTENTSHIELD_GLOBAL"
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) echo 'Close KOReader first; disable marker set'; exit 1;; esac
done
KR=
for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -f "$d/koreader.sh" ] && [ -d "$d/plugins" ]; then
        [ -z "$KR" ] || exit 1
        KR="$d"
    fi
done
[ -n "$KR" ] || exit 1
B=$(cat "$BASE/last-1.0-backup.txt" 2>/dev/null || :)
case "$B" in "$BASE"/backup-before-1.0-*) ;; *) echo 'No valid 1.0 backup pointer'; exit 1;; esac
[ -f "$B/main.lua" ] || { echo 'No previous plugin backup'; exit 1; }
T="$KR/plugins/dcprointentgate.koplugin"
NEW="$BASE/rolled-back-1.0-$(date +%Y%m%d-%H%M%S)-$$"
[ ! -e "$T" ] || mv "$T" "$NEW"
if ! mv "$B" "$T"; then [ ! -e "$NEW" ] || mv "$NEW" "$T"; exit 1; fi
echo 'Rollback complete. DISABLE_INTENTGATE remains; remove via USB to enable trials.'
sync
