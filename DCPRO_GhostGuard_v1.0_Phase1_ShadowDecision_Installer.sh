#!/bin/sh
# DCPRO GhostGuard v1.0 Phase 1 - Native Shadow Decision test installer
# Installs ONLY the read-only decision observer on top of an existing GhostGuard 0.9.1.
# Usage:
#   run normally -> install Phase 1 observer
#   run with "rollback" -> restore previous native-shadow observer

ROOT="${DCPRO_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
SERVICE_DIR="$DATA/service"
TARGET="$SERVICE_DIR/ghostguard-native-shadow.lua"
BACKUP="$SERVICE_DIR/ghostguard-native-shadow.pre-v1-phase1.bak"
PIDFILE="$SERVICE_DIR/native-shadow.pid"
SERVICE_PIDFILE="$SERVICE_DIR/service.pid"
SERVICE_SCRIPT="$SERVICE_DIR/ghostguard-service.sh"
STATUS="$SERVICE_DIR/native-shadow.status"
MARKER="$SERVICE_DIR/V1_PHASE1_SHADOW_DECISION"
TMP="$DATA/v1-phase1-shadow-decision.$$"
LOG="$ROOT/documents/GhostGuard_v1_Phase1.log"
URL="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/v1.0-native-shadow-decision/packages/ghostguard/source/system/ghostguard-native-shadow.lua"

mkdir -p "$SERVICE_DIR" "$ROOT/documents" 2>/dev/null || exit 1
: > "$LOG" 2>/dev/null || true
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }
fail(){ log "ERROR: $*"; exit 1; }

pid_matches(){
    pid="$1"; needle="$2"
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq "$needle"
}

stop_shadow(){
    if [ -r "$PIDFILE" ]; then
        pid="$(cat "$PIDFILE" 2>/dev/null || true)"
        if pid_matches "$pid" "ghostguard-native-shadow.lua"; then kill "$pid" 2>/dev/null || true; fi
    fi
    rm -f "$PIDFILE" 2>/dev/null || true
}

restart_supervisor(){
    if [ -r "$SERVICE_PIDFILE" ]; then
        pid="$(cat "$SERVICE_PIDFILE" 2>/dev/null || true)"
        if pid_matches "$pid" "ghostguard-service.sh"; then kill "$pid" 2>/dev/null || true; fi
    fi
    rm -f "$SERVICE_PIDFILE" 2>/dev/null || true
    [ -x "$SERVICE_SCRIPT" ] || [ -f "$SERVICE_SCRIPT" ] || return 1
    /bin/sh "$SERVICE_SCRIPT" >/dev/null 2>&1 &
    return 0
}

copy_compat(){
    src="$1"; dst="$2"
    cp -p "$src" "$dst" 2>/dev/null || cp "$src" "$dst" 2>/dev/null || cat "$src" > "$dst" 2>/dev/null || return 1
    if command -v cmp >/dev/null 2>&1; then cmp "$src" "$dst" >/dev/null 2>&1; else [ "$(wc -c < "$src")" = "$(wc -c < "$dst")" ]; fi
}

find_luajit(){
    for x in "$ROOT/koreader/luajit" "$ROOT/koreader/bin/luajit" "$ROOT/extensions/koreader/luajit" "$ROOT/extensions/koreader/bin/luajit"; do
        [ -x "$x" ] && { printf '%s\n' "$x"; return 0; }
    done
    command -v luajit 2>/dev/null || true
}

download(){
    if command -v curl >/dev/null 2>&1; then
        curl -L -f -sS "$URL" -o "$TMP" >>"$LOG" 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$TMP" "$URL" >>"$LOG" 2>&1
    else return 1; fi
}

verify_phase1(){
    f="$1"
    [ -s "$f" ] || return 1
    grep -Fq 'MODE=READ_ONLY_SHADOW_DECISION' "$f" || return 1
    grep -Fq 'DECISION_POLICY=STRONG_EVIDENCE_V1' "$f" || return 1
    grep -Fq 'ACTUAL_SUPPRESSION=OFF' "$f" || return 1
    grep -Fq 'INPUT_GRAB=OFF' "$f" || return 1
    grep -Fq 'EVENT_INJECTION=OFF' "$f" || return 1
    grep -Fq 'FAIL_OPEN=YES' "$f" || return 1
    grep -Fq 'local O_RDONLY = 0' "$f" || return 1
    grep -Fq 'WOULD_SUPPRESS' "$f" || return 1
    ! grep -Fq 'ffi.C.ioctl' "$f" || return 1
    ! grep -Fq 'ffi.C.write' "$f" || return 1
    ! grep -Fq 'O_RDWR' "$f" || return 1
    ! grep -Fq 'O_WRONLY' "$f" || return 1

    lua="$(find_luajit)"
    if [ -n "$lua" ]; then "$lua" -e "assert(loadfile([[$f]]))" >>"$LOG" 2>&1 || return 1; fi
    return 0
}

rollback(){
    [ -f "$BACKUP" ] || fail "Rollback backup not found: $BACKUP"
    stop_shadow
    copy_compat "$BACKUP" "$TARGET" || fail "Cannot restore native shadow backup"
    chmod 644 "$TARGET" 2>/dev/null || true
    rm -f "$MARKER" "$STATUS" 2>/dev/null || true
    restart_supervisor || fail "Cannot restart GhostGuard supervisor"
    log "ROLLBACK SUCCESS"
    echo "GhostGuard native shadow rolled back."
    exit 0
}

[ "${1:-}" = "rollback" ] && rollback

[ -f "$TARGET" ] || fail "Existing GhostGuard native shadow not found. Install GhostGuard 0.9.1 first."
[ -f "$SERVICE_SCRIPT" ] || fail "GhostGuard supervisor not found."

download || fail "Cannot download Phase 1 observer"
verify_phase1 "$TMP" || { rm -f "$TMP"; fail "Phase 1 observer safety/syntax verification failed"; }

if [ ! -f "$BACKUP" ]; then copy_compat "$TARGET" "$BACKUP" || { rm -f "$TMP"; fail "Cannot create rollback backup"; }; fi

stop_shadow
copy_compat "$TMP" "$TARGET" || { rm -f "$TMP"; fail "Cannot install Phase 1 observer"; }
rm -f "$TMP" 2>/dev/null || true
chmod 644 "$TARGET" 2>/dev/null || true

cat > "$MARKER" <<EOF
DCPRO_GHOSTGUARD_V1_PHASE1
MODE=READ_ONLY_SHADOW_DECISION
ACTUAL_SUPPRESSION=OFF
INPUT_GRAB=OFF
EVENT_INJECTION=OFF
ROLLBACK=$BACKUP
INSTALLED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
EOF

restart_supervisor || fail "Phase 1 installed but GhostGuard supervisor could not restart"

log "SUCCESS"
log "Observer=$TARGET"
log "Status=$STATUS"
log "Decision log=$SERVICE_DIR/native-shadow-decisions.log"
log "Actual suppression=OFF"
echo "GhostGuard v1.0 Phase 1 Shadow Decision installed."
echo "Actual native suppression remains OFF."
echo "Decision log: $SERVICE_DIR/native-shadow-decisions.log"
exit 0
