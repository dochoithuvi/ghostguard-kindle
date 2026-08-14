#!/bin/sh
# DontUseFBInk
# DCPRO GhostGuard OneClick v8
# Auto-installs KOReader before GhostGuard so touch-broken Kindles can bootstrap without UI input.
# KOReader install path: KPM first, official KOReader release ZIP fallback second.
# Also repairs GhostGuard repo, installs SimpleUI when no ZenUI/SimpleUI exists,
# and applies the GitHub Raw -> jsDelivr license-sync fallback from the public repo.

ROOT="/mnt/us"
REPO_ID="dochoithuvi-ghostguard"
REPO="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.json"
KOREADER_REPO_ID="kindlemodding"
KOREADER_REPO="https://raw.githubusercontent.com/KindleModding/repo/main/manifest.v2.json"
KOREADER_VERSION="2026.07"
LOG="$ROOT/documents/GhostGuard_Installer.log"
TMP="$ROOT/.dcpro_ghostguard/bootstrap_tmp.log"
FONT_SCALE=3
SIMPLEUI_ZIP="https://codeload.github.com/doctorhetfield-cmd/simpleui.koplugin/zip/refs/heads/main"
SIMPLEUI_TMP="$ROOT/.dcpro_ghostguard/simpleui.zip"
SIMPLEUI_TMPDIR="$ROOT/.dcpro_ghostguard/simpleui_unpack"
KO_TMP="$ROOT/.dcpro_ghostguard/koreader.zip"
KO_TMPDIR="$ROOT/.dcpro_ghostguard/koreader_unpack"

mkdir -p "$ROOT/.dcpro_ghostguard" 2>/dev/null || true
: > "$LOG" 2>/dev/null || true

log() { printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

FBINK=""
for c in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink /var/local/kmc/kindle5/bin/fbink; do
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
download_file() {
    URL="$1"; DEST="$2"
    rm -f "$DEST" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then curl -L --fail --silent --show-error "$URL" -o "$DEST"; return $?; fi
    if command -v wget >/dev/null 2>&1; then wget -q -O "$DEST" "$URL"; return $?; fi
    return 127
}

repair_repo() {
    REPOLIST="$($KPM -y list-repo 2>&1 || true)"
    printf '%s\n' "$REPOLIST" >>"$LOG" 2>/dev/null || true
    if printf '%s\n' "$REPOLIST" | grep -q "$REPO_ID"; then
        if printf '%s\n' "$REPOLIST" | grep "$REPO_ID" | grep -q 'bit\.ly/ghostguard'; then
            log "Legacy bit.ly GhostGuard repo detected; replacing it."
            runlog "$KPM" -y remove-repo "$REPO_ID" || true
            runlog "$KPM" -y add-repo "$REPO" || return 1
        fi
    else
        runlog "$KPM" -y add-repo "$REPO" || return 1
    fi
    runlog "$KPM" -y update
}

koreader_installed() {
    [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ] || [ -x "$ROOT/koreader/koreader.sh" ]
}

koreader_release_target() {
    # KPM_KIND is the best signal available on the supported KMC layouts.
    case "$KPM_KIND" in
        kindlehf) echo "kindlehf" ;;
        kindlepw2) echo "kindlepw2" ;;
        *)
            if [ -d /var/local/kmc/kindle5 ]; then echo "kindle-legacy"; else echo "kindle"; fi
            ;;
    esac
}

install_koreader_direct() {
    TARGET="$(koreader_release_target)"
    ASSET="koreader-${TARGET}-v${KOREADER_VERSION}.zip"
    URL="https://github.com/koreader/koreader/releases/download/v${KOREADER_VERSION}/${ASSET}"
    log "KOReader direct fallback target=$TARGET asset=$ASSET"
    line 3 "KOReader: tai goi chinh thuc..."
    rm -rf "$KO_TMPDIR" "$KO_TMP" 2>/dev/null || true
    mkdir -p "$KO_TMPDIR" 2>/dev/null || return 1
    download_file "$URL" "$KO_TMP" || { log "Direct KOReader download failed: $URL"; return 1; }
    [ -s "$KO_TMP" ] || return 1
    command -v unzip >/dev/null 2>&1 || { log "unzip not available for KOReader direct fallback."; return 1; }
    unzip -q "$KO_TMP" -d "$KO_TMPDIR" >/dev/null 2>&1 || { log "KOReader ZIP extraction failed."; return 1; }
    SRC=""
    # Release ZIP contains koreader/ and extensions/. Locate a valid root regardless of ZIP layout.
    for d in "$KO_TMPDIR" "$KO_TMPDIR"/*; do
        if [ -x "$d/koreader/koreader.sh" ] || [ -x "$d/extensions/koreader/bin/koreader.sh" ]; then SRC="$d"; break; fi
    done
    [ -n "$SRC" ] || { log "KOReader ZIP extracted but expected launcher was not found."; return 1; }
    if [ -d "$SRC/koreader" ]; then
        rm -rf "$ROOT/koreader" 2>/dev/null || true
        cp -R "$SRC/koreader" "$ROOT/koreader" || return 1
    fi
    if [ -d "$SRC/extensions" ]; then
        mkdir -p "$ROOT/extensions" 2>/dev/null || return 1
        if [ -d "$SRC/extensions/koreader" ]; then
            rm -rf "$ROOT/extensions/koreader" 2>/dev/null || true
            cp -R "$SRC/extensions/koreader" "$ROOT/extensions/koreader" || return 1
        fi
    fi
    rm -rf "$KO_TMPDIR" "$KO_TMP" 2>/dev/null || true
    koreader_installed && { log "KOReader direct fallback installed successfully."; return 0; }
    return 1
}

install_koreader() {
    if koreader_installed; then log "KOReader already installed."; return 0; fi
    log "KOReader not found; trying official KPM installation first."
    line 3 "KOReader chua co - dang cai..."
    REPOLIST="$($KPM -y list-repo 2>&1 || true)"
    printf '%s\n' "$REPOLIST" >>"$LOG" 2>/dev/null || true
    if ! printf '%s\n' "$REPOLIST" | grep -q "$KOREADER_REPO_ID"; then
        log "Official KMC repository not found; adding it automatically."
        runlog "$KPM" -y add-repo "$KOREADER_REPO" || log "Could not add official KMC repo; direct fallback will be used."
    fi
    runlog "$KPM" -y update || log "KPM update failed; direct KOReader fallback will be attempted."
    if runlog "$KPM" -y install koreader; then
        if koreader_installed; then log "KOReader installed successfully through KPM."; return 0; fi
    fi
    log "KPM KOReader install failed; falling back to official KOReader release ZIP."
    install_koreader_direct
}

install_simpleui() {
    if [ -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ] || [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then
        log "ZenUI/SimpleUI already installed."; return 0
    fi
    log "No ZenUI/SimpleUI found; attempting automatic SimpleUI installation."
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

patch_license_sync() {
    DEST="$ROOT/koreader/plugins/dcghostguardpro.koplugin"
    [ -d "$DEST" ] || return 0
    PATCH_TMP="$ROOT/.dcpro_ghostguard/license_sync_patch"
    mkdir -p "$PATCH_TMP" 2>/dev/null || return 1
    BASE_RAW="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/source/payload/dcghostguardpro.koplugin"
    BASE_CDN="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/source/payload/dcghostguardpro.koplugin"
    for f in defaults.lua online_license.lua; do
        if ! download_file "$BASE_RAW/$f" "$PATCH_TMP/$f"; then
            log "Raw download failed for $f; trying jsDelivr."
            download_file "$BASE_CDN/$f" "$PATCH_TMP/$f" || { log "Network patch failed for $f."; return 1; }
        fi
        [ -s "$PATCH_TMP/$f" ] || { log "Downloaded $f is empty."; return 1; }
    done
    grep -q 'online_license_registry_mirror_url' "$PATCH_TMP/defaults.lua" || { log "Mirror setting missing."; return 1; }
    grep -q 'JSDELIVR' "$PATCH_TMP/online_license.lua" || { log "Fallback logic missing."; return 1; }
    cp "$PATCH_TMP/defaults.lua" "$DEST/defaults.lua" || return 1
    cp "$PATCH_TMP/online_license.lua" "$DEST/online_license.lua" || return 1
    rm -rf "$PATCH_TMP" 2>/dev/null || true
    log "Online license fallback patch installed successfully."
    return 0
}

detect_ui() {
    if [ -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ]; then UI_NAME="ZenUI"
    elif [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then UI_NAME="SimpleUI"
    else UI_NAME="KOReader native"; fi
    log "UI detected: $UI_NAME"
}

clear_screen
line 1 "DCPRO GhostGuard Installer v8"
line 2 "-----------------------------"
line 4 "[1/7] Kiem tra he thong..."
log "========================================"
log "DCPRO GhostGuard OneClick v8"
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

# Critical bootstrap: install KOReader before touching GhostGuard. This allows the script
# to finish the bootstrap even when the Kindle touch panel is unusable.
line 4 "[1/7] He thong... OK"
line 5 "[2/7] Kiem tra / cai KOReader..."
install_koreader || fail "Khong tai/cai duoc KOReader"
if ! koreader_installed; then fail "KOReader van chua san sang sau khi cai"; fi
line 5 "[2/7] KOReader... OK"

line 6 "[3/7] Kiem tra UI..."
if [ ! -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ] && [ ! -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then
    install_simpleui || log "SimpleUI auto-install skipped/failed; continuing with native UI."
fi
detect_ui
line 6 "[3/7] UI: $UI_NAME"

line 7 "[4/7] Sua / cap nhat repository..."
if ! repair_repo; then
    log "Initial repository repair failed; forcing clean re-add."
    runlog "$KPM" -y remove-repo "$REPO_ID" || true
    runlog "$KPM" -y add-repo "$REPO" || fail "Khong them duoc repo GhostGuard"
    runlog "$KPM" -y update || fail "Khong cap nhat duoc KPM"
fi
line 7 "[4/7] Repository... OK"

line 8 "[5/7] Tai va cai GhostGuard..."
if ! runlog "$KPM" -y install ghostguard; then
    log "GhostGuard install failed once; repairing repo and retrying."
    runlog "$KPM" -y remove-repo "$REPO_ID" || true
    runlog "$KPM" -y add-repo "$REPO" || fail "Repair repo that bai"
    runlog "$KPM" -y update || fail "KPM update that bai"
    runlog "$KPM" -y install ghostguard || fail "Cai GhostGuard that bai"
fi
line 8 "[5/7] GhostGuard... OK"

line 9 "[6/7] Cap nhat license network..."
patch_license_sync || log "License fallback patch skipped; package version may already contain it."
line 9 "[6/7] License network... OK"

line 10 "[7/7] Dang mo KOReader..."
"$KPM" -y launch ghostguard >>"$LOG" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    line 10 "HOAN TAT!"
    exit 0
fi
# Launch failure is not necessarily an installation failure; KOReader may need a clean restart.
log "GhostGuard launch returned rc=$RC; KOReader itself is installed."
line 10 "CAI XONG - Khoi dong KOReader"
sleep 5
exit 0
