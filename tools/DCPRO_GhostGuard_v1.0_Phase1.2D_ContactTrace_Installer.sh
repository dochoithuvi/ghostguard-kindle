#!/bin/sh
# DCPRO GhostGuard v1.0 Phase 1.2D Native Contact Trace
# Diagnostic only. Captures three marked touch regions:
#   CENTER -> TOP_LEFT -> BOTTOM_RIGHT
# Native blocking remains OFF.

ROOT="${DCPRO_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
SVC="$DATA/service"
FINGERPRINT="$SVC/controller.fingerprint"
MAP="$SVC/native-mapping.profile"
SERVICE_PIDFILE="$SVC/service.pid"
SERVICE_SCRIPT="$SVC/ghostguard-service.sh"
SHADOW_PIDFILE="$SVC/native-shadow.pid"
PAUSE="$SVC/native-shadow.pause"
TRACER="$SVC/ghostguard-contact-tracer.lua"
TRACE="$SVC/native-contact-trace.log"
MARKER="$SVC/native-contact-trace.marker"
LOG="$ROOT/documents/GhostGuard_v1_Phase1_2D_ContactTrace.log"
URL="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/v1.0-phase1.1-controller-mapper/packages/ghostguard/source/system/ghostguard-contact-tracer.lua"
SUPERVISOR_WAS_RUNNING=0

mkdir -p "$SVC" "$ROOT/documents" 2>/dev/null || exit 1
: > "$LOG" 2>/dev/null || true
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

FBINK="$(command -v fbink 2>/dev/null || true)"
[ -n "$FBINK" ] || for x in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink; do
  [ -x "$x" ] && FBINK="$x" && break
done
say(){ [ -n "$FBINK" ] && "$FBINK" -S 2 -x 1 -y "$1" -r "$2" >/dev/null 2>&1 || true; }

find_luajit(){
  for x in "$ROOT/koreader/luajit" "$ROOT/koreader/bin/luajit" "$ROOT/extensions/koreader/luajit" "$ROOT/extensions/koreader/bin/luajit"; do
    [ -x "$x" ] && { printf '%s\n' "$x"; return 0; }
  done
  command -v luajit 2>/dev/null || true
}

pid_matches(){
  pid="$1"; needle="$2"
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  [ -r "/proc/$pid/cmdline" ] || return 1
  tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq "$needle"
}

stop_runtime(){
  if [ -r "$SERVICE_PIDFILE" ]; then
    pid="$(cat "$SERVICE_PIDFILE" 2>/dev/null || true)"
    if pid_matches "$pid" "ghostguard-service.sh"; then
      SUPERVISOR_WAS_RUNNING=1
      kill "$pid" 2>/dev/null || true
      sleep 2 2>/dev/null || true
    fi
  fi
  if [ -r "$SHADOW_PIDFILE" ]; then
    pid="$(cat "$SHADOW_PIDFILE" 2>/dev/null || true)"
    if pid_matches "$pid" "ghostguard-native-shadow.lua"; then
      kill "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$SERVICE_PIDFILE" "$SHADOW_PIDFILE" 2>/dev/null || true
}

restore_runtime(){
  rm -f "$PAUSE" 2>/dev/null || true
  if [ "$SUPERVISOR_WAS_RUNNING" = "1" ] && [ -f "$SERVICE_SCRIPT" ]; then
    /bin/sh "$SERVICE_SCRIPT" >/dev/null 2>&1 &
  fi
}

fail(){ log "ERROR: $*"; restore_runtime; exit 1; }

event="$(sed -n 's/^CAPTURE_EVENT=//p' "$MAP" 2>/dev/null | head -1)"
[ -n "$event" ] || event="$(sed -n 's/^EVENT=//p' "$FINGERPRINT" 2>/dev/null | head -1)"
case "$event" in event[0-9]*) :;; *) fail "touch event missing";; esac
device="/dev/input/$event"
[ -r "$device" ] || fail "$device not readable"

lua="$(find_luajit)"
[ -n "$lua" ] || fail "LuaJIT not found"

tmp="$TRACER.tmp.$$"
if command -v curl >/dev/null 2>&1; then
  curl -L -f -sS "$URL" -o "$tmp" >>"$LOG" 2>&1 || fail "download tracer failed"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$tmp" "$URL" >>"$LOG" 2>&1 || fail "download tracer failed"
else
  fail "no download tool"
fi

"$lua" -e "assert(loadfile([[$tmp]]))" >>"$LOG" 2>&1 || { rm -f "$tmp"; fail "tracer syntax invalid"; }
grep -Fq 'MODE=RAW_READ_ONLY_TRACE' "$tmp" || { rm -f "$tmp"; fail "tracer safety marker missing"; }
grep -Fq 'ACTUAL_SUPPRESSION=OFF' "$tmp" || { rm -f "$tmp"; fail "tracer suppression marker missing"; }
! grep -Fq 'ffi.C.write' "$tmp" || { rm -f "$tmp"; fail "unexpected write API found"; }
mv -f "$tmp" "$TRACER" || fail "cannot install tracer"

touch "$PAUSE" 2>/dev/null || true
stop_runtime
rm -f "$TRACE" "$MARKER" 2>/dev/null || true
printf 'TARGET=PREPARE\n' > "$MARKER"

"$lua" "$TRACER" "$device" "$FINGERPRINT" "$TRACE" "$MARKER" 54 >>"$LOG" 2>&1 &
tpid=$!
sleep 2

say 2 "[1/3] CHAM GIUA MAN HINH 3 LAN"
printf 'TARGET=CENTER\n' > "$MARKER"
sleep 15

say 3 "[2/3] CHAM GOC TREN TRAI 3 LAN"
printf 'TARGET=TOP_LEFT\n' > "$MARKER"
sleep 15

say 4 "[3/3] CHAM GOC DUOI PHAI 3 LAN"
printf 'TARGET=BOTTOM_RIGHT\n' > "$MARKER"
sleep 15

say 5 "DANG HOAN TAT TRACE..."
printf 'TARGET=FINISH\n' > "$MARKER"

wait "$tpid"
rc=$?
restore_runtime
SUPERVISOR_WAS_RUNNING=0

[ "$rc" -eq 0 ] || fail "tracer exited rc=$rc"
[ -s "$TRACE" ] || fail "trace file missing"

log "SUCCESS"
log "TRACE=$TRACE"
log "Native blocking remains OFF."
say 6 "TRACE XONG - GUI FILE CHO EM"
echo "Contact trace complete."
echo "Send: $TRACE"
echo "Log: $LOG"
exit 0
