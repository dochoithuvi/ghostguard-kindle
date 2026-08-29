#!/bin/sh
# DCPRO GhostGuard Native Guarded Micro-Grab v2.1
#
# ONE 30-minute qualification/probation:
#   Phase A 0-10 min: PASSIVE ONLY, zero EVIOCGRAB
#   Phase B 10-30 min: guarded 60ms micro-grab only on very strict repeat-4 bursts
#
# No uinput. No long-lived grab. No autostart.
# Physical touchscreen remains the Kindle framework's real input device.
#
# Commands:
#   check
#   test
#   rescue
#   report

ROOT="${DCPRO_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
SVC="$DATA/service"

REPORT="$SVC/native-guarded-micrograb-v2.report"
ACTIONS="$SVC/native-guarded-micrograb-v2.actions"
HEARTBEAT="$SVC/native-guarded-micrograb-v2.heartbeat"
RESCUE="$SVC/native-guarded-micrograb-v2.rescue"
LOCKDIR="$SVC/native-guarded-micrograb-v2.lock"
EXITFILE="$SVC/native-guarded-micrograb-v2.exit"
RUNTIMELOG="$ROOT/documents/GhostGuard_Native_GuardedMicroGrab_Runtime.log"

MODE="${1:-check}"

mkdir -p "$SVC" "$ROOT/documents" 2>/dev/null || exit 1
touch "$RUNTIMELOG" 2>/dev/null || true

find_luajit(){
  for x in "$ROOT/koreader/luajit" "$ROOT/koreader/bin/luajit" \
           "$ROOT/extensions/koreader/luajit" "$ROOT/extensions/koreader/bin/luajit"; do
    [ -x "$x" ] && { echo "$x"; return 0; }
  done
  command -v luajit 2>/dev/null || true
}

case "$MODE" in
  rescue)
    touch "$RESCUE"
    echo "GhostGuard native rescue requested."
    exit 0
    ;;
  report)
    [ -r "$REPORT" ] && cat "$REPORT" || { echo "No report yet."; exit 3; }
    exit 0
    ;;
  check|test) ;;
  *)
    echo "Usage: $0 [check|test|rescue|report]"
    exit 2
    ;;
esac

LUA="$(find_luajit)"
[ -n "$LUA" ] || {
  cat >"$REPORT" <<EOF
DCPRO_GHOSTGUARD_NATIVE_GUARDED_MICROGRAB_V2
VERDICT=PREFLIGHT_FAIL
DETAIL=LUAJIT_MISSING
EVIOCGRAB_ATTEMPTED=NO
FAIL_OPEN=YES
EOF
  exit 2
}

TMP="$SVC/native-guarded-micrograb-v2.lua"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/native_guarded_micrograb_v2.lua.part1" \
    "$SCRIPT_DIR/native_guarded_micrograb_v2.lua.part2" >"$TMP" || exit 6

"$LUA" -e "assert(loadfile([[$TMP]]))" >>"$RUNTIMELOG" 2>&1 || {
  rm -f "$TMP"
  cat >"$REPORT" <<EOF
DCPRO_GHOSTGUARD_NATIVE_GUARDED_MICROGRAB_V2
VERDICT=PREFLIGHT_FAIL
DETAIL=LUA_SYNTAX_ERROR
EVIOCGRAB_ATTEMPTED=NO
FAIL_OPEN=YES
EOF
  exit 7
}

# Runtime FFI self-test before any test can start.
"$LUA" -e 'local ffi=require("ffi"); ffi.cdef[[int getpid(void);]]; assert(tonumber(ffi.C.getpid()) > 1)' \
  >>"$RUNTIMELOG" 2>&1 || {
  rm -f "$TMP"
  cat >"$REPORT" <<EOF
DCPRO_GHOSTGUARD_NATIVE_GUARDED_MICROGRAB_V2
VERDICT=PREFLIGHT_FAIL
DETAIL=FFI_SELFTEST_FAILED
EVIOCGRAB_ATTEMPTED=NO
FAIL_OPEN=YES
EOF
  exit 8
}

if [ "$MODE" = "check" ]; then
  "$LUA" "$TMP" check "$RESCUE" "$REPORT" "$ACTIONS" "$HEARTBEAT"
  rc=$?
  rm -f "$TMP"
  exit "$rc"
fi

# Atomic singleton. Recover only a provably stale lock.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  oldpid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
  case "$oldpid" in
    ''|*[!0-9]*)
      rm -rf "$LOCKDIR" 2>/dev/null || true
      ;;
    *)
      if ! kill -0 "$oldpid" 2>/dev/null; then
        rm -rf "$LOCKDIR" 2>/dev/null || true
      fi
      ;;
  esac
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "Another live GhostGuard Native Guarded Micro-Grab instance is running (PID=$oldpid)." >>"$RUNTIMELOG"
    rm -f "$TMP"
    exit 9
  fi
fi
echo "$$" >"$LOCKDIR/pid"

rm -f "$RESCUE" "$REPORT" "$ACTIONS" "$HEARTBEAT" "$EXITFILE" 2>/dev/null || true

cleanup(){
  rc="$?"
  rm -rf "$LOCKDIR" 2>/dev/null || true
  rm -f "$RESCUE" "$TMP" 2>/dev/null || true
  {
    echo "EXIT_CODE=$rc"
    echo "EXIT_WALL=$(date +%s 2>/dev/null || echo UNKNOWN)"
  } >"$EXITFILE"
}
trap cleanup EXIT HUP INT TERM

echo "Starting Guarded Micro-Grab v2.1: 10m passive + 20m guarded active." >>"$RUNTIMELOG"

"$LUA" "$TMP" test "$RESCUE" "$REPORT" "$ACTIONS" "$HEARTBEAT" >>"$RUNTIMELOG" 2>&1 &
LPID=$!

# Independent hard watchdog. Killing the Lua process closes the evdev fd and
# therefore releases EVIOCGRAB even if the Lua state machine stalls.
(
  sleep 1830
  if kill -0 "$LPID" 2>/dev/null; then
    echo "WATCHDOG: terminating PID=$LPID after hard TTL" >>"$RUNTIMELOG"
    kill "$LPID" 2>/dev/null || true
    sleep 1
    kill -9 "$LPID" 2>/dev/null || true
  fi
) &
WPID=$!

wait "$LPID"
RC=$?
kill "$WPID" 2>/dev/null || true
exit "$RC"
