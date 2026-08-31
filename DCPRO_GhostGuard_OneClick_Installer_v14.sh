#!/bin/sh
# DCPRO GhostGuard OneClick v14
# Bootstrap KOReader + SimpleUI when needed via repository bootstrap, then install GhostGuard 0.9.2.
set -u
ROOT="${DCPRO_ONECLICK_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
TMP="${DCPRO_ONECLICK_TMP:-$DATA/oneclick-v14}"
REPORT_DIR="$ROOT/GhostGuard_Reports"
LOG="${DCPRO_ONECLICK_LOG:-$REPORT_DIR/OneClick_v14.log}"
BOOTSTRAP_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/bootstrap/DCPRO_GhostGuard_OneClick_Installer.sh"
BOOTSTRAP_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/bootstrap/DCPRO_GhostGuard_OneClick_Installer.sh"
GG_NAME="ghostguard_0.9.2_kindle5-kindlepw2-kindlehf.kpkg"
GG_SHA256="b5112ba60f745032d60fcfc443709e374f61c587d3dc5215a17d14aaf81d1eeb"
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
        return
    fi
    if command -v openssl >/dev/null 2>&1; then
        got="$(openssl dgst -sha256 "$f" 2>/dev/null | sed 's/^.*= *//')"
        [ "$got" = "$expected" ]
        return
    fi
    return 1
}

log "DCPRO GhostGuard OneClick v14"
log "Root: $ROOT"

KO_ROOT=""
for candidate in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -d "$candidate/plugins" ]; then KO_ROOT="$candidate"; break; fi
done
if [ -z "$KO_ROOT" ]; then
    BOOTSTRAP="$TMP/oneclick-bootstrap.sh"
    log "KOReader not detected; running repository bootstrap."
    download_pair "$BOOTSTRAP_PRIMARY" "$BOOTSTRAP_MIRROR" "$BOOTSTRAP" || fail "cannot download OneClick bootstrap"
    chmod 755 "$BOOTSTRAP" 2>/dev/null || true
    DCPRO_ONECLICK_ROOT="$ROOT" DCPRO_ONECLICK_LOG="$LOG" sh "$BOOTSTRAP" >>"$LOG" 2>&1 || fail "OneClick bootstrap failed"
fi

KO_ROOT=""
for candidate in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -d "$candidate/plugins" ]; then KO_ROOT="$candidate"; break; fi
done
[ -n "$KO_ROOT" ] || fail "KOReader plugins directory not found after bootstrap"

KPKG="$TMP/$GG_NAME"
log "Downloading GhostGuard 0.9.2 package."
download_pair "$GG_PRIMARY" "$GG_MIRROR" "$KPKG" || fail "cannot download GhostGuard 0.9.2 package"
verify_sha256 "$KPKG" "$GG_SHA256" || fail "GhostGuard 0.9.2 SHA-256 mismatch"

rm -rf "$TMP/pkg" 2>/dev/null || true
mkdir -p "$TMP/pkg" || fail "cannot create package staging directory"
tar -xzf "$KPKG" -C "$TMP/pkg" >>"$LOG" 2>&1 || fail "cannot extract GhostGuard 0.9.2 package"
[ -f "$TMP/pkg/install.sh" ] || fail "GhostGuard package install.sh missing"
(
    cd "$TMP/pkg" || exit 1
    GHOSTGUARD_US_ROOT="$ROOT" sh ./install.sh
) >>"$LOG" 2>&1 || fail "GhostGuard 0.9.2 install failed"

SIMPLEUI_OK=0
for p in "$KO_ROOT/plugins/simpleui.koplugin" "$KO_ROOT/plugins/simpleui.koplugin/main.lua"; do
    if [ -e "$p" ]; then SIMPLEUI_OK=1; break; fi
done

cat >> "$LOG" <<EOF
GhostGuard 0.9.2 install complete.
KOReader root: $KO_ROOT
SimpleUI detected: $SIMPLEUI_OK
Artifact SHA-256: $GG_SHA256
Reports: $REPORT_DIR
EOF

printf 'ONECLICK_VERSION=14\nGHOSTGUARD_VERSION=0.9.2\nRUNTIME=MTGUARD5_ADAPTIVE_V3\nARTIFACT_SHA256=%s\nKO_READER_ROOT=%s\nSIMPLEUI_DETECTED=%s\nREPORT_DIR=%s\nCLOUD_UPLOAD=REMOVED\nZENUI=REMOVED\nNATIVE_FILTER=SHADOW_ONLY\nINPUT_GRAB=OFF\nEVENT_INJECTION=OFF\n' \
    "$GG_SHA256" "$KO_ROOT" "$SIMPLEUI_OK" "$REPORT_DIR" > "$DATA/ONECLICK_V14_OK"

sync 2>/dev/null || true
echo "GhostGuard 0.9.2 installed successfully."
echo "Restart KOReader once."
exit 0
