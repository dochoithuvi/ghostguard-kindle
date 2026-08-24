#!/bin/sh
set -u

VERSION="0.2.0"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"
TARGET="/var/local/mesquite/GhostGuardNative"
LATEST="$STATE_DIR/watch-latest.txt"
UI_COPY="$TARGET/watch.txt"
TMP="$STATE_DIR/.watch.$$"
RAW="$STATE_DIR/.watch-raw.$$"
LOCK="$STATE_DIR/watch.lock"
CAPTURE_SECONDS="${GHOSTGUARD_NATIVE_WATCH_SECONDS:-12}"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 1

cleanup() {
    rm -f "$TMP" "$RAW" 2>/dev/null || true
    rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if ! mkdir "$LOCK" 2>/dev/null; then
    exit 0
fi

dev_name() {
    [ -r "$1/device/name" ] && tr '\n' ' ' < "$1/device/name" 2>/dev/null | sed 's/[[:space:]]*$//' || true
}

is_name_candidate() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -Eq 'touch|zforce|cyttsp|atmel|fts|ft5|goodix|synaptics|wacom|elan'
}

choose_event() {
    fallback=""
    for sys in /sys/class/input/event*; do
        [ -e "$sys" ] || continue
        ev="$(basename "$sys")"
        dev="/dev/input/$ev"
        [ -r "$dev" ] || continue
        name="$(dev_name "$sys")"
        if is_name_candidate "$name"; then
            printf '%s\n' "$ev"
            return 0
        fi
        if [ -z "$fallback" ] && [ -r "$sys/device/capabilities/abs" ]; then
            abs="$(tr -d ' 0\n\r\t' < "$sys/device/capabilities/abs" 2>/dev/null || true)"
            [ -n "$abs" ] && fallback="$ev"
        fi
    done
    [ -n "$fallback" ] && printf '%s\n' "$fallback"
}

EVENT="$(choose_event || true)"
UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"

{
    echo "DCPRO_GHOSTGUARD_NATIVE_WATCH_V2"
    echo "VERSION=$VERSION"
    echo "MODE=PASSIVE_EVENT_WATCH"
    echo "PROTECT=OFF"
    echo "EVENT_NODE_OPEN=READ_ONLY"
    echo "INPUT_GRAB=OFF"
    echo "EVENT_INJECTION=OFF"
    echo "CAPTURE_SECONDS=$CAPTURE_SECONDS"
    echo "UTC=$UTC"

    if [ -z "$EVENT" ]; then
        echo "STATUS=NO_TOUCH_CANDIDATE"
        echo "EVENT=NONE"
        echo "DETAIL=No readable touchscreen candidate was found. Run the metadata probe and inspect DEVICE_PERMS/TOUCH_CANDIDATE."
        exit 0
    fi

    SYS="/sys/class/input/$EVENT"
    DEVICE="/dev/input/$EVENT"
    NAME="$(dev_name "$SYS")"
    echo "STATUS=CAPTURING"
    echo "EVENT=$EVENT"
    echo "DEVICE=$DEVICE"
    echo "NAME=${NAME:-UNKNOWN}"
    echo
    echo "[RAW_EVDEV_HEX]"
} > "$TMP"

if [ -z "$EVENT" ]; then
    mv "$TMP" "$LATEST" 2>/dev/null || exit 1
    [ -d "$TARGET" ] && cp "$LATEST" "$UI_COPY" 2>/dev/null || true
    cat "$LATEST"
    exit 0
fi

DEVICE="/dev/input/$EVENT"

# Short-lived passive capture only. dd opens the evdev node for reading; there
# is no grab, no write path and no synthetic input device. The capture process
# is stopped after CAPTURE_SECONDS so this is not a resident daemon.
(
    if command -v hexdump >/dev/null 2>&1; then
        dd if="$DEVICE" bs=16 2>/dev/null | hexdump -v -e '16/1 "%02x " "\n"'
    elif command -v od >/dev/null 2>&1; then
        dd if="$DEVICE" bs=16 2>/dev/null | od -An -v -tx1
    else
        echo "NO_HEX_DUMPER_AVAILABLE"
    fi
) > "$RAW" 2>&1 &
CAP_PID=$!

sleep "$CAPTURE_SECONDS" 2>/dev/null || sleep 12
kill "$CAP_PID" 2>/dev/null || true
wait "$CAP_PID" 2>/dev/null || true

if [ -s "$RAW" ]; then
    cat "$RAW" >> "$TMP"
    STATUS="CAPTURE_OK"
else
    echo "NO_EVENTS_CAPTURED" >> "$TMP"
    STATUS="NO_EVENTS_CAPTURED"
fi

{
    echo
    echo "[WATCH_RESULT]"
    echo "STATUS=$STATUS"
    echo "FINISHED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "SAFETY=READ_ONLY_NO_GRAB_NO_INJECTION"
} >> "$TMP"

mv "$TMP" "$LATEST" 2>/dev/null || exit 1
if [ -d "$TARGET" ]; then
    cp "$LATEST" "$UI_COPY" 2>/dev/null || true
fi

cat "$LATEST"
exit 0
