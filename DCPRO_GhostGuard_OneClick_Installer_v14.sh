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
GG_SHA256="92df5cb7bd16ca1dacb5cdc40f1f8d49fef72bc4b216d8a1a87883704f26e552"
GG_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/artifacts/$GG_NAME"
GG_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/artifacts/$GG_NAME"
AUTOSTART_SCRIPT="$DATA/koreader-autostart.sh"
AUTOSTART_JOB="/etc/upstart/dcpro-koreader-autostart.conf"
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

install_koreader_autostart(){
    rm -f "$DATA/LAUNCH_ONCE" 2>/dev/null || true
    cat > "$AUTOSTART_SCRIPT" <<'EOS'
#!/bin/sh
set -u
ROOT="${DCPRO_ONECLICK_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
LOG="$ROOT/GhostGuard_Reports/KOReader_Autostart.log"
START_DELAY="${DCPRO_KOREADER_START_DELAY:-10}"
mkdir -p "$DATA" "${LOG%/*}" 2>/dev/null || exit 0
log(){ printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$*" >> "$LOG" 2>/dev/null || true; }
koreader_running(){
    for c in /proc/[0-9]*/cmdline; do
        [ -r "$c" ] || continue
        tr '\000' ' ' < "$c" 2>/dev/null | grep -Eq '(^|[ /])reader\.lua([ ]|$)' && return 0
    done
    return 1
}
find_launcher(){
    if [ -x "$ROOT/koreader/koreader.sh" ]; then printf '%s\n' "$ROOT/koreader/koreader.sh"; return 0; fi
    if [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ]; then printf '%s\n' "$ROOT/extensions/koreader/bin/koreader.sh"; return 0; fi
    return 1
}
# mounted_userstore may fire before package files are fully visible on slower boots.
i=0
launcher=""
while [ "$i" -lt 30 ]; do
    launcher="$(find_launcher 2>/dev/null || true)"
    [ -n "$launcher" ] && break
    i=$((i + 1))
    sleep 2 2>/dev/null || true
done
[ -n "$launcher" ] || { log "KOReader launcher unavailable; fail-open"; exit 0; }
sleep "$START_DELAY" 2>/dev/null || true
if koreader_running; then log "KOReader already running; skip duplicate launch"; exit 0; fi
# Never use the legacy GhostGuard LAUNCH_ONCE hand-off. KOReader boots through
# its own launcher and GhostGuard loads normally from plugins after UI startup.
rm -f "$DATA/LAUNCH_ONCE" 2>/dev/null || true
log "Launching KOReader directly: $launcher --asap"
exec "$launcher" --asap
EOS
    chmod 755 "$AUTOSTART_SCRIPT" 2>/dev/null || return 1

    [ -d /etc/upstart ] || { log "WARN: /etc/upstart unavailable; reboot autostart not installed"; return 1; }
    method=""
    if command -v mntroot >/dev/null 2>&1 && mntroot rw >/dev/null 2>&1; then method="mntroot"
    elif mount -o remount,rw / >/dev/null 2>&1; then method="mount"
    else log "WARN: rootfs could not be remounted rw for KOReader autostart"; return 1
    fi

    tmp="${AUTOSTART_JOB}.new.$$"
    cat > "$tmp" <<'EOF'
description "DCPRO KOReader direct autostart"

start on mounted_userstore
stop on stopping filesystems

# One launch per boot only. No respawn loop: if KOReader exits, the Kindle stays
# usable and KOReader will start again only after the next device reboot.
task
console none

script
    AUTOSTART="/mnt/us/.dcpro_ghostguard/koreader-autostart.sh"
    [ -x "$AUTOSTART" ] || exit 0
    exec /bin/sh "$AUTOSTART"
end script
EOF
    ok=0
    chmod 644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$AUTOSTART_JOB" 2>/dev/null || ok=1
    rm -f "$tmp" 2>/dev/null || true
    if [ "$method" = "mntroot" ]; then mntroot ro >/dev/null 2>&1 || true
    else mount -o remount,ro / >/dev/null 2>&1 || true; fi
    [ "$ok" = "0" ] || return 1
    command -v initctl >/dev/null 2>&1 && initctl reload-configuration >/dev/null 2>&1 || true
    return 0
}

start_koreader_now(){
    rm -f "$DATA/LAUNCH_ONCE" 2>/dev/null || true
    if command -v initctl >/dev/null 2>&1 && [ -f "$AUTOSTART_JOB" ]; then
        initctl stop dcpro-koreader-autostart >/dev/null 2>&1 || true
        if initctl start dcpro-koreader-autostart DCPRO_KOREADER_START_DELAY=2 >/dev/null 2>&1; then
            log "KOReader direct start handed to Upstart"
            return 0
        fi
    fi
    [ -x "$AUTOSTART_SCRIPT" ] || return 1
    ( DCPRO_KOREADER_START_DELAY=2 /bin/sh "$AUTOSTART_SCRIPT" ) </dev/null >/dev/null 2>&1 &
    log "KOReader direct start handed to fallback launcher"
    return 0
}

log "DCPRO GhostGuard OneClick v14"
log "Root: $ROOT"
say 1 "GhostGuard OneClick v14"
say 2 "KOReader + SimpleUI + MTGuard5 GOLDEN"

BOOTSTRAP="$TMP/koreader-simpleui-v14.sh"
say 4 "[1/8] Tai bootstrap KOReader/SimpleUI..."
log "Ensuring KOReader + SimpleUI."
download_pair "$BOOTSTRAP_PRIMARY" "$BOOTSTRAP_MIRROR" "$BOOTSTRAP" || fail "khong tai duoc bootstrap"
chmod 755 "$BOOTSTRAP" 2>/dev/null || true

say 6 "[2/8] Kiem tra/cai KOReader + SimpleUI..."
DCPRO_ONECLICK_ROOT="$ROOT" DCPRO_ONECLICK_LOG="$LOG" sh "$BOOTSTRAP" >>"$LOG" 2>&1 || fail "KOReader/SimpleUI bootstrap failed"

KO_ROOT=""
for candidate in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -d "$candidate/plugins" ]; then KO_ROOT="$candidate"; break; fi
done
[ -n "$KO_ROOT" ] || fail "khong tim thay KOReader sau bootstrap"
say 8 "[3/8] KOReader + SimpleUI... OK"

KPKG="$TMP/$GG_NAME"
say 9 "[4/8] Tai MTGuard5 GOLDEN..."
log "Downloading MTGuard5 golden package."
download_pair "$GG_PRIMARY" "$GG_MIRROR" "$KPKG" || fail "khong tai duoc MTGuard5 golden"

say 10 "[5/8] Kiem tra SHA-256..."
verify_sha256 "$KPKG" "$GG_SHA256" || fail "GhostGuard SHA-256 mismatch"

say 11 "[6/8] Giai nen + cai GhostGuard..."
rm -rf "$TMP/pkg" 2>/dev/null || true
mkdir -p "$TMP/pkg" || fail "khong tao duoc thu muc staging"
tar -xzf "$KPKG" -C "$TMP/pkg" >>"$LOG" 2>&1 || fail "khong giai nen duoc GhostGuard"
[ -f "$TMP/pkg/install.sh" ] || fail "GhostGuard package thieu install.sh"
(
    cd "$TMP/pkg" || exit 1
    GHOSTGUARD_US_ROOT="$ROOT" sh ./install.sh
) >>"$LOG" 2>&1 || fail "MTGuard5 golden install failed"

say 12 "[7/8] Cai auto-mo KOReader sau reboot..."
AUTOSTART_OK=0
if install_koreader_autostart; then AUTOSTART_OK=1
else log "WARN: persistent KOReader autostart unavailable; current install remains usable"; fi

say 13 "[8/8] Xac minh cai dat..."
SIMPLEUI_OK=0
for p in "$KO_ROOT/plugins/simpleui.koplugin" "$KO_ROOT/plugins/simpleui.koplugin/main.lua"; do
    if [ -e "$p" ]; then SIMPLEUI_OK=1; break; fi
done
[ "$SIMPLEUI_OK" = "1" ] || fail "SimpleUI verification failed"

cat >> "$LOG" <<EOF
MTGuard5 golden install complete.
KOReader root: $KO_ROOT
SimpleUI detected: $SIMPLEUI_OK
KOReader reboot autostart: $AUTOSTART_OK
Artifact SHA-256: $GG_SHA256
Reports: $REPORT_DIR
EOF

printf 'ONECLICK_VERSION=14\nGHOSTGUARD_VERSION=0.9.1-local-mtguard5\nRUNTIME=mtguard1-adaptive-v3-approved-cover-nocloud\nARTIFACT_SHA256=%s\nKO_READER_ROOT=%s\nSIMPLEUI_DETECTED=%s\nKO_READER_DIRECT_LAUNCH=1\nKO_READER_BOOT_AUTOSTART=%s\nLEGACY_LAUNCH_ONCE=DISABLED\nREPORT_DIR=%s\nCLOUD_UPLOAD=REMOVED\nZENUI=REMOVED\nNATIVE_FILTER=SHADOW_ONLY\nINPUT_GRAB=OFF\nEVENT_INJECTION=OFF\n' \
    "$GG_SHA256" "$KO_ROOT" "$SIMPLEUI_OK" "$AUTOSTART_OK" "$REPORT_DIR" > "$DATA/ONECLICK_V14_OK"

sync 2>/dev/null || true
log "SUCCESS"
say 14 "THANH CONG! Dang mo KOReader truc tiep..."
say 15 "Lan reboot sau KOReader se tu khoi dong"
echo "MTGuard5 golden installed successfully."
echo "Opening KOReader directly; reboot autostart: $AUTOSTART_OK"
start_koreader_now || log "WARN: could not hand off immediate KOReader launch"
exit 0
