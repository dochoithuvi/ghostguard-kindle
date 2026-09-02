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
GG_SHA256="63f1e5023887af381586cbc7b10e1a8e21066541d862b5698446a157224f29ea"
GG_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/artifacts/$GG_NAME"
GG_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/artifacts/$GG_NAME"
LEGACY_AUTOSTART_SCRIPT="$DATA/koreader-autostart.sh"
LEGACY_AUTOSTART_JOB="/etc/upstart/dcpro-koreader-autostart.conf"
mkdir -p "$TMP" "$REPORT_DIR" 2>/dev/null || exit 1
: > "$LOG" 2>/dev/null || true
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

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
finish_delay(){ sleep "${DCPRO_ONECLICK_FINISH_DELAY:-6}" 2>/dev/null || true; }
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

# v14 safety rollback: a previous build installed a reboot Upstart job. Disable
# it first through a persistent no-op script, then remove the rootfs job when
# writable. Even if rootfs cleanup is unavailable, the stale job cannot launch
# KOReader because its target script exits immediately.
disable_koreader_boot_autostart(){
    rm -f "$DATA/LAUNCH_ONCE" 2>/dev/null || true
    mkdir -p "$DATA" 2>/dev/null || true
    cat > "$LEGACY_AUTOSTART_SCRIPT" <<'EOS'
#!/bin/sh
# Reboot auto-open intentionally disabled. KOReader is launched only by the user
# or once immediately after a successful OneClick install.
exit 0
EOS
    chmod 755 "$LEGACY_AUTOSTART_SCRIPT" 2>/dev/null || true

    if command -v initctl >/dev/null 2>&1; then
        initctl stop dcpro-koreader-autostart >/dev/null 2>&1 || true
    fi
    [ -e "$LEGACY_AUTOSTART_JOB" ] || return 0

    method=""
    if command -v mntroot >/dev/null 2>&1 && mntroot rw >/dev/null 2>&1; then method="mntroot"
    elif mount -o remount,rw / >/dev/null 2>&1; then method="mount"
    else
        log "WARN: rootfs readonly; stale Upstart job left in place but points to disabled no-op script"
        return 0
    fi

    rm -f "$LEGACY_AUTOSTART_JOB" 2>/dev/null || true
    if [ "$method" = "mntroot" ]; then mntroot ro >/dev/null 2>&1 || true
    else mount -o remount,ro / >/dev/null 2>&1 || true; fi
    command -v initctl >/dev/null 2>&1 && initctl reload-configuration >/dev/null 2>&1 || true
    return 0
}

koreader_running(){
    for c in /proc/[0-9]*/cmdline; do
        [ -r "$c" ] || continue
        tr '\000' ' ' < "$c" 2>/dev/null | grep -Eq '(^|[ /])reader\.lua([ ]|$)' && return 0
    done
    return 1
}

find_koreader_launcher(){
    if [ -x "$ROOT/koreader/koreader.sh" ]; then printf '%s\n' "$ROOT/koreader/koreader.sh"; return 0; fi
    if [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ]; then printf '%s\n' "$ROOT/extensions/koreader/bin/koreader.sh"; return 0; fi
    return 1
}

start_koreader_now(){
    rm -f "$DATA/LAUNCH_ONCE" 2>/dev/null || true
    if koreader_running; then log "KOReader already running; skip duplicate post-install launch"; return 0; fi
    launcher="$(find_koreader_launcher 2>/dev/null || true)"
    [ -n "$launcher" ] || return 1
    (
        sleep "${DCPRO_KOREADER_POSTINSTALL_DELAY:-2}" 2>/dev/null || true
        exec "$launcher" --asap
    ) </dev/null >/dev/null 2>&1 &
    log "KOReader post-install direct launch queued: $launcher --asap"
    return 0
}

log "DCPRO GhostGuard OneClick v14"
log "Root: $ROOT"
say 1 "GhostGuard OneClick v14"
say 2 "KOReader + SimpleUI + MTGuard5 GOLDEN"

# Disable reboot auto-open before any other work so reinstalling over the prior
# build cannot leave the crash-prone startup behavior active.
disable_koreader_boot_autostart

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

say 11 "[6/7] Giai nen + cai GhostGuard plugin..."
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
[ -f "$KO_ROOT/plugins/dcghostguardpro.koplugin/main.lua" ] || fail "GhostGuard plugin verification failed"

cat >> "$LOG" <<EOF
MTGuard5 golden install complete.
KOReader root: $KO_ROOT
SimpleUI detected: $SIMPLEUI_OK
KOReader reboot autostart: DISABLED
GhostGuard Library icon: REMOVED (use KOReader icon)
Artifact SHA-256: $GG_SHA256
Reports: $REPORT_DIR
EOF

printf 'ONECLICK_VERSION=14\nGHOSTGUARD_VERSION=0.9.1-local-mtguard5\nRUNTIME=mtguard1-adaptive-v3-approved-cover-nocloud\nARTIFACT_SHA256=%s\nKO_READER_ROOT=%s\nSIMPLEUI_DETECTED=%s\nKO_READER_DIRECT_LAUNCH=1\nKO_READER_BOOT_AUTOSTART=0\nKO_READER_LIBRARY_ENTRY=PRIMARY\nGHOSTGUARD_LIBRARY_ICON=REMOVED\nLEGACY_LAUNCH_ONCE=DISABLED\nADAPTIVE_CHECKPOINT_SAMPLES=4\nADAPTIVE_CHECKPOINT_SECONDS=30\nADAPTIVE_EXTERNAL_REPORT_SECONDS=5\nADAPTIVE_PROMOTION_MIN_CLUSTER=4\nADAPTIVE_PROMOTION_MIN_AGE_SECONDS=15\nREPORT_DIR=%s\nCLOUD_UPLOAD=REMOVED\nZENUI=REMOVED\nNATIVE_FILTER=SHADOW_ONLY\nINPUT_GRAB=OFF\nEVENT_INJECTION=OFF\n' \
    "$GG_SHA256" "$KO_ROOT" "$SIMPLEUI_OK" "$REPORT_DIR" > "$DATA/ONECLICK_V14_OK"

sync 2>/dev/null || true
log "SUCCESS"
say 14 "THANH CONG! Dang mo KOReader..."
say 15 "Tu mo sau reboot: DA TAT"
echo "MTGuard5 golden installed successfully."
echo "Opening KOReader directly. Reboot autostart is disabled."
start_koreader_now || log "WARN: could not queue immediate KOReader launch"
exit 0
