#!/bin/sh
# Fixture smoke test. Simulated process read-only /proc/sysfs on build host.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
sh -n "$ROOT/probe.sh"
BASE=$(mktemp -d "${TMPDIR:-/tmp}/gg-stock-audit.XXXXXX")
trap 'rm -rf "$BASE"' EXIT HUP INT TERM
mkdir -p "$BASE/proc/123/fd" "$BASE/sys/class/input/event1/device/capabilities" \
  "$BASE/sys/devices/platform/goodix-ts.0" "$BASE/dev/input" "$BASE/out"
echo 'com.amazon.kpp' > "$BASE/proc/123/comm"
ln -s /dev/input/event1 "$BASE/proc/123/fd/8"
echo 'goodix-ts' > "$BASE/sys/class/input/event1/device/name"
echo 'goodix_ts/input0' > "$BASE/sys/class/input/event1/device/phys"
echo 'f' > "$BASE/sys/class/input/event1/device/capabilities/abs"
echo '1' > "$BASE/sys/class/input/event1/device/capabilities/key"
echo '1' > "$BASE/sys/class/input/event1/device/properties"
echo 'state:enabled' > "$BASE/sys/devices/platform/goodix-ts.0/irq_info"
: > "$BASE/dev/input/event1"
: > "$BASE/dev/uinput"
GG_PROBE_OUT="$BASE/out" GG_PROBE_PROC="$BASE/proc" GG_PROBE_SYS="$BASE/sys" \
  GG_PROBE_DEV="$BASE/dev" GG_PROBE_DELAY=0 /bin/sh "$ROOT/probe.sh" --foreground
RESULT="$BASE/out/stock-input-audit-latest.txt"
for pattern in 'GOODIX_PLATFORM_NODE=YES' 'NAME=goodix-ts' \
  'COMM=com.amazon.kpp' 'NODE=/dev/input/event1' \
  'EVIOCGRAB=NO' 'UINPUT_OPEN=NO' 'STATUS=COMPLETE_READ_ONLY'; do
  grep -F "$pattern" "$RESULT" >/dev/null || { echo "missing $pattern" >&2; exit 1; }
done
[ ! -e "$BASE/out/.running" ] || { echo 'stale lock' >&2; exit 1; }
echo 'PASS: mock /proc + sysfs stock input probe'
