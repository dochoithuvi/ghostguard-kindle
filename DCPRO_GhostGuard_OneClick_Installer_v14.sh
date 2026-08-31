#!/bin/sh
# DCPRO GhostGuard OneClick v14
# Bootstrap KOReader + SimpleUI when needed via proven v13, then install GhostGuard 0.9.2.
set -u
ROOT="${DCPRO_ONECLICK_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
TMP="${DCPRO_ONECLICK_TMP:-$DATA/oneclick-v14}"
REPORT_DIR="$ROOT/GhostGuard_Reports"
LOG="${DCPRO_ONECLICK_LOG:-$REPORT_DIR/OneClick_v14.log}"
V13_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/DCPRO_GhostGuard_OneClick_Installer_v13.sh"
V13_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/DCPRO_GhostGuard_OneClick_Installer_v13.sh"
GG_NAME="ghostguard_0.9.2_kindle5-kindlepw2-kindlehf.kpkg"
GG_SHA256="bb72ee627d2680e773254cbe34da96e193bee296d2d0ac654336bae27c8fcd41"
GG_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/artifacts/$GG_NAME"
GG_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/artifacts/$GG_NAME"
mkdir -p "$TMP" "$REPORT_DIR" 2>/dev/null || exit 1
: > "$LOG" 2>/dev/null || true
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }
fail(){ log "ERROR: $*"; exit 1; }
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
download_pair(){ download "$1" "$3" && return 0; download "$2" "$3"; }
verify_sha256(){
    f="$1"; expected="$2"
    if command -v sha256sum >/dev/null 2>&1; then
        got="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
        [ "$got" = "$expected" ]
        return $?
    fi
    if command -v openssl >/dev/null 2>&1; then
        got="$(openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}')"
        [ "$got" = "$expected" ]
        return $?
    fi
    log "WARN: no SHA-256 tool available; package checksum verification skipped"
    return 0
}
valid_ko_root(){
    d="$1"; [ -n "$d" ] && [ -d "$d/plugins" ] || return 1
    [ -d "$d/frontend" ] || [ -f "$d/koreader.sh" ] || [ -x "$d/bin/koreader.sh" ] || [ -f "$d/reader.lua" ]
}
detect_koreader_root(){
    for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do valid_ko_root "$d" && { printf '%s\n' "$d"; return 0; }; done
    return 1
}
need_v13=1
KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"
if [ -n "$KO_ROOT" ] && [ -f "$KO_ROOT/plugins/simpleui.koplugin/main.lua" ]; then need_v13=0; fi
if [ "$need_v13" = "1" ]; then
    V13="$TMP/DCPRO_GhostGuard_OneClick_Installer_v13.sh"
    log "Bootstrap: v13 required"
    download_pair "$V13_PRIMARY" "$V13_MIRROR" "$V13" || fail "cannot download v13 bootstrap"
    chmod 755 "$V13" 2>/dev/null || true
    DCPRO_ONECLICK_ROOT="$ROOT" DCPRO_ONECLICK_TMP="$DATA/oneclick-v13" \
    DCPRO_ONECLICK_LOG="$REPORT_DIR/OneClick_v13_bootstrap.log" \
        /bin/sh "$V13" >>"$LOG" 2>&1 || fail "v13 bootstrap failed"
    KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"
fi
[ -n "$KO_ROOT" ] || fail "KOReader unavailable"
PKG="$TMP/$GG_NAME"; UNPACK="$TMP/ghostguard-092"
download_pair "$GG_PRIMARY" "$GG_MIRROR" "$PKG" || fail "cannot download GhostGuard 0.9.2"
verify_sha256 "$PKG" "$GG_SHA256" || fail "GhostGuard 0.9.2 checksum mismatch"
rm -rf "$UNPACK" 2>/dev/null || true; mkdir -p "$UNPACK" || fail "cannot create unpack dir"
tar -xzf "$PKG" -C "$UNPACK" >>"$LOG" 2>&1 || fail "cannot extract GhostGuard 0.9.2"
compact="$(tr -d ' \t\r\n' < "$UNPACK/manifest.json" 2>/dev/null || true)"
printf '%s' "$compact" | grep -Fq '"version":[0,9,2]' || fail "package version mismatch"
test ! -e "$UNPACK/payload/dcghostguardpro.koplugin/cloud_manager.lua" || fail "Cloud runtime present"
test ! -e "$UNPACK/payload/dcghostguardpro.koplugin/zenui_bridge.lua" || fail "ZenUI runtime present"
( cd "$UNPACK" && GHOSTGUARD_US_ROOT="$ROOT" /bin/sh ./install.sh ) >>"$LOG" 2>&1 || fail "0.9.2 install failed"
PLUGIN="$KO_ROOT/plugins/dcghostguardpro.koplugin"
grep -Fq 'version = "0.9.2"' "$PLUGIN/defaults.lua" 2>/dev/null || fail "runtime version verify failed"
grep -Fq 'runtime_revision = "mtguard5-adaptive-v3-stable"' "$PLUGIN/defaults.lua" 2>/dev/null || fail "runtime revision verify failed"
rm -f "$ROOT/documents/GhostGuard_OneClick_v13.log" "$ROOT/documents/GhostGuard_Installer.log" 2>/dev/null || true
cat > "$DATA/ONECLICK_V14_OK" <<EOF
DCPRO_GHOSTGUARD_ONECLICK_V14_OK
VERSION=0.9.2
KO_ROOT=$KO_ROOT
PLUGIN=$PLUGIN
REPORT_DIR=$REPORT_DIR
CLOUD=REMOVED
ZENUI=REMOVED
NATIVE_FILTER=SHADOW_ONLY
INPUT_GRAB=OFF
EVENT_INJECTION=OFF
EOF
sync 2>/dev/null || true
log "PASS: GhostGuard 0.9.2 / OneClick v14"
exit 0
