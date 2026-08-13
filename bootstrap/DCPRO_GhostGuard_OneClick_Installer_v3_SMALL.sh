#!/bin/sh
# Name: GhostGuard - Cai / Cap nhat
# Author: Do Choi Thu Vi
# DontUseFBInk
# DCPRO GhostGuard OneClick v3 SMALL
# Requires: KMC/KPM + KOReader + Wi-Fi
#
# UI: small FBInk text (-S 1), jailbreak-like.
# Full diagnostics:
#   /mnt/us/documents/GhostGuard_Installer.log

ROOT="/mnt/us"
REPO="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.json"
LOG="$ROOT/documents/GhostGuard_Installer.log"
TMP="$ROOT/.dcpro_ghostguard/bootstrap_tmp.log"

mkdir -p "$ROOT/.dcpro_ghostguard" 2>/dev/null || true
: > "$LOG" 2>/dev/null || true

log() {
    printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true
}

FBINK=""
for c in \
    /var/local/kmc/bin/fbink \
    /var/local/kmc/kindlehf/bin/fbink \
    /var/local/kmc/kindlepw2/bin/fbink
do
    if [ -x "$c" ]; then FBINK="$c"; break; fi
done
if [ -z "$FBINK" ]; then FBINK="$(command -v fbink 2>/dev/null || true)"; fi

clear_screen() {
    [ -n "$FBINK" ] || return 0
    "$FBINK" -k >/dev/null 2>&1 || "$FBINK" -S 1 -c " " >/dev/null 2>&1 || true
}
line() {
    if [ -n "$FBINK" ]; then
        "$FBINK" -S 1 -x 2 -y "$1" -r "$2" >/dev/null 2>&1 || true
    fi
}
fail() {
    log "ERROR: $*"
    line 13 "LOI: $*"
    line 15 "Log: documents/GhostGuard_Installer.log"
    sleep 8
    exit 1
}
runlog() {
    : > "$TMP" 2>/dev/null || true
    "$@" >"$TMP" 2>&1
    RC=$?
    cat "$TMP" >>"$LOG" 2>/dev/null || true
    printf '[exit=%s]\n' "$RC" >>"$LOG" 2>/dev/null || true
    return "$RC"
}

clear_screen
line 2  "DCPRO GhostGuard Installer"
line 4  "--------------------------------"
line 6  "[1/4] Kiem tra he thong..."

log "========================================"
log "DCPRO GhostGuard OneClick v3 SMALL"
log "Date: $(date)"
log "========================================"

KPM=""
KPM_KIND=""
if [ -x /var/local/kmc/bin/kpm ]; then
    KPM="/var/local/kmc/bin/kpm"
    KPM_KIND="generic"
elif [ -x /var/local/kmc/kindlehf/bin/kpm ]; then
    KPM="/var/local/kmc/kindlehf/bin/kpm"
    KPM_KIND="kindlehf"
elif [ -x /var/local/kmc/kindlepw2/bin/kpm ]; then
    KPM="/var/local/kmc/kindlepw2/bin/kpm"
    KPM_KIND="kindlepw2"
fi
[ -n "$KPM" ] || fail "Khong tim thay KPM/KMC"

case "$KPM_KIND" in
    kindlehf|kindlepw2)
        PLAT_DIR="$(dirname "$(dirname "$KPM")")"
        export LD_LIBRARY_PATH="$PLAT_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ;;
esac
log "KPM=$KPM ($KPM_KIND)"

if [ ! -x "$ROOT/extensions/koreader/bin/koreader.sh" ] && \
   [ ! -x "$ROOT/koreader/koreader.sh" ]; then
    fail "Chua tim thay KOReader"
fi

line 6  "[1/4] Kiem tra he thong... OK"
line 8  "[2/4] Cap nhat kho GhostGuard..."

if ! "$KPM" -y list-repo 2>/dev/null | grep -q 'dochoithuvi-ghostguard'; then
    runlog "$KPM" -y add-repo "$REPO" || fail "Khong them duoc repository"
else
    log "Repository already registered."
fi
runlog "$KPM" -y update || fail "Khong cap nhat duoc KPM index"
line 8  "[2/4] Cap nhat kho GhostGuard... OK"

line 10 "[3/4] Tai va cai GhostGuard..."
runlog "$KPM" -y install ghostguard || fail "Cai GhostGuard that bai"
line 10 "[3/4] Tai va cai GhostGuard... OK"

line 12 "[4/4] Dang mo KOReader..."
log "Launching ghostguard through KPM package launch hook."
"$KPM" -y launch ghostguard >>"$LOG" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    line 12 "[4/4] Mo KOReader... OK"
    line 14 "Hoan tat."
    exit 0
fi
fail "Khong mo duoc GhostGuard (exit=$RC)"
