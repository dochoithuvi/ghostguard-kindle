#!/bin/sh
# DCPRO GhostGuard v14 bootstrap helper
# Ensures KOReader 2026.07.1 + SimpleUI are available before GhostGuard install.
set -u
ROOT="${DCPRO_ONECLICK_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
TMP="${DCPRO_BOOTSTRAP_TMP:-$DATA/bootstrap-v14}"
LOG="${DCPRO_ONECLICK_LOG:-$ROOT/GhostGuard_Reports/OneClick_v14.log}"
KO_VERSION="2026.07.1"
KMC_REPO="https://repo.kindlemodding.org/manifest.v2.json"
SUI_ZIP_URL="https://codeload.github.com/doctorhetfield-cmd/simpleui.koplugin/zip/refs/heads/main"
SUI_ZIP="$TMP/simpleui-main.zip"
SUI_UNPACK="$TMP/simpleui-unpack"
mkdir -p "$TMP" "${LOG%/*}" 2>/dev/null || exit 1
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }
fail(){ log "BOOTSTRAP ERROR: $*"; exit 1; }
download(){
    url="$1"; out="$2"; rm -f "$out" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        curl -L -f -sS "$url" -o "$out" >>"$LOG" 2>&1 && [ -s "$out" ] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$url" >>"$LOG" 2>&1 && [ -s "$out" ] && return 0
    fi
    return 1
}
find_kpm(){
    for k in /var/local/kmc/bin/kpm /var/local/kmc/kindlehf/bin/kpm /var/local/kmc/kindlepw2/bin/kpm; do
        [ -x "$k" ] && { printf '%s\n' "$k"; return 0; }
    done
    return 1
}
valid_ko_root(){
    d="$1"
    [ -n "$d" ] && [ -d "$d/plugins" ] || return 1
    [ -d "$d/frontend" ] || [ -f "$d/koreader.sh" ] || [ -x "$d/bin/koreader.sh" ] || [ -f "$d/reader.lua" ]
}
detect_koreader_root(){
    if [ -n "${DCPRO_KO_ROOT_OVERRIDE:-}" ] && valid_ko_root "$DCPRO_KO_ROOT_OVERRIDE"; then printf '%s\n' "$DCPRO_KO_ROOT_OVERRIDE"; return 0; fi
    for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
        if valid_ko_root "$d"; then printf '%s\n' "$d"; return 0; fi
    done
    p="$(find "$ROOT" -maxdepth 8 -type f \( -name koreader.sh -o -name reader.lua \) 2>/dev/null | head -n 1)"
    [ -n "$p" ] || return 1
    d="${p%/*}"; n=0
    while [ "$n" -lt 5 ]; do
        if [ -d "$d/plugins" ]; then printf '%s\n' "$d"; return 0; fi
        parent="${d%/*}"; [ "$parent" = "$d" ] && break; d="$parent"; n=$((n + 1))
    done
    return 1
}
koreader_target(){ case "$1" in */kindlehf/bin/kpm) echo kindlehf;; */kindlepw2/bin/kpm) echo kindlepw2;; *) echo kindle;; esac; }
ko_sha256(){
    case "$1" in
        kindle) echo "1fa9cc2784ffa42eaa309445d4e81661f825614c9c32349554fed6e4c8757a1d";;
        kindlehf) echo "3343a916d12f36c01b59df1f65bd83ff5616e6c2a4dfbe919e7fa1400b8b1bbb";;
        kindlepw2) echo "ea1f575c54492a2c679d128b7f3210fd7d6a87e5f5a1ff1f7a7fe2080ff68f86";;
        *) return 1;;
    esac
}
verify_sha256(){
    f="$1"; expected="$2"
    if command -v sha256sum >/dev/null 2>&1; then
        got="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"; [ "$got" = "$expected" ]; return
    fi
    if command -v openssl >/dev/null 2>&1; then
        got="$(openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}')"; [ "$got" = "$expected" ]; return
    fi
    log "WARN: SHA256 tool unavailable; KOReader checksum verification skipped."
    return 0
}
unzip_to(){
    zip="$1"; dest="$2"; rm -rf "$dest" 2>/dev/null || true; mkdir -p "$dest" || return 1
    if command -v unzip >/dev/null 2>&1; then unzip -q "$zip" -d "$dest" >>"$LOG" 2>&1; return $?; fi
    if command -v busybox >/dev/null 2>&1; then busybox unzip -q "$zip" -d "$dest" >>"$LOG" 2>&1; return $?; fi
    return 1
}
install_koreader_kpm(){
    kpm="$1"; [ -x "$kpm" ] || return 1
    repos="$("$kpm" -y list-repo 2>&1 || true)"; printf '%s\n' "$repos" >> "$LOG"
    if ! printf '%s\n' "$repos" | grep -Fq "kindlemodding"; then "$kpm" -y add-repo "$KMC_REPO" >>"$LOG" 2>&1 || true; fi
    "$kpm" -y update >>"$LOG" 2>&1 || log "WARN: KPM update failed before KOReader install."
    "$kpm" -y install koreader >>"$LOG" 2>&1 || return 1
    KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"; [ -n "$KO_ROOT" ]
}
install_koreader_official(){
    kpm="$1"; target="$(koreader_target "$kpm")"; expected="$(ko_sha256 "$target")" || return 1
    asset="koreader-${target}-v${KO_VERSION}.zip"
    url="https://github.com/koreader/koreader/releases/download/v${KO_VERSION}/${asset}"
    zip="$TMP/$asset"; dest="$TMP/koreader-unpack"
    log "KOReader fallback: $url"
    download "$url" "$zip" || return 1
    verify_sha256 "$zip" "$expected" || return 1
    unzip_to "$zip" "$dest" || return 1
    src=""
    for d in "$dest/koreader" "$dest"/*/koreader; do
        if [ -f "$d/koreader.sh" ] || [ -d "$d/frontend" ]; then src="$d"; break; fi
    done
    if [ -n "$src" ]; then
        rm -rf "$ROOT/koreader" 2>/dev/null || true
        cp -R "$src" "$ROOT/koreader" >>"$LOG" 2>&1 || return 1
    else
        for d in "$dest/extensions/koreader" "$dest"/*/extensions/koreader; do
            if [ -x "$d/bin/koreader.sh" ] || [ -d "$d/frontend" ]; then src="$d"; break; fi
        done
        [ -n "$src" ] || return 1
        mkdir -p "$ROOT/extensions" || return 1
        rm -rf "$ROOT/extensions/koreader" 2>/dev/null || true
        cp -R "$src" "$ROOT/extensions/koreader" >>"$LOG" 2>&1 || return 1
    fi
    KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"; [ -n "$KO_ROOT" ]
}
ensure_koreader(){
    KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"
    if [ -n "$KO_ROOT" ]; then log "KOReader already installed: $KO_ROOT"; return 0; fi
    KPM="$(find_kpm 2>/dev/null || true)"
    if [ -n "$KPM" ] && install_koreader_kpm "$KPM"; then log "KOReader installed via KPM: $KO_ROOT"; return 0; fi
    log "KPM KOReader path unavailable/failed; using official release ZIP."
    install_koreader_official "$KPM"
}
simpleui_installed(){
    target="$KO_ROOT/plugins/simpleui.koplugin"
    [ -f "$target/main.lua" ] && [ -f "$target/features/sui_quickactions.lua" ] && [ -f "$target/infra/sui_config.lua" ] && [ -f "$target/engines/sui_window.lua" ]
}
install_simpleui(){
    if simpleui_installed; then log "SimpleUI already installed and API-compatible."; return 0; fi
    download "$SUI_ZIP_URL" "$SUI_ZIP" || return 1
    unzip_to "$SUI_ZIP" "$SUI_UNPACK" || return 1
    src=""
    for d in "$SUI_UNPACK/simpleui.koplugin-main" "$SUI_UNPACK"/*; do
        if [ -f "$d/main.lua" ] && [ -f "$d/_meta.lua" ] && [ -f "$d/features/sui_quickactions.lua" ] && [ -f "$d/infra/sui_config.lua" ] && [ -f "$d/engines/sui_window.lua" ]; then src="$d"; break; fi
    done
    [ -n "$src" ] || return 1
    target="$KO_ROOT/plugins/simpleui.koplugin"
    backup="$KO_ROOT/plugins/.simpleui.koplugin.v14-old"
    staging="$KO_ROOT/plugins/.simpleui.koplugin.v14-new.$$"
    rm -rf "$staging" "$backup" 2>/dev/null || true
    cp -R "$src" "$staging" >>"$LOG" 2>&1 || return 1
    [ -d "$target" ] && mv "$target" "$backup" >>"$LOG" 2>&1 || true
    if ! mv "$staging" "$target" >>"$LOG" 2>&1; then
        [ -d "$backup" ] && mv "$backup" "$target" 2>/dev/null || true
        return 1
    fi
    if ! simpleui_installed; then
        rm -rf "$target" 2>/dev/null || true
        [ -d "$backup" ] && mv "$backup" "$target" 2>/dev/null || true
        return 1
    fi
    rm -rf "$backup" 2>/dev/null || true
    log "SimpleUI install: PASS ($target)"
}

ensure_koreader || fail "cannot install/detect KOReader"
install_simpleui || fail "cannot install/verify SimpleUI"
printf '%s\n' "$KO_ROOT"
exit 0
