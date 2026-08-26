#!/bin/sh
# DCPRO GhostGuard v1.0 Phase 1.1 Controller Mapper installer/runner
# Read-only mapper. Temporarily pauses Native Shadow while mapping, then restores it.

ROOT="${DCPRO_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
SERVICE_DIR="$DATA/service"
FINGERPRINT="$SERVICE_DIR/controller.fingerprint"
SERVICE_STATUS="$SERVICE_DIR/service.status"
SHADOW_PIDFILE="$SERVICE_DIR/native-shadow.pid"
MAPPER="$SERVICE_DIR/ghostguard-controller-mapper.lua"
PROFILE="$SERVICE_DIR/native-mapping.profile"
RAW="$SERVICE_DIR/native-mapping-raw.log"
LOG="$ROOT/documents/GhostGuard_v1_Phase1_1_Mapper.log"
PAUSE="$SERVICE_DIR/native-shadow.pause"
DURATION="${DCPRO_MAPPING_SECONDS:-90}"

URL="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/v1.0-phase1.1-controller-mapper/packages/ghostguard/source/system/ghostguard-controller-mapper.lua"

mkdir -p "$SERVICE_DIR" "$ROOT/documents" 2>/dev/null || exit 1
: > "$LOG" 2>/dev/null || true

log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }
fail(){ log "ERROR: $*"; rm -f "$PAUSE" 2>/dev/null || true; exit 1; }

find_luajit(){
    for x in "$ROOT/koreader/luajit" "$ROOT/koreader/bin/luajit" \
             "$ROOT/extensions/koreader/luajit" "$ROOT/extensions/koreader/bin/luajit"; do
        [ -x "$x" ] && { printf '%s\n' "$x"; return 0; }
    done
    command -v luajit 2>/dev/null || true
}

download(){
    out="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -L -f -sS "$URL" -o "$out" >>"$LOG" 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$URL" >>"$LOG" 2>&1
    else
        return 1
    fi
}

pid_matches(){
    pid="$1"; needle="$2"
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq "$needle"
}

stop_shadow(){
    if [ -r "$SHADOW_PIDFILE" ]; then
        pid="$(cat "$SHADOW_PIDFILE" 2>/dev/null || true)"
        if pid_matches "$pid" "ghostguard-native-shadow.lua"; then
            kill "$pid" 2>/dev/null || true
        fi
    fi
    rm -f "$SHADOW_PIDFILE" 2>/dev/null || true
}

controller_event(){
    e="$(sed -n 's/^EVENT=//p' "$FINGERPRINT" 2>/dev/null | head -1)"
    [ -n "$e" ] || e="$(sed -n 's/^EVENT=//p' "$SERVICE_STATUS" 2>/dev/null | head -1)"
    case "$e" in event[0-9]*) printf '%s\n' "$e";; *) return 1;; esac
}

verify_mapper(){
    f="$1"
    [ -s "$f" ] || return 1
    grep -Fq 'DCPRO GhostGuard v1.0 Phase 1.1 Controller Mapper' "$f" || return 1
    grep -Fq 'O_RDONLY + O_NONBLOCK' "$f" || return 1
    grep -Fq 'ORIENTATION_STATE=UNVERIFIED' "$f" || return 1
    grep -Fq 'ACTUAL_SUPPRESSION=OFF' "$f" || return 1
    ! grep -Fq 'ffi.C.write' "$f" || return 1
    ! grep -Fq 'O_RDWR' "$f" || return 1
    ! grep -Fq 'O_WRONLY' "$f" || return 1
    return 0
}

[ -r "$FINGERPRINT" ] || fail "controller.fingerprint missing; GhostGuard service must run first"

LUAJIT="$(find_luajit)"
[ -n "$LUAJIT" ] || fail "LuaJIT not found"

EVENT="$(controller_event)" || fail "touch controller event not found"
DEVICE="/dev/input/$EVENT"
[ -r "$DEVICE" ] || fail "$DEVICE is not readable"

TMP="$MAPPER.tmp.$$"
download "$TMP" || fail "cannot download controller mapper"
verify_mapper "$TMP" || { rm -f "$TMP"; fail "mapper safety verification failed"; }
"$LUAJIT" -e "assert(loadfile([[$TMP]]))" >>"$LOG" 2>&1 || { rm -f "$TMP"; fail "mapper Lua syntax validation failed"; }
mv -f "$TMP" "$MAPPER" || fail "cannot install mapper"
chmod 644 "$MAPPER" 2>/dev/null || true

touch "$PAUSE" 2>/dev/null || true
stop_shadow
sleep 1 2>/dev/null || true

log "Starting read-only controller mapping"
log "DEVICE=$DEVICE"
log "DURATION=$DURATION"
log "FINGERPRINT=$FINGERPRINT"

"$LUAJIT" "$MAPPER" "$DEVICE" "$FINGERPRINT" "$PROFILE" "$RAW" "$DURATION" >>"$LOG" 2>&1
RC=$?

rm -f "$PAUSE" 2>/dev/null || true

[ "$RC" -eq 0 ] || fail "controller mapper exited rc=$RC"
[ -s "$PROFILE" ] || fail "mapping profile not created"
[ -s "$RAW" ] || fail "raw mapping report not created"

grep -Fq 'ACTUAL_SUPPRESSION=OFF' "$PROFILE" || fail "mapping safety marker missing"
grep -Fq 'ORIENTATION_STATE=UNVERIFIED' "$PROFILE" || fail "orientation safety marker missing"

log "SUCCESS"
cat "$PROFILE" >>"$LOG" 2>/dev/null || true

echo "GhostGuard Phase 1.1 Controller Mapper complete."
echo "Profile: $PROFILE"
echo "Raw report: $RAW"
echo "Native blocking remains OFF."
exit 0
