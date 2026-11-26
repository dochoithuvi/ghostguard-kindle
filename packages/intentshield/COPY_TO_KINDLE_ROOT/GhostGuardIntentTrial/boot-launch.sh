#!/bin/sh
# One attempt per boot, no respawn, no stopping the Amazon framework.
set -u
PATH=/bin:/sbin:/usr/bin:/usr/sbin; export PATH
ROOT=/mnt/us
# Upstart may start before user store is mounted. Never create a mountpoint.
i=0
while [ "$i" -lt 90 ]; do
    [ -d "$ROOT/documents" ] && [ -d "$ROOT/GhostGuardIntentTrial" ] && break
    i=$((i+1)); sleep 1
done
[ -d "$ROOT/documents" ] && [ -d "$ROOT/GhostGuardIntentTrial" ] || exit 2
REPORT="$ROOT/GhostGuard_Reports/IntentGate"
mkdir -p "$REPORT" || exit 2
LOG="$REPORT/boot.log"
[ ! -f "$LOG" ] || [ "$(wc -c < "$LOG")" -lt 65536 ] || mv "$LOG" "$LOG.previous"
exec >>"$LOG" 2>&1
log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail(){ log "REFUSE: $*"; exit 2; }
MODE=${1:-probe}
SERIAL=$(tr -d '\r\n' </proc/usid 2>/dev/null || :)
# Prefer system-owned sources. USB version text is a diagnostic fallback only.
FW_SOURCE=; FW_VALUE=
check_version() {
    label=$1; value=$2
    versions=$(printf '%s\n' "$value" | grep -Eo '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)*' | sed 's/^[^0-9]*//' | sort -u || :)
    [ -n "$versions" ] || return 0
    log "FW_SOURCE=$label versions=$(printf '%s' "$versions" | tr '\n' ' ')"
    # A readable source with conflicting/other versions is not overridden by a fallback.
    [ "$versions" = 5.18.6 ] || fail 'Firmware other than exact 5.18.6 or ambiguous version'
    FW_SOURCE=$label; FW_VALUE=5.18.6
}
for vf in /etc/prettyversion.txt /etc/version.txt; do
    if [ -r "$vf" ]; then check_version "$vf" "$(head -n 2 "$vf" 2>/dev/null || :)"; else log "FW_SOURCE=$vf unavailable"; fi
done
if command -v lipc-get-prop >/dev/null 2>&1; then
    check_version lipc-system-version "$(lipc-get-prop com.lab126.system version 2>/dev/null || :)"
fi
if [ -z "$FW_VALUE" ]; then
    for vf in "$ROOT/system/version.txt" /mnt/base-us/system/version.txt; do
        if [ -r "$vf" ]; then
            value=$(head -n 2 "$vf" 2>/dev/null || :)
            case "$value" in 'Kindle 5.18.6'|'Kindle 5.18.6 '*)
                # USB text is user-writable: require explicit confirmation of Device Info.
                if [ -f "$ROOT/CONFIRM_INTENTSHIELD_FW_5.18.6" ] && [ "$(cat "$ROOT/CONFIRM_INTENTSHIELD_FW_5.18.6" 2>/dev/null)" = '5.18.6' ]; then
                    check_version "$vf (user-confirmed)" "$value"
                else log "FW_SOURCE=$vf matches; verify Device Info and create confirmation marker"; fi;;
                *) log "FW_SOURCE=$vf unavailable or not exact Kindle 5.18.6";;
            esac
        fi
    done
fi
KR=
for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -f "$d/koreader.sh" ] && [ -f "$d/plugins/zenos.koplugin/main.lua" ] && [ -f "$d/plugins/dcprointentgate.koplugin/global_shield.lua" ]; then
        [ -z "$KR" ] || fail 'Multiple KOReader installations'
        KR=$d
    fi
done
case "$SERIAL" in G002AP*|G002AQ*|G092AP*|G092AQ*) ;; *) fail 'Basic 2022 serial prefix not verified';; esac
[ "$FW_VALUE" = 5.18.6 ] || fail 'Firmware 5.18.6 not verified; see FW_SOURCE diagnostics'
log "FW_VERIFIED=$FW_VALUE source=$FW_SOURCE"
[ -n "$KR" ] || fail 'KOReader, ZenOS or IntentShield missing'
command -v initctl >/dev/null || fail 'Upstart unavailable'
initctl status framework | grep -q 'start/running' || fail 'framework job not running'
log "PREFLIGHT_OK mode=$MODE KR=$KR"
[ "$MODE" != probe ] || exit 0
[ "$MODE" = boot ] || fail 'unknown mode'
[ -f "$ROOT/ENABLE_INTENTSHIELD_BOOT" ] && [ -f "$ROOT/ENABLE_INTENTSHIELD_GLOBAL" ] || fail 'not opted in'
[ ! -e "$ROOT/DISABLE_INTENTSHIELD_BOOT" ] && [ ! -e "$ROOT/DISABLE_INTENTGATE" ] || fail 'USB recovery marker'
BOOT=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || :)
case "$BOOT" in ''|*[!a-fA-F0-9-]*) fail 'boot ID unavailable';; esac
mkdir "/tmp/dcpro-intentshield-$BOOT.once" || fail 'already attempted this boot'
# Give stock UI time to become ready and allow recovery markers to be read.
sleep 20
[ -f "$ROOT/ENABLE_INTENTSHIELD_BOOT" ] && [ ! -e "$ROOT/DISABLE_INTENTSHIELD_BOOT" ] && [ ! -e "$ROOT/DISABLE_INTENTGATE" ] || fail 'cancelled during delay'
initctl status framework | grep -q 'start/running' || fail 'framework no longer running'
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*|*'/koreader.sh'*) fail 'KOReader may already be running';; esac
done
log 'Launch existing KOReader --asap; no framework stop'
cd "$KR" || fail 'cannot enter KOReader'
exec /bin/sh "$KR/koreader.sh" --asap
