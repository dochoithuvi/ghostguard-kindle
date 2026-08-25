#!/bin/sh
# DCPRO GhostGuard v0.8 system supervisor.
#
# This process intentionally does NOT grab, write or inject input events.
# It survives independently of KOReader, tracks power/controller lifecycle,
# and leaves actual touch suppression to the tested KOReader protection bridge.
set -u

VERSION="0.8.0"
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
SERVICE_DIR="$DATA/service"
CONFIG="$SERVICE_DIR/config.env"
STATUS="$SERVICE_DIR/service.status"
LOG="$SERVICE_DIR/service.log"
PIDFILE="$SERVICE_DIR/service.pid"
FINGERPRINT="$SERVICE_DIR/controller.fingerprint"
FINGERPRINT_PREV="$SERVICE_DIR/controller.previous"
RESUME_REQUEST="$SERVICE_DIR/resume.request"
WAKE_SEQ_FILE="$SERVICE_DIR/wake.seq"
CONTROLLER_CHANGED="$SERVICE_DIR/CONTROLLER_CHANGED"
LOOP_SECONDS="${GHOSTGUARD_SERVICE_POLL_SECONDS:-5}"
HEARTBEAT_SECONDS="${GHOSTGUARD_SERVICE_HEARTBEAT_SECONDS:-300}"

mkdir -p "$SERVICE_DIR" 2>/dev/null || exit 0

log() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$*" >> "$LOG" 2>/dev/null || true
    # Keep flash writes bounded. Truncate only when the log grows beyond ~64 KiB.
    if [ -f "$LOG" ]; then
        size="$(wc -c < "$LOG" 2>/dev/null || echo 0)"
        if [ "${size:-0}" -gt 65536 ] 2>/dev/null; then
            tail -n 250 "$LOG" > "$LOG.tmp.$$" 2>/dev/null && mv -f "$LOG.tmp.$$" "$LOG" 2>/dev/null || true
        fi
    fi
}

write_atomic() {
    path="$1"
    tmp="${path}.tmp.$$"
    cat > "$tmp" 2>/dev/null || return 1
    mv -f "$tmp" "$path" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

if [ ! -f "$CONFIG" ]; then
    cat > "$CONFIG" <<'EOF'
# DCPRO GhostGuard v0.8 persistent service policy
ENABLED=1
AUTOSTART=1
RESUME_AFTER_WAKE=1
PAUSE_DURING_SLEEP=1
DESIRED_MODE=AUTO
EOF
fi

# Load only known scalar keys; do not source arbitrary user content.
read_config() {
    ENABLED=1
    AUTOSTART=1
    RESUME_AFTER_WAKE=1
    PAUSE_DURING_SLEEP=1
    DESIRED_MODE=AUTO
    [ -r "$CONFIG" ] || return 0
    while IFS='=' read -r key value; do
        case "$key" in
            ENABLED) [ "$value" = "0" ] && ENABLED=0 || ENABLED=1 ;;
            AUTOSTART) [ "$value" = "0" ] && AUTOSTART=0 || AUTOSTART=1 ;;
            RESUME_AFTER_WAKE) [ "$value" = "0" ] && RESUME_AFTER_WAKE=0 || RESUME_AFTER_WAKE=1 ;;
            PAUSE_DURING_SLEEP) [ "$value" = "0" ] && PAUSE_DURING_SLEEP=0 || PAUSE_DURING_SLEEP=1 ;;
            DESIRED_MODE) DESIRED_MODE="$(printf '%s' "$value" | tr -cd 'A-Za-z0-9_-')" ;;
        esac
    done < "$CONFIG"
}

pid_is_ghostguard_service() {
    pid="$1"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq 'ghostguard-service.sh'
}

# Single instance without relying on flock (not present on every Kindle build).
# A stale PID file must never make us mistake an unrelated reused PID for GG.
if [ -r "$PIDFILE" ]; then
    oldpid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if pid_is_ghostguard_service "$oldpid"; then
        exit 0
    fi
    rm -f "$PIDFILE" 2>/dev/null || true
fi
printf '%s\n' "$$" > "$PIDFILE" 2>/dev/null || exit 0
cleanup() { rm -f "$PIDFILE" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP

read_one() {
    [ -r "$1" ] && tr '\n\r' '  ' < "$1" 2>/dev/null | sed 's/[[:space:]][[:space:]]*/ /g;s/^ //;s/ $//' || true
}

is_touch_name() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -Eq 'touch|zforce|cyttsp|atmel|fts|ft5|goodix|synaptics|wacom|elan'
}

choose_touch_sysfs() {
    fallback=""
    for sys in /sys/class/input/event*; do
        [ -e "$sys" ] || continue
        name="$(read_one "$sys/device/name")"
        if is_touch_name "$name"; then
            printf '%s\n' "$sys"
            return 0
        fi
        if [ -z "$fallback" ] && [ -r "$sys/device/capabilities/abs" ]; then
            abs="$(tr -d ' 0\n\r\t' < "$sys/device/capabilities/abs" 2>/dev/null || true)"
            [ -n "$abs" ] && fallback="$sys"
        fi
    done
    [ -n "$fallback" ] && printf '%s\n' "$fallback"
}

hash_text() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$1" | md5sum | awk '{print $1}'
    else
        printf '%s' "$1" | cksum | awk '{print $1 "-" $2}'
    fi
}

probe_controller() {
    sys="$(choose_touch_sysfs || true)"
    if [ -z "$sys" ]; then
        CONTROLLER_EVENT="NONE"
        CONTROLLER_NAME="UNKNOWN"
        CONTROLLER_HASH="NONE"
        CONTROLLER_RAW="NONE"
        return 1
    fi
    CONTROLLER_EVENT="$(basename "$sys")"
    CONTROLLER_NAME="$(read_one "$sys/device/name")"
    bustype="$(read_one "$sys/device/id/bustype")"
    vendor="$(read_one "$sys/device/id/vendor")"
    product="$(read_one "$sys/device/id/product")"
    revision="$(read_one "$sys/device/id/version")"
    phys="$(read_one "$sys/device/phys")"
    uniq="$(read_one "$sys/device/uniq")"
    abs="$(read_one "$sys/device/capabilities/abs")"
    key="$(read_one "$sys/device/capabilities/key")"
    # Deliberately exclude eventN from the hash: Linux may renumber it after wake.
    CONTROLLER_RAW="name=$CONTROLLER_NAME|bus=$bustype|vendor=$vendor|product=$product|version=$revision|phys=$phys|uniq=$uniq|abs=$abs|key=$key"
    CONTROLLER_HASH="$(hash_text "$CONTROLLER_RAW")"
    return 0
}

persist_fingerprint() {
    probe_controller || true
    # A transiently unavailable input node must not destroy the last known-good
    # controller identity. Keep the old fingerprint until a real controller is seen.
    [ "$CONTROLLER_HASH" != "NONE" ] || return 1
    {
        echo "DCPRO_GHOSTGUARD_CONTROLLER_FINGERPRINT_V1"
        echo "VERSION=$VERSION"
        echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
        echo "EVENT=$CONTROLLER_EVENT"
        echo "NAME=$CONTROLLER_NAME"
        echo "FINGERPRINT=$CONTROLLER_HASH"
        echo "RAW=$CONTROLLER_RAW"
    } | write_atomic "$FINGERPRINT" || true
}

power_state() {
    value=""
    if command -v lipc-get-prop >/dev/null 2>&1; then
        value="$(lipc-get-prop -s com.lab126.powerd state 2>/dev/null || true)"
        if [ -z "$value" ]; then
            value="$(lipc-get-prop com.lab126.powerd status 2>/dev/null | sed -n 's/.*[Ss]tate:[[:space:]]*//p' | head -1 || true)"
        fi
    fi
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z_-')"
    [ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "unknown"
}

is_active_state() {
    case "$1" in
        active|awake|resuming) return 0 ;;
        *) return 1 ;;
    esac
}

next_wake_seq() {
    n="$(cat "$WAKE_SEQ_FILE" 2>/dev/null || echo 0)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    n=$((n + 1))
    printf '%s\n' "$n" > "$WAKE_SEQ_FILE" 2>/dev/null || true
    printf '%s\n' "$n"
}

write_status() {
    state="$1"
    reason="$2"
    read_config
    {
        echo "DCPRO_GHOSTGUARD_SYSTEM_SERVICE_V1"
        echo "VERSION=$VERSION"
        echo "PID=$$"
        echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
        echo "POWER_STATE=$state"
        echo "REASON=$reason"
        echo "ENABLED=$ENABLED"
        echo "AUTOSTART=$AUTOSTART"
        echo "RESUME_AFTER_WAKE=$RESUME_AFTER_WAKE"
        echo "PAUSE_DURING_SLEEP=$PAUSE_DURING_SLEEP"
        echo "DESIRED_MODE=${DESIRED_MODE:-AUTO}"
        echo "EVENT=${CONTROLLER_EVENT:-UNKNOWN}"
        echo "CONTROLLER=${CONTROLLER_NAME:-UNKNOWN}"
        echo "FINGERPRINT=${CONTROLLER_HASH:-NONE}"
        echo "INPUT_GRAB=OFF"
        echo "EVENT_INJECTION=OFF"
        echo "FAIL_OPEN=YES"
    } | write_atomic "$STATUS" || true
}

mark_controller_changed() {
    old_hash="$1"
    new_hash="$2"
    reason="$3"
    printf 'OLD=%s\nNEW=%s\nREASON=%s\nUTC=%s\n' "$old_hash" "$new_hash" "$reason" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$CONTROLLER_CHANGED" 2>/dev/null || true
    log "controller fingerprint changed: $old_hash -> $new_hash ($reason); marker is sticky until profile approval"
}

on_wake() {
    read_config
    old_hash=""
    if [ -r "$FINGERPRINT" ]; then
        old_hash="$(sed -n 's/^FINGERPRINT=//p' "$FINGERPRINT" | head -1)"
        cp -f "$FINGERPRINT" "$FINGERPRINT_PREV" 2>/dev/null || true
    fi

    # Give the input stack a brief chance to reappear after powerd announces wake.
    attempts=0
    while [ "$attempts" -lt 4 ]; do
        probe_controller || true
        [ "$CONTROLLER_HASH" != "NONE" ] && break
        attempts=$((attempts + 1))
        sleep 1 2>/dev/null || true
    done

    new_hash="$CONTROLLER_HASH"
    match="YES"
    if [ "$new_hash" = "NONE" ]; then
        match="UNKNOWN"
        log "controller unavailable after wake; keeping previous fingerprint and failing open"
    elif [ -n "$old_hash" ] && [ "$old_hash" != "NONE" ] && [ "$new_hash" != "$old_hash" ]; then
        match="NO"
        mark_controller_changed "$old_hash" "$new_hash" "WAKE"
        persist_fingerprint || true
    else
        persist_fingerprint || true
        # Never clear CONTROLLER_CHANGED here. A real mismatch stays blocked
        # until KOReader explicitly approves a freshly learned profile.
        if [ -f "$CONTROLLER_CHANGED" ]; then match="PENDING_RELEARN"; fi
    fi

    seq="$(next_wake_seq)"
    if [ "$ENABLED" = "1" ] && [ "$RESUME_AFTER_WAKE" = "1" ]; then
        {
            echo "DCPRO_GHOSTGUARD_RESUME_REQUEST_V1"
            echo "WAKE_SEQ=$seq"
            echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
            echo "FINGERPRINT_MATCH=$match"
            echo "EVENT=$CONTROLLER_EVENT"
            echo "CONTROLLER=$CONTROLLER_NAME"
            echo "FINGERPRINT=$CONTROLLER_HASH"
            echo "DESIRED_MODE=${DESIRED_MODE:-AUTO}"
        } | write_atomic "$RESUME_REQUEST" || true
    fi
    write_status "active" "WAKE"
}

read_config
startup_old_hash=""
if [ -r "$FINGERPRINT" ]; then
    startup_old_hash="$(sed -n 's/^FINGERPRINT=//p' "$FINGERPRINT" | head -1)"
    cp -f "$FINGERPRINT" "$FINGERPRINT_PREV" 2>/dev/null || true
fi
persist_fingerprint || true
startup_new_hash="$CONTROLLER_HASH"
if [ -n "$startup_old_hash" ] && [ "$startup_old_hash" != "NONE" ] \
    && [ "$startup_new_hash" != "NONE" ] && [ "$startup_new_hash" != "$startup_old_hash" ]; then
    mark_controller_changed "$startup_old_hash" "$startup_new_hash" "SERVICE_START"
fi
state="$(power_state)"
prev_state="$state"
last_heartbeat="$(date +%s 2>/dev/null || echo 0)"
write_status "$state" "START"
log "service start pid=$$ power=$state controller=$CONTROLLER_NAME fingerprint=$CONTROLLER_HASH"

while :; do
    sleep "$LOOP_SECONDS" 2>/dev/null || sleep 5
    read_config
    state="$(power_state)"

    if [ "$state" != "$prev_state" ]; then
        log "power transition $prev_state -> $state"
        if is_active_state "$state" && ! is_active_state "$prev_state"; then
            on_wake
        else
            write_status "$state" "POWER_TRANSITION"
        fi
        prev_state="$state"
    fi

    now="$(date +%s 2>/dev/null || echo 0)"
    if [ "$now" -gt 0 ] 2>/dev/null && [ $((now - last_heartbeat)) -ge "$HEARTBEAT_SECONDS" ] 2>/dev/null; then
        probe_controller || true
        write_status "$state" "HEARTBEAT"
        last_heartbeat="$now"
    fi
done
