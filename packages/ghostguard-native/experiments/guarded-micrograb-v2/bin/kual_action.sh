#!/bin/sh
ROOT="/mnt/us"
EXT="$ROOT/extensions/ghostguard-native-guarded-micrograb"
RUN="$EXT/bin/native_guarded_micrograb_v2.sh"
SVC="$ROOT/.dcpro_ghostguard/service"

REPORT="$SVC/native-guarded-micrograb-v2.report"
ACTIONS="$SVC/native-guarded-micrograb-v2.actions"
HEARTBEAT="$SVC/native-guarded-micrograb-v2.heartbeat"
EXITFILE="$SVC/native-guarded-micrograb-v2.exit"
PIDFILE="$SVC/native-guarded-micrograb-v2.kual.pid"
LOCKDIR="$SVC/native-guarded-micrograb-v2.lock"

STATUSDOC="$ROOT/documents/GhostGuard_Native_GuardedMicroGrab_Status.txt"
REPORTDOC="$ROOT/documents/GhostGuard_Native_GuardedMicroGrab_Report.txt"
ACTIONDOC="$ROOT/documents/GhostGuard_Native_GuardedMicroGrab_Actions.txt"
HEARTDOC="$ROOT/documents/GhostGuard_Native_GuardedMicroGrab_Heartbeat.txt"
EXITDOC="$ROOT/documents/GhostGuard_Native_GuardedMicroGrab_Exit.txt"
BGLOG="$ROOT/documents/GhostGuard_Native_GuardedMicroGrab_Runtime.log"

MODE="${1:-check}"
mkdir -p "$ROOT/documents" "$SVC" 2>/dev/null || true

status(){
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  {
    echo "GhostGuard Native Guarded Micro-Grab v2.1"
    if [ -d "$LOCKDIR" ]; then
      echo "LOCK=HELD"
    else
      echo "LOCK=FREE"
    fi
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "LAUNCHER_PID_ALIVE=YES"
    else
      echo "LAUNCHER_PID_ALIVE=NO"
    fi
    echo "LAUNCHER_PID=$pid"

    if [ -r "$HEARTBEAT" ]; then
      echo ""
      echo "[HEARTBEAT]"
      cat "$HEARTBEAT"
    fi

    if [ -r "$REPORT" ]; then
      echo ""
      echo "[REPORT]"
      sed -n \
        -e '/^VERDICT=/p' \
        -e '/^DETAIL=/p' \
        -e '/^ELAPSED_SECONDS=/p' \
        -e '/^PHASE=/p' \
        -e '/^BASELINE_PASS=/p' \
        -e '/^ACTIVE_ENABLED=/p' \
        -e '/^ACTIVE_DISABLED_REASON=/p' \
        -e '/^RAW_EVENTS=/p' \
        -e '/^COMPLETED_CONTACTS=/p' \
        -e '/^ELIGIBLE_STRICT_AXIS_ONLY=/p' \
        -e '/^PASSIVE_SHADOW_TRIGGERS=/p' \
        -e '/^ARMED_TRIGGERS=/p' \
        -e '/^GRAB_ATTEMPTS=/p' \
        -e '/^GRAB_SUCCEEDED=/p' \
        -e '/^GRAB_FAILED=/p' \
        -e '/^GRAB_TOTAL_MS=/p' \
        -e '/^MAX_GRAB_MS=/p' \
        -e '/^GRABBED_EVENTS_DROPPED=/p' \
        -e '/^GRAB_HIT_COMPLETE_CONTACTS=/p' \
        -e '/^GRABBED_TRACKING_STARTS=/p' \
        -e '/^GRABBED_TRACKING_ENDS=/p' \
        -e '/^BOUNDARY_CAP_HITS=/p' \
        -e '/^SAFETY_SKIP_/p' "$REPORT"
    fi

    if [ -r "$EXITFILE" ]; then
      echo ""
      echo "[EXIT]"
      cat "$EXITFILE"
    fi
  } >"$STATUSDOC"
}

launch(){
  if [ -d "$LOCKDIR" ]; then
    status
    return 4
  fi
  rm -f "$PIDFILE" 2>/dev/null || true

  if command -v start-stop-daemon >/dev/null 2>&1; then
    start-stop-daemon -S -b -m -p "$PIDFILE" -x /bin/sh -- "$RUN" test >>"$BGLOG" 2>&1
  elif command -v setsid >/dev/null 2>&1; then
    setsid /bin/sh "$RUN" test >>"$BGLOG" 2>&1 </dev/null &
    echo $! >"$PIDFILE"
  else
    nohup /bin/sh "$RUN" test >>"$BGLOG" 2>&1 </dev/null &
    echo $! >"$PIDFILE"
  fi
  sleep 2
  status
}

case "$MODE" in
  check)
    /bin/sh "$RUN" check
    ;;
  test30m)
    launch
    ;;
  rescue)
    /bin/sh "$RUN" rescue
    ;;
  status)
    status
    ;;
  export)
    [ -r "$REPORT" ] && cp "$REPORT" "$REPORTDOC" 2>/dev/null || echo "No report." >"$REPORTDOC"
    [ -r "$ACTIONS" ] && cp "$ACTIONS" "$ACTIONDOC" 2>/dev/null || echo "No actions." >"$ACTIONDOC"
    [ -r "$HEARTBEAT" ] && cp "$HEARTBEAT" "$HEARTDOC" 2>/dev/null || true
    [ -r "$EXITFILE" ] && cp "$EXITFILE" "$EXITDOC" 2>/dev/null || true
    status
    ;;
  *)
    exit 2
    ;;
esac
