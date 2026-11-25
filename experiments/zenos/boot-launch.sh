#!/bin/sh
# GhostGuard ZenOS experimental one-shot launcher, KT5 / FW 5.18.6.
# No framework-stop, input grab, boot-loop restart, or system writes.
set -u
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
USB=/mnt/us
DATA="$USB/.dcpro_ghostguard"
ENABLE="$USB/ENABLE_GHOSTGUARD_ZEN_BOOT"
DISABLE="$USB/DISABLE_GHOSTGUARD_ZEN_BOOT"
LOGDIR="$USB/GhostGuard_Reports"
MODE="${1:-probe}"
if [ ! -d "$USB/documents" ]; then echo "User store not ready" >&2; exit 2; fi
mkdir -p "$LOGDIR" || exit 2
LOG="$LOGDIR/ZenOS-boot.log"
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 65536 ]; then
    mv -f "$LOG" "$LOG.previous" 2>/dev/null || :
fi
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
refuse() { log "REFUSE: $*"; echo "$*" >&2; exit 2; }
VERSION="$(cat /etc/prettyversion.txt /etc/version.txt 2>/dev/null || :)"
SERIAL="$(tr -d '\r\n' </proc/usid 2>/dev/null || :)"
MODEL_OK=0
case "$SERIAL" in G002AP*|G002AQ*|G092AP*|G092AQ*) MODEL_OK=1;; esac
FW_OK=0
printf '%s\n' "$VERSION" | grep -Eq '(^|[^0-9.])5\.18\.6([^0-9.]|$)' && FW_OK=1
KR=
for D in /mnt/us/koreader /mnt/base-us/koreader /mnt/us/extensions/koreader; do
    if [ -f "$D/koreader.sh" ] && [ -f "$D/plugins/zenos.koplugin/main.lua" ] &&
       [ -f "$D/plugins/dcghostguardpro.koplugin/main.lua" ]; then
        KR="$D"; break
    fi
done
log "MODE=$MODE MODEL_OK=$MODEL_OK FW_OK=$FW_OK KOReader=${KR:-missing}"
case "$MODE" in
probe)
    for J in framework lab126_gui kppmainapp; do
        initctl status "$J" >> "$LOG" 2>&1 || :
    done
    log "UPSTART_TEMPLATE_NOT_INSTALLED_BY_THIS_SCRIPT"
    echo "Report: $LOG"
    exit 0;;
manual|boot) ;;
*) refuse "Unknown mode";;
esac
[ "$MODEL_OK" -eq 1 ] && [ "$FW_OK" -eq 1 ] || refuse "Model/firmware not verified"
[ -n "$KR" ] || refuse "KOReader, ZenOS or GhostGuard missing"
[ ! -e "$DISABLE" ] || refuse "USB disable marker"
[ ! -e "$DATA/SAFE_MODE" ] || refuse "GhostGuard SAFE_MODE"
if [ "$MODE" = boot ]; then
    [ -f "$ENABLE" ] || refuse "Boot not opted in"
    [ -f "$DATA/ZEN_EARLY_PROTECT" ] || refuse "Zen early protection not opted in"
    # Once per boot, including unsuccessful launches. No respawn.
    BOOT="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || :)"
    case "$BOOT" in ""|*[!a-fA-F0-9-]*) refuse "Cannot verify boot ID";; esac
    mkdir "/tmp/ghostguard-zenos-$BOOT.once" 2>/dev/null || refuse "Already attempted this boot"
fi
# Avoid launching a second reader; conservative false positives are OK.
if ps w 2>/dev/null | grep -E '[l]uajit.*reader\.lua|[k]oreader\.sh' | grep -v 'boot-launch.sh' >/dev/null; then
    refuse "KOReader may already be running"
fi
log "Launching existing KOReader --asap; no framework stop"
cd "$KR" || refuse "Cannot enter KOReader directory"
exec /bin/sh "$KR/koreader.sh" --asap >> "$LOG" 2>&1
