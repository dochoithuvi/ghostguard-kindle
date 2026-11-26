#!/bin/sh
set -eu
ROOT=/mnt/us; BASE="$ROOT/GhostGuardIntentTrial"
# Ensure new Global/boot cannot start before restoring legacy.
touch "$ROOT/DISABLE_INTENTSHIELD_BOOT" "$ROOT/DISABLE_INTENTGATE"
rm -f "$ROOT/ENABLE_INTENTSHIELD_GLOBAL" "$ROOT/ENABLE_INTENTSHIELD_BOOT"
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) echo 'Close KOReader first'; exit 1;; esac
done
B=$(cat "$BASE/last-legacy-backup.txt" 2>/dev/null || :)
case "$B" in "$BASE"/legacy-ghostguard-*) ;; *) exit 1;; esac
[ -f "$B/main.lua" ] || exit 1
KR=
for k in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -f "$k/koreader.sh" ] && [ -d "$k/plugins" ]; then [ -z "$KR" ] || exit 1; KR=$k; fi
done
[ -n "$KR" ] && [ ! -e "$KR/plugins/dcghostguardpro.koplugin" ] || exit 1
mv "$B" "$KR/plugins/dcghostguardpro.koplugin"
echo 'Legacy restored; IntentShield remains disabled. Old boot marker not re-enabled.'
sync
