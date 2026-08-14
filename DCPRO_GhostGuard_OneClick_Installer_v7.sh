#!/bin/sh
# Name: GhostGuard - Cai / Cap nhat
# Author: Do Choi Thu Vi
# DCPRO GhostGuard OneClick v7
# Requires KMC/KPM + Wi-Fi; auto-installs KOReader and SimpleUI when missing.
# KOReader is installed from the official KindleModding KPM repository.

ROOT="/mnt/us"
REPO_ID="dochoithuvi-ghostguard"
REPO="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.json"
KOREADER_REPO_ID="kindlemodding"
KOREADER_REPO="https://raw.githubusercontent.com/KindleModding/repo/main/manifest.json"
LOG="$ROOT/documents/GhostGuard_Installer.log"
TMP="$ROOT/.dcpro_ghostguard/bootstrap_tmp.log"
FONT_SCALE=3
SIMPLEUI_REPO="https://github.com/doctorhetfield-cmd/simpleui.koplugin"
SIMPLEUI_ZIP="https://codeload.github.com/doctorhetfield-cmd/simpleui.koplugin/zip/refs/heads/main"
SIMPLEUI_TMP="$ROOT/.dcpro_ghostguard/simpleui.zip"
SIMPLEUI_TMPDIR="$ROOT/.dcpro_ghostguard/simpleui_unpack"

mkdir -p "$ROOT/.dcpro_ghostguard" 2>/dev/null || true
: > "$LOG" 2>/dev/null || true

log() { printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

FBINK=""
for c in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink; do
    if [ -x "$c" ]; then FBINK="$c"; break; fi
done
[ -n "$FBINK" ] || FBINK="$(command -v fbink 2>/dev/null || true)"

clear_screen() {
    [ -n "$FBINK" ] || return 0
    "$FBINK" -k >/dev/null 2>&1 || "$FBINK" -S "$FONT_SCALE" -c " " >/dev/null 2>&1 || true
}
line() {
    [ -n "$FBINK" ] && "$FBINK" -S "$FONT_SCALE" -x 1 -y "$1" -r "$2" >/dev/null 2>&1 || true
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
    if [ -x /var/local/kmc/bin/kpm ]; then KPM=/var/local/kmc/bin/kpm; KPM_KIND=generic; return 0; fi
    if [ -x /var/local/kmc/kindlehf/bin/kpm ]; then KPM=/var/local/kmc/kindlehf/bin/kpm; KPM_KIND=kindlehf; return 0; fi
    if [ -x /var/local/kmc/kindlepw2/bin/kpm ]; then KPM=/var/local/kmc/kindlepw2/bin/kpm; KPM_KIND=kindlepw2; return 0; fi
    return 1
}
repair_repo() {
    REPOLIST="$($KPM -y list-repo 2>&1 || true)"
    printf '%s\n' "$REPOLIST" >>"$LOG" 2>/dev/null || true
    if printf '%s\n' "$REPOLIST" | grep -q "$REPO_ID"; then
        if printf '%s\n' "$REPOLIST" | grep "$REPO_ID" | grep -q 'bit\.ly/ghostguard'; then
            runlog "$KPM" -y remove-repo "$REPO_ID" || true
            runlog "$KPM" -y add-repo "$REPO" || return 1
        fi
    else
        runlog "$KPM" -y add-repo "$REPO" || return 1
    fi
    runlog "$KPM" -y update
}
download_file() {
    URL="$1"; DEST="$2"
    if command -v curl >/dev/null 2>&1; then curl -L --fail --silent --show-error "$URL" -o "$DEST"; return $?; fi
    if command -v wget >/dev/null 2>&1; then wget -q -O "$DEST" "$URL"; return $?; fi
    return 127
}
install_koreader() {
    if [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ] || [ -x "$ROOT/koreader/koreader.sh" ]; then
        log "KOReader already installed."; return 0
    fi
    log "KOReader not found; attempting automatic KPM installation."
    line 3 "KOReader chua co - dang tai..."
    REPOLIST="$($KPM -y list-repo 2>&1 || true)"
    printf '%s\n' "$REPOLIST" >>"$LOG" 2>/dev/null || true
    if ! printf '%s\n' "$REPOLIST" | grep -q "$KOREADER_REPO_ID"; then
        log "Official KMC repository not found; adding it automatically."
        runlog "$KPM" -y add-repo "$KOREADER_REPO" || return 1
    fi
    runlog "$KPM" -y update || true
    if runlog "$KPM" -y install koreader; then
        if [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ] || [ -x "$ROOT/koreader/koreader.sh" ]; then
            log "KOReader installed successfully."; return 0
        fi
    fi
    log "KOReader installation failed."
    return 1
}
install_simpleui() {
    if [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then log "SimpleUI already installed."; return 0; fi
    log "SimpleUI not found; attempting automatic installation."
    rm -rf "$SIMPLEUI_TMPDIR" "$SIMPLEUI_TMP" 2>/dev/null || true
    mkdir -p "$SIMPLEUI_TMPDIR" 2>/dev/null || return 1
    download_file "$SIMPLEUI_ZIP" "$SIMPLEUI_TMP" || return 1
    command -v unzip >/dev/null 2>&1 || return 1
    unzip -q "$SIMPLEUI_TMP" -d "$SIMPLEUI_TMPDIR" >/dev/null 2>&1 || return 1
    SRC=""
    for d in "$SIMPLEUI_TMPDIR"/simpleui.koplugin "$SIMPLEUI_TMPDIR"/simpleui.koplugin-*; do
        if [ -f "$d/main.lua" ]; then SRC="$d"; break; fi
    done
    [ -n "$SRC" ] || return 1
    mkdir -p "$ROOT/koreader/plugins" 2>/dev/null || return 1
    rm -rf "$ROOT/koreader/plugins/simpleui.koplugin" 2>/dev/null || true
    cp -R "$SRC" "$ROOT/koreader/plugins/simpleui.koplugin" || return 1
    rm -rf "$SIMPLEUI_TMPDIR" "$SIMPLEUI_TMP" 2>/dev/null || true
    log "SimpleUI installed successfully."
    return 0
}
detect_ui() {
    if [ -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ]; then UI_NAME="ZenUI"
    elif [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then UI_NAME="SimpleUI"
    else UI_NAME="KOReader native"; fi
    log "UI detected: $UI_NAME"
}

clear_screen
line 1 "DCPRO GhostGuard Installer"
line 2 "--------------------------"
line 4 "[1/6] Kiem tra he thong..."
log "========================================"
log "DCPRO GhostGuard OneClick v7"
log "Date: $(date)"
log "========================================"

KPM=""; KPM_KIND=""
find_kpm || fail "Khong tim thay KPM/KMC"
log "KPM=$KPM ($KPM_KIND)"
case "$KPM_KIND" in
    kindlehf|kindlepw2)
        PLAT_DIR="$(dirname "$(dirname "$KPM")")"
        export LD_LIBRARY_PATH="$PLAT_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ;;
esac

# IMPORTANT: this happens before any GhostGuard launch, so a Kindle with a
# broken/touch-unusable UI can still bootstrap KOReader from the scriptlet.
if [ ! -x "$ROOT/extensions/koreader/bin/koreader.sh" ] && [ ! -x "$ROOT/koreader/koreader.sh" ]; then
    install_koreader || fail "Khong tai/cai duoc KOReader"
fi
if [ ! -x "$ROOT/extensions/koreader/bin/koreader.sh" ] && [ ! -x "$ROOT/koreader/koreader.sh" ]; then
    fail "KOReader van chua san sang sau khi cai"
fi

if [ ! -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ] && [ ! -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then
    install_simpleui || log "SimpleUI auto-install skipped/failed; continuing with native UI."
fi

detect_ui
line 4 "[1/6] He thong... OK ($UI_NAME)"
line 5 "[2/6] Sua / cap nhat repository..."
if ! repair_repo; then
    log "Initial repository repair failed; forcing clean re-add."
    runlog "$KPM" -y remove-repo "$REPO_ID" || true
    runlog "$KPM" -y add-repo "$REPO" || fail "Khong them duoc repo GhostGuard"
    runlog "$KPM" -y update || fail "Khong cap nhat duoc KPM"
fi
line 5 "[3/6] Repository... OK"
line 6 "[4/6] Tai va cai GhostGuard..."
if ! runlog "$KPM" -y install ghostguard; then
    log "Install failed once; repairing repo and retrying."
    runlog "$KPM" -y remove-repo "$REPO_ID" || true
    runlog "$KPM" -y add-repo "$REPO" || fail "Repair repo that bai"
    runlog "$KPM" -y update || fail "KPM update that bai"
    runlog "$KPM" -y install ghostguard || fail "Cai GhostGuard that bai"
fi
line 6 "[4/6] GhostGuard... OK"
line 7 "[5/6] Chuan bi UI: $UI_NAME"
log "GhostGuard selects UI bridge at KOReader runtime: ZenUI > SimpleUI > Native."
line 7 "[5/6] UI... OK"
line 8 "[6/6] Dang mo KOReader..."
"$KPM" -y launch ghostguard >>"$LOG" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    line 8 "[6/6] Mo KOReader... OK"
    line 10 "HOAN TAT!"
    exit 0
fi
fail "Khong mo duoc GhostGuard"
