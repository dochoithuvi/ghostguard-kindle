#!/bin/sh
# Offline installation for the separate IntentGate plugin; no firmware changes.
set -eu
ROOT=/mnt/us
BASE="$ROOT/GhostGuardIntentTrial"
REPORT="$ROOT/GhostGuard_Reports/IntentGate"
mkdir -p "$REPORT"
exec >>"$REPORT/install.log" 2>&1
log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail(){ log "FAIL: $*"; exit 1; }
log 'START IntentShield 1.0'
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) fail 'Close KOReader completely first';; esac
done
KR=
for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -f "$d/koreader.sh" ] && [ -d "$d/plugins" ]; then
        [ -z "$KR" ] || fail 'Multiple KOReader folders; use manual install'
        KR="$d"
    fi
done
[ -n "$KR" ] || fail 'KOReader missing'
[ -f "$KR/plugins/zenos.koplugin/main.lua" ] || fail 'ZenOS missing; install existing Zen Alpha first'
SRC="$BASE/dcprointentgate.koplugin"
T="$KR/plugins/dcprointentgate.koplugin"
[ ! -e "$T" ] || [ -d "$T" ] || fail 'Unexpected target type'
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum not available; use manual USB copy'
(cd "$SRC" && sha256sum -c "$BASE/SHA256SUMS") || fail 'Payload checksum mismatch'
S="$KR/plugins/.dcprointentgate-stage.$$"
trap 'rm -rf "$S"' EXIT
trap 'exit 130' HUP INT TERM
mkdir "$S"
for name in _meta.lua main.lua intent_gate.lua global_shield.lua; do cp "$SRC/$name" "$S/$name"; cmp "$SRC/$name" "$S/$name"; done
B="$BASE/backup-before-1.0-$(date +%Y%m%d-%H%M%S)-$$"
if [ -d "$T" ]; then
    [ ! -e "$B" ] || fail 'Backup already exists; keep it and use manual update'
    mv "$T" "$B" || fail 'Could not back up old IntentGate'
fi
if ! mv "$S" "$T"; then
    [ ! -d "$B" ] || mv "$B" "$T" || :
    fail 'Could not activate trial'
fi
printf '%s\n' "$B" > "$BASE/last-1.0-backup.txt"
log "Backup (if previous plugin existed): $B"
[ ! -e "$ROOT/DISABLE_INTENTGATE" ] || log 'Kill switch present; remove manually via USB only when ready' 
log "SUCCESS: $T; no changes to GhostGuard or ZenOS"
sync
