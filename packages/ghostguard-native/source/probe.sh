#!/bin/sh
set -u

VERSION="0.2.0"
STATE_DIR="/mnt/us/.dcpro_ghostguard_native"
TARGET="/var/local/mesquite/GhostGuardNative"
LATEST="$STATE_DIR/probe-latest.txt"
UI_COPY="$TARGET/probe.txt"
TMP="$STATE_DIR/.probe.$$"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 1

cleanup() { rm -f "$TMP" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

safe_read() {
    [ -r "$1" ] && cat "$1" 2>/dev/null || true
}

lower() {
    tr '[:upper:]' '[:lower:]'
}

candidate_reason() {
    name="$1"
    abs="$2"
    lname="$(printf '%s' "$name" | lower)"
    case "$lname" in
        *touch*|*zforce*|*cyttsp*|*atmel*|*fts*|*ft5*|*goodix*|*synaptics*|*wacom*|*elan*)
            printf '%s' "name-match"
            return
            ;;
    esac
    compact_abs="$(printf '%s' "$abs" | tr -d ' 0\n\r\t')"
    if [ -n "$compact_abs" ]; then
        printf '%s' "abs-capability"
    else
        printf '%s' "no"
    fi
}

{
    echo "DCPRO_GHOSTGUARD_NATIVE_PROBE_V2"
    echo "VERSION=$VERSION"
    echo "MODE=READ_ONLY_METADATA"
    echo "PROTECT=OFF"
    echo "INPUT_GRAB=OFF"
    echo "EVENT_NODE_OPEN=NO"
    echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "UNAME=$(uname -a 2>/dev/null || true)"

    MODEL="$(safe_read /proc/device-tree/model | tr '\000' ' ' | sed 's/[[:space:]]*$//')"
    [ -n "$MODEL" ] || MODEL="$(safe_read /sys/firmware/devicetree/base/model | tr '\000' ' ' | sed 's/[[:space:]]*$//')"
    [ -n "$MODEL" ] || MODEL="UNKNOWN"
    echo "MODEL=$MODEL"

    if [ -r /etc/prettyversion.txt ]; then
        echo "FIRMWARE=$(tr '\n' ' ' < /etc/prettyversion.txt 2>/dev/null | sed 's/[[:space:]]*$//')"
    elif [ -r /etc/version.txt ]; then
        echo "FIRMWARE=$(tr '\n' ' ' < /etc/version.txt 2>/dev/null | sed 's/[[:space:]]*$//')"
    else
        echo "FIRMWARE=UNKNOWN"
    fi

    echo
    echo "[INPUT_EVENTS]"
    found=0
    for sys in /sys/class/input/event*; do
        [ -e "$sys" ] || continue
        found=1
        ev="$(basename "$sys")"
        dev="/dev/input/$ev"
        name="$(safe_read "$sys/device/name" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        phys="$(safe_read "$sys/device/phys" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        uniq="$(safe_read "$sys/device/uniq" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        abs="$(safe_read "$sys/device/capabilities/abs" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        key="$(safe_read "$sys/device/capabilities/key" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        prop="$(safe_read "$sys/device/properties" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        reason="$(candidate_reason "$name" "$abs")"
        perms="$(ls -l "$dev" 2>/dev/null | awk '{print $1 ":" $3 ":" $4}' || true)"
        echo "EVENT=$ev"
        echo "  NAME=${name:-UNKNOWN}"
        echo "  PHYS=${phys:-UNKNOWN}"
        echo "  UNIQ=${uniq:-UNKNOWN}"
        echo "  ABS=${abs:-0}"
        echo "  KEY=${key:-0}"
        echo "  PROP=${prop:-0}"
        echo "  DEVICE_PERMS=${perms:-UNKNOWN}"
        echo "  TOUCH_CANDIDATE=$reason"
    done
    [ "$found" = "1" ] || echo "NO_EVENT_SYSFS_ENTRIES"

    echo
    echo "[PROC_INPUT_DEVICES]"
    if [ -r /proc/bus/input/devices ]; then
        cat /proc/bus/input/devices
    else
        echo "UNAVAILABLE"
    fi

    echo
    echo "[SAFETY_ASSERTIONS]"
    echo "KOReader patching: NO"
    echo "EVIOCGRAB: NO"
    echo "uinput injection: NO"
    echo "background daemon: NO"
    echo "probe reads /dev/input/event*: NO"
} > "$TMP"

mv "$TMP" "$LATEST" || exit 1
if [ -d "$TARGET" ]; then
    cp "$LATEST" "$UI_COPY" 2>/dev/null || true
fi

cat "$LATEST"
exit 0
