#!/bin/sh
# Integrated GhostGuard Native diagnostic capture for v0.8.
# Read-only, short-lived, no EVIOCGRAB, no uinput and no event injection.
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
STATE_DIR="$ROOT/.dcpro_ghostguard/service"
OUT="$STATE_DIR/native-capture-latest.txt"
RAW="$STATE_DIR/.native-capture.$$"
SECONDS="${GHOSTGUARD_NATIVE_WATCH_SECONDS:-8}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 1
trap 'rm -f "$RAW" 2>/dev/null || true' EXIT INT TERM

read_name() {
    [ -r "$1/device/name" ] && tr '\n' ' ' < "$1/device/name" 2>/dev/null | sed 's/[[:space:]]*$//' || true
}
choose_event() {
    fallback=""
    for sys in /sys/class/input/event*; do
        [ -e "$sys" ] || continue
        ev="$(basename "$sys")"
        dev="/dev/input/$ev"
        [ -r "$dev" ] || continue
        name="$(read_name "$sys")"
        if printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | grep -Eq 'touch|zforce|cyttsp|atmel|fts|ft5|goodix|synaptics|wacom|elan'; then
            printf '%s\n' "$ev"; return 0
        fi
        if [ -z "$fallback" ] && [ -r "$sys/device/capabilities/abs" ]; then
            abs="$(tr -d ' 0\n\r\t' < "$sys/device/capabilities/abs" 2>/dev/null || true)"
            [ -n "$abs" ] && fallback="$ev"
        fi
    done
    [ -n "$fallback" ] && printf '%s\n' "$fallback"
}

EVENT="$(choose_event || true)"
TMP="$OUT.tmp.$$"
{
    echo "DCPRO_GHOSTGUARD_NATIVE_CAPTURE_V080"
    echo "VERSION=0.8.0"
    echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "MODE=PASSIVE_READ_ONLY"
    echo "INPUT_GRAB=OFF"
    echo "EVENT_INJECTION=OFF"
    echo "CAPTURE_SECONDS=$SECONDS"
    echo "EVENT=${EVENT:-NONE}"
} > "$TMP"

if [ -z "$EVENT" ]; then
    echo "STATUS=NO_TOUCH_CANDIDATE" >> "$TMP"
    mv -f "$TMP" "$OUT"
    cat "$OUT"
    exit 0
fi

DEVICE="/dev/input/$EVENT"
echo "NAME=$(read_name "/sys/class/input/$EVENT")" >> "$TMP"
echo "[RAW_EVDEV_HEX]" >> "$TMP"
(
    if command -v hexdump >/dev/null 2>&1; then
        dd if="$DEVICE" bs=16 2>/dev/null | hexdump -v -e '16/1 "%02x " "\n"'
    elif command -v od >/dev/null 2>&1; then
        dd if="$DEVICE" bs=16 2>/dev/null | od -An -v -tx1
    else
        echo "NO_HEX_DUMPER_AVAILABLE"
    fi
) > "$RAW" 2>&1 &
pid=$!
sleep "$SECONDS" 2>/dev/null || sleep 8
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
if [ -s "$RAW" ]; then cat "$RAW" >> "$TMP"; echo "STATUS=CAPTURE_OK" >> "$TMP"; else echo "STATUS=NO_EVENTS_CAPTURED" >> "$TMP"; fi
mv -f "$TMP" "$OUT"
cat "$OUT"
