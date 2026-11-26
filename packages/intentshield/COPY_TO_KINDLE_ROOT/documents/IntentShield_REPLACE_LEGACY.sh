#!/bin/sh
# Run only with KOReader closed; legacy plugin backup is outside plugins.
set -eu
ROOT=/mnt/us; BASE="$ROOT/GhostGuardIntentTrial"; REPORT="$ROOT/GhostGuard_Reports/IntentGate"
mkdir -p "$REPORT"; exec >>"$REPORT/install.log" 2>&1
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) echo 'Close KOReader completely first'; exit 1;; esac
done
KR=
for k in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -f "$k/koreader.sh" ] && [ -d "$k/plugins" ]; then [ -z "$KR" ] || exit 1; KR=$k; fi
done
[ -n "$KR" ] && [ -f "$KR/plugins/dcprointentgate.koplugin/global_shield.lua" ] || { echo 'Install IntentShield first'; exit 1; }
OLD="$KR/plugins/dcghostguardpro.koplugin"
[ -d "$OLD" ] || { echo 'Legacy plugin already absent'; exit 0; }
B="$BASE/legacy-ghostguard-$(date +%Y%m%d-%H%M%S)-$$"
[ ! -e "$B" ] || exit 1
mv "$OLD" "$B"
printf '%s\n' "$B" > "$BASE/last-legacy-backup.txt"
# Disable the old optional Zen boot only; preserve all old settings and data.
if [ -e "$ROOT/ENABLE_GHOSTGUARD_ZEN_BOOT" ]; then mv "$ROOT/ENABLE_GHOSTGUARD_ZEN_BOOT" "$B/ENABLE_GHOSTGUARD_ZEN_BOOT.saved"; fi
# Legacy native shadow service is read-only; disable separately if desired.
echo "Legacy plugin moved to $B. License/profile retained. Native shadow service untouched."
sync
