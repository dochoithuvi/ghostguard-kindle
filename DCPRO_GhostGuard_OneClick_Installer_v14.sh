#!/bin/sh
# DCPRO GhostGuard OneClick v14
# Ensure KOReader + SimpleUI, then install the MTGuard5 golden runtime.
set -u
ROOT="${DCPRO_ONECLICK_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
TMP="${DCPRO_ONECLICK_TMP:-$DATA/oneclick-v14}"
REPORT_DIR="$ROOT/GhostGuard_Reports"
LOG="${DCPRO_ONECLICK_LOG:-$REPORT_DIR/OneClick_v14.log}"
BOOTSTRAP_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/bootstrap/koreader-simpleui-v14.sh"
BOOTSTRAP_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/bootstrap/koreader-simpleui-v14.sh"
GG_NAME="ghostguard_mtguard5_golden_kindle5-kindlepw2-kindlehf.kpkg"
GG_SHA256="92fd6914205719d19fc243728d347ff76b6f29787ec4dc50cbf1b842055f4fdd"
GG_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/artifacts/$GG_NAME"
GG_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/artifacts/$GG_NAME"
mkdir -p "$TMP" "$REPORT_DIR" 2>/dev/null || exit 1
: > "$LOG" 2>/dev/null || true
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

# Visible progress on Kindle, matching the proven v13 behavior.
FBINK="$(command -v fbink 2>/dev/null || true)"
[ -n "$FBINK" ] || for x in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink; do
    [ -x "$x" ] && FBINK="$x" && break
done
say(){
    row="$1"; shift
    text="$*"
    log "UI: $text"
    [ -n "$FBINK" ] && "$FBINK" -S 2 -x 1 -y "$row" -r "$text" >/dev/null 2>&1 || true
}
finish_delay(){
    # Keep the final result visible long enough to read when launched from KUAL/launcher.
    sleep "${DCPRO_ONECLICK_FINISH_DELAY:-8}" 2>/dev/null || true
}
fail(){
    log "ERROR: $*"
    say 14 "LOI: $*"
    say 15 "Xem GhostGuard_Reports/OneClick_v14.log"
    finish_delay
    exit 1
}

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
say 1 "GhostGuard OneClick v14"
say 2 "KOReader + SimpleUI + MTGuard5 GOLDEN"

BOOTSTRAP="$TMP/koreader-simpleui-v14.sh"
say 4 "[1/7] Tai bootstrap KOReader/SimpleUI..."
log "Ensuring KOReader + SimpleUI."
download_pair "$BOOTSTRAP_PRIMARY" "$BOOTSTRAP_MIRROR" "$BOOTSTRAP" || fail "khong tai duoc bootstrap"
chmod 755 "$BOOTSTRAP" 2>/dev/null || true

say 6 "[2/7] Kiem tra/cai KOReader + SimpleUI..."
DCPRO_ONECLICK_ROOT="$ROOT" DCPRO_ONECLICK_LOG="$LOG" sh "$BOOTSTRAP" >>"$LOG" 2>&1 || fail "KOReader/SimpleUI bootstrap failed"

KO_ROOT=""
for candidate in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -d "$candidate/plugins" ]; then KO_ROOT="$candidate"; break; fi
done
[ -n "$KO_ROOT" ] || fail "khong tim thay KOReader sau bootstrap"
say 8 "[3/7] KOReader + SimpleUI... OK"

KPKG="$TMP/$GG_NAME"
say 9 "[4/7] Tai MTGuard5 GOLDEN..."
log "Downloading MTGuard5 golden package."
download_pair "$GG_PRIMARY" "$GG_MIRROR" "$KPKG" || fail "khong tai duoc MTGuard5 golden"

say 10 "[5/7] Kiem tra SHA-256..."
verify_sha256 "$KPKG" "$GG_SHA256" || fail "GhostGuard SHA-256 mismatch"

say 11 "[6/7] Giai nen + cai GhostGuard..."
rm -rf "$TMP/pkg" 2>/dev/null || true
mkdir -p "$TMP/pkg" || fail "khong tao duoc thu muc staging"
tar -xzf "$KPKG" -C "$TMP/pkg" >>"$LOG" 2>&1 || fail "khong giai nen duoc GhostGuard"
[ -f "$TMP/pkg/install.sh" ] || fail "GhostGuard package thieu install.sh"
(
    cd "$TMP/pkg" || exit 1
    GHOSTGUARD_US_ROOT="$ROOT" sh ./install.sh
) >>"$LOG" 2>&1 || fail "MTGuard5 golden install failed"

say 12 "[7/7] Xac minh cai dat..."
SIMPLEUI_OK=0
for p in "$KO_ROOT/plugins/simpleui.koplugin" "$KO_ROOT/plugins/simpleui.koplugin/main.lua"; do
    if [ -e "$p" ]; then SIMPLEUI_OK=1; break; fi
done
[ "$SIMPLEUI_OK" = "1" ] || fail "SimpleUI verification failed"

cat >> "$LOG" <<EOF
MTGuard5 golden install complete.
KOReader root: $KO_ROOT
SimpleUI detected: $SIMPLEUI_OK
Artifact SHA-256: $GG_SHA256
Reports: $REPORT_DIR
EOF

printf 'ONECLICK_VERSION=14\nGHOSTGUARD_VERSION=0.9.1-local-mtguard5\nRUNTIME=mtguard1-adaptive-v3-approved-cover-nocloud\nARTIFACT_SHA256=%s\nKO_READER_ROOT=%s\nSIMPLEUI_DETECTED=%s\nREPORT_DIR=%s\nCLOUD_UPLOAD=REMOVED\nZENUI=REMOVED\nNATIVE_FILTER=SHADOW_ONLY\nINPUT_GRAB=OFF\nEVENT_INJECTION=OFF\n' \
    "$GG_SHA256" "$KO_ROOT" "$SIMPLEUI_OK" "$REPORT_DIR" > "$DATA/ONECLICK_V14_OK"

sync 2>/dev/null || true
log "SUCCESS"
say 14 "THANH CONG! MTGuard5 GOLDEN da cai dat"
say 15 "Khoi dong lai KOReader 1 lan"
echo "MTGuard5 golden installed successfully."
echo "Restart KOReader once."
finish_delay
exit 0
