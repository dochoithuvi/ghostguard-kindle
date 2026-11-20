#!/bin/sh
# GhostGuard Native Stock-Input Audit v0.1 — by Dochoithuvi
# KINDLE BASIC 11 (2022) / FW 5.18.6 read-only, Library/SH Integration launcher
# NO firmware changes, NO EVIOCGRAB, NO /dev/uinput writes, NO injection,
# NO IRQ modification, NO reboot, NO KUAL/KOReader dependency.
# This DOES NOT test whether the Amazon stock reader accepts virtual touch.

set -u
umask 077
PATH=/bin:/usr/bin:/sbin:/usr/sbin
export PATH

OUT=${GG_PROBE_OUT:-/mnt/us/GhostGuard_StockInput_Reports}
PROC=${GG_PROBE_PROC:-/proc}
SYS=${GG_PROBE_SYS:-/sys}
DEV=${GG_PROBE_DEV:-/dev}
DELAY=${GG_PROBE_DELAY:-20}
case "$DELAY" in ''|*[!0-9]*) DELAY=20 ;; esac
[ "$DELAY" -le 120 ] || DELAY=120
LOCK="$OUT/.running"

utc() { date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date; }
safe_line() { [ -r "$1" ] && tr '\000\r\n' '   ' < "$1" 2>/dev/null | cut -c1-300 || :; }

get_fw() {
    for v in /etc/prettyversion.txt /etc/version.txt; do
        [ -r "$v" ] || continue
        safe_line "$v"
        return
    done
    printf '%s\n' 'UNKNOWN'
}

# Never read actual evdev data; symbolic-link lookup only.
# It is normal that the reader does NOT hold the evdev FD directly:
# Amazon's framework/display/input server may own it instead.
fd_owners() {
    heading=$1
    printf '\n[%s_EVDEV_OPEN_FDS]\n' "$heading"
    if ! command -v readlink >/dev/null 2>&1; then
        echo 'UNAVAILABLE: readlink not installed'
        return
    fi
    found=0
    count=0
    for process in "$PROC"/[0-9]*; do
        [ -d "$process/fd" ] || continue
        for descriptor in "$process"/fd/*; do
            [ -L "$descriptor" ] || continue
            link=$(readlink "$descriptor" 2>/dev/null || :)
            case "$link" in
                */input/event[0-9]*|*/input/event[0-9]*' (deleted)')
                    pid=${process##*/}
                    name=$(safe_line "$process/comm" | tr -cd 'A-Za-z0-9_.:-')
                    echo "PID=$pid COMM=${name:-UNKNOWN} FD=${descriptor##*/} NODE=$link"
                    found=1
                    ;;
            esac
            count=$((count + 1))
            # Bounded /proc scan to avoid burdening a weak e-reader.
            [ "$count" -le 12000 ] || { echo 'SCAN_LIMIT_REACHED=12000'; break 2; }
        done
    done
    [ "$found" -eq 1 ] || echo 'NO_VISIBLE_EVDEV_HOLDERS (does not imply unconsumed input)'
}

snapshot() {
    phase=$1
    echo
    echo "[$phase] UTC=$(utc)"
    echo '[RELEVANT_PROCESSES]'
    # Do not log process command lines: they may contain book paths/account data.
    shown=0
    for process in "$PROC"/[0-9]*; do
        [ -r "$process/comm" ] || continue
        name=$(safe_line "$process/comm" | tr -cd 'A-Za-z0-9_.:-')
        case "$name" in
            *kpp*|*KPP*|*reader*|*Reader*|*appmgr*|*framework*|*awesome*|*Xorg*|*chrom*|*Chrom*|*hermes*|*input*|*gestur*)
                echo "PID=${process##*/} COMM=$name"
                shown=$((shown + 1))
                [ "$shown" -le 70 ] || { echo 'PROCESS_DISPLAY_LIMIT_REACHED=70'; break; }
                ;;
        esac
    done
    fd_owners "$phase"
}

run() {
    mkdir -p "$OUT" 2>/dev/null || exit 1
    mkdir "$LOCK" 2>/dev/null || {
        echo "GhostGuard StockInput audit already running" >> "$OUT/launch.log"
        exit 0
    }
    trap 'rmdir "$LOCK" 2>/dev/null || :' 0 1 2 3 15
    TMP="$OUT/.audit.$$"
    TARGET="$OUT/stock-input-audit-latest.txt"
    {
        echo 'GHOSTGUARD_NATIVE_STOCK_INPUT_AUDIT_V0.1'
        echo 'SAFETY=PASSIVE_READ_ONLY'
        echo 'EVIOCGRAB=NO'
        echo 'UINPUT_OPEN=NO'
        echo 'EVENT_INJECTION=NO'
        echo 'IRQ_OR_POWER_WRITE=NO'
        echo 'AUTOSTART=NO'
        echo 'KO_READER_REQUIRED=NO'
        echo "START_UTC=$(utc)"
        echo "MODEL=$(safe_line "$PROC/device-tree/model")"
        echo "FIRMWARE=$(get_fw)"
        echo "KERNEL=$(uname -r 2>/dev/null || :)"
        if get_fw | grep -Fq '5.18.6'; then
            echo 'FW_5_18_6=YES'
        else
            echo 'FW_5_18_6=NOT_CONFIRMED'
        fi
        echo
        echo '[GOODIX_SYSFS]'
        goodix="$SYS/devices/platform/goodix-ts.0"
        if [ -d "$goodix" ]; then
            echo 'GOODIX_PLATFORM_NODE=YES'
            for leaf in irq_info reset modalias; do
                echo "${leaf}_PRESENT=$([ -e "$goodix/$leaf" ] && echo YES || echo NO)"
            done
            [ -r "$goodix/irq_info" ] && { echo 'IRQ_INFO_START'; cat "$goodix/irq_info" 2>/dev/null; echo 'IRQ_INFO_END'; }
        else
            echo 'GOODIX_PLATFORM_NODE=NO'
        fi
        echo
        echo '[INPUT_NODES]'
        for node in "$SYS"/class/input/event*; do
            [ -e "$node" ] || continue
            ev=${node##*/}
            echo "EVENT=$ev NAME=$(safe_line "$node/device/name") PHYS=$(safe_line "$node/device/phys")"
            echo "  ABS=$(safe_line "$node/device/capabilities/abs")"
            echo "  KEY=$(safe_line "$node/device/capabilities/key")"
            echo "  PROP=$(safe_line "$node/device/properties")"
            if [ -r "$DEV/input/$ev" ]; then echo '  READABLE=YES'; else echo '  READABLE=NO'; fi
        done
        echo
        echo '[VIRTUAL_INPUT_CAPABILITY_ONLY]'
        for path in "$DEV/uinput" "$DEV/input/uinput"; do
            if [ -e "$path" ]; then
                echo "NODE=$path PRESENT=YES READABLE=$([ -r "$path" ] && echo YES || echo NO) WRITABLE=$([ -w "$path" ] && echo YES || echo NO)"
            else
                echo "NODE=$path PRESENT=NO"
            fi
        done
        [ -r "$PROC/modules" ] && { echo 'UINPUT_MODULE_LINES:'; grep -Ei '(^uinput |^evdev |^goodix )' "$PROC/modules" || :; }
        echo
        snapshot LIBRARY_LAUNCH
        echo "READER_SNAPSHOT_DELAY_SECONDS=$DELAY"
        sleep "$DELAY"
        snapshot AFTER_DELAY
        echo
        echo 'WARNING=Presence of uinput does NOT prove Amazon accepts virtual touchscreen.'
        echo 'WARNING=FD scan cannot prove which reader ultimately processes touch.'
        echo 'NEXT_STEP=Review process holders and design a short, separately authorized virtual input acceptance test.'
        echo "FINISHED_UTC=$(utc)"
        echo 'STATUS=COMPLETE_READ_ONLY'
    } > "$TMP" 2>&1
    mv -f "$TMP" "$TARGET" || exit 1
    echo "$(utc) COMPLETE $TARGET" >> "$OUT/launch.log"
}

case "${1:-}" in
    --worker) run ;;
    --foreground) run ;;
    *)
        mkdir -p "$OUT" 2>/dev/null || exit 1
        echo "$(utc) START_REQUEST from Library; audit in background" >> "$OUT/launch.log"
        if command -v nohup >/dev/null 2>&1; then
            nohup /bin/sh "$0" --worker >/dev/null 2>&1 </dev/null &
        else
            (/bin/sh "$0" --worker >/dev/null 2>&1 </dev/null) &
        fi
        echo "GhostGuard StockInput Audit started. Open an Amazon book within ${DELAY}s."
        echo "Report: $OUT/stock-input-audit-latest.txt"
        exit 0
        ;;
esac
