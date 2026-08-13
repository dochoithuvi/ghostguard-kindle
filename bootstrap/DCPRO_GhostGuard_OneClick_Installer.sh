#!/bin/sh
# Name: GhostGuard - Cai / Cap nhat
# Author: Do Choi Thu Vi
# Icon: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAKQAAACkCAAAAAA83tqdAAAD+ElEQVR42u2d647cIAyFORHv/8qnP7ZVZyYh+PiSZFZEqlbqBvNhbHMJeMH2/GdrC3JBLsj7IfH3X+bT8xFba2ipkQ1MJ+S/nw/UJPb/wWdpcmiFfAzkqaPwEZBTX+bdkMZowxshhYDIeyDlkM3LIXFGglxMH+Q84qTGJA+kUU956tQhhbqzMEVIudoUTgnSVWMCph3S7wphJ7JCBvURK26DzOiygAgDZFoocQuaQqYOHk5hYKnJ50g8g0Q2oVfsELJyQaDKHkCijtBRQVdEJC5/qUxHDzUJHyGCBYalurnlcudhWtCqTpsmGVtFSMXp0mSQ8OctnkifCun1iNM9l2mvd78lQg06Z5in0twbVvAUccawnog4X4g5MXsO4m4py8EK3IXZ44ycWTWii+geZLTU+OEWOmUvR9xHGbnLtwAjlbreXkapJmHdsTjQ1qs2tS7vSYw4fvf9LTopu4+RxsD+MWq/KFOh7GFGzEvxSJkC5RZkhMUHcGgmKNAkjhAdw/b/Ljfr0q5JBhgPfc4ewQSbJAwjOIZzxM+gVOQ4fHOC2Qh+MmoT2spTi5MUh8fRqC0Oi95JL6z99sbp/CCzRRkN5k+6XC0KCdH8g5Sxj/K+qdpFmqRu/9Rnd1GbpO6jbO4dL++RG1Kuke5dua3eHgMlwpAXPgtyQS7IBbkgF+SCXJAL8kshcRkHfqcm77xIxOU4C/ILnsleEJhg99EINNAkH+XcyyYX5NdBXjPFwO+Nk0RIKe4QRk8wd/Zb8r3FrWUaJaLFLrBJFHnc1trt/o12oSZR1bht7ma4TpH8jSPOHbM1BmwS97rNGWT0ixflNjLk3YhpClHZW5VN8QUCVY7jikI8ZJwcZpvbV3II4se3d6T4HmyH3eMrVQaq2NLiRJDR7Th596woOZ3XJlHCiBbX5HV6jEAG5kIWRms7tufrcQrpVaWJ0dwQ15nedMag47jO2cuMTPRu3KJHAyRVydAZGYVUKW29qN1FMXQ3lfV/BaPJJmmfckOq3PrapspBO5lyYzezjDq24N0HlDjftGDLY7SGoB0lDny5itEcJz8oMej/EkZ7MH+nHPZ/BaPjFsmAspDRf2KfHPV/0j1m62pxEoIhxz3fpcdIKh6acwYMitdA7u7gQGCU0yZ4bZKzFpYwyl/d4RuHEVrRq95Nzy8RY9RDEPXZkpSxIidOUvsF0KKMnmBOibHFGfPS6LEM0Z+Q0FJ9EmJy1kRKL1wAOaFIRAxm8hySpCKGc6Iemx1SEROyy5pmiNF97W9IgZuwicpqxqS0zKhEzMvCXZrkDJXp3B6WhTs8+a52nAFVZutzz1qgADEd8kdgtlCsv0WyIBfkglyQp88fkJpONIe1gvUAAAAASUVORK5CYII=
# DontUseFBInk
# DCPRO GhostGuard OneClick v5
# Requires KMC/KPM + KOReader + Wi-Fi.
# Repairs legacy GhostGuard repo entries and preserves Native/SimpleUI/ZenUI independence.

ROOT="/mnt/us"
REPO_ID="dochoithuvi-ghostguard"
REPO="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.json"
LOG="$ROOT/documents/GhostGuard_Installer.log"
TMP="$ROOT/.dcpro_ghostguard/bootstrap_tmp.log"
FONT_SCALE=3

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
    if [ -x "$c" ]; then
        FBINK="$c"
        break
    fi
done
if [ -z "$FBINK" ]; then
    FBINK="$(command -v fbink 2>/dev/null || true)"
fi

clear_screen() {
    [ -n "$FBINK" ] || return 0
    "$FBINK" -k >/dev/null 2>&1 || "$FBINK" -S "$FONT_SCALE" -c " " >/dev/null 2>&1 || true
}

line() {
    if [ -n "$FBINK" ]; then
        "$FBINK" -S "$FONT_SCALE" -x 1 -y "$1" -r "$2" >/dev/null 2>&1 || true
    fi
}

fail() {
    log "ERROR: $*"
    line 8 "LOI: $*"
    line 10 "Xem: documents/GhostGuard_Installer.log"
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

find_kpm() {
    if [ -x /var/local/kmc/bin/kpm ]; then
        KPM=/var/local/kmc/bin/kpm
        KPM_KIND=generic
        return 0
    fi
    if [ -x /var/local/kmc/kindlehf/bin/kpm ]; then
        KPM=/var/local/kmc/kindlehf/bin/kpm
        KPM_KIND=kindlehf
        return 0
    fi
    if [ -x /var/local/kmc/kindlepw2/bin/kpm ]; then
        KPM=/var/local/kmc/kindlepw2/bin/kpm
        KPM_KIND=kindlepw2
        return 0
    fi
    return 1
}

repair_repo() {
    REPOLIST="$("$KPM" -y list-repo 2>&1 || true)"
    printf '%s\n' "$REPOLIST" >>"$LOG" 2>/dev/null || true

    if printf '%s\n' "$REPOLIST" | grep -q "$REPO_ID"; then
        if printf '%s\n' "$REPOLIST" | grep "$REPO_ID" | grep -q 'bit\.ly/ghostguard'; then
            log "Legacy bit.ly repository detected; replacing with raw GitHub URL."
            runlog "$KPM" -y remove-repo "$REPO_ID" || true
            runlog "$KPM" -y add-repo "$REPO" || return 1
        else
            log "GhostGuard repository already registered."
        fi
    else
        runlog "$KPM" -y add-repo "$REPO" || return 1
    fi

    runlog "$KPM" -y update
}

detect_ui() {
    if [ -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ]; then
        UI_NAME="ZenUI"
    elif [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then
        UI_NAME="SimpleUI"
    else
        UI_NAME="KOReader native"
    fi
    log "UI detected: $UI_NAME"
}

clear_screen
line 1 "DCPRO GhostGuard Installer"
line 2 "--------------------------"
line 4 "[1/5] Kiem tra he thong..."

log "========================================"
log "DCPRO GhostGuard OneClick v5"
log "Date: $(date)"
log "========================================"

KPM=""
KPM_KIND=""
find_kpm || fail "Khong tim thay KPM/KMC"
log "KPM=$KPM ($KPM_KIND)"

case "$KPM_KIND" in
    kindlehf|kindlepw2)
        PLAT_DIR="$(dirname "$(dirname "$KPM")")"
        export LD_LIBRARY_PATH="$PLAT_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ;;
esac

if [ ! -x "$ROOT/extensions/koreader/bin/koreader.sh" ] && \
   [ ! -x "$ROOT/koreader/koreader.sh" ]; then
    fail "Chua tim thay KOReader"
fi

detect_ui
line 4 "[1/5] He thong... OK ($UI_NAME)"
line 5 "[2/5] Sua / cap nhat repository..."

if ! repair_repo; then
    log "Initial repository repair failed; forcing clean re-add."
    runlog "$KPM" -y remove-repo "$REPO_ID" || true
    runlog "$KPM" -y add-repo "$REPO" || fail "Khong them duoc repo GhostGuard"
    runlog "$KPM" -y update || fail "Khong cap nhat duoc KPM"
fi
line 5 "[2/5] Repository... OK"

line 6 "[3/5] Tai va cai GhostGuard..."
if ! runlog "$KPM" -y install ghostguard; then
    log "Install failed once; repairing repo and retrying."
    runlog "$KPM" -y remove-repo "$REPO_ID" || true
    runlog "$KPM" -y add-repo "$REPO" || fail "Repair repo that bai"
    runlog "$KPM" -y update || fail "KPM update that bai"
    runlog "$KPM" -y install ghostguard || fail "Cai GhostGuard that bai"
fi
line 6 "[3/5] GhostGuard... OK"

line 7 "[4/5] Chuan bi UI: $UI_NAME"
log "GhostGuard selects UI bridge at KOReader runtime: ZenUI > SimpleUI > Native."
line 7 "[4/5] UI... OK"

line 8 "[5/5] Dang mo KOReader..."
"$KPM" -y launch ghostguard >>"$LOG" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    line 8 "[5/5] Mo KOReader... OK"
    line 10 "HOAN TAT!"
    exit 0
fi

fail "Khong mo duoc GhostGuard"
