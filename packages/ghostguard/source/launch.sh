#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
MARKER="$DATA/LAUNCH_ONCE"
mkdir -p "$DATA" || exit 1
printf 'REQUEST=KPM\nMODE=AUTO\nCREATED_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$MARKER" || exit 1
if [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ]; then exec "$ROOT/extensions/koreader/bin/koreader.sh"; fi
if [ -x "$ROOT/koreader/koreader.sh" ]; then exec "$ROOT/koreader/koreader.sh"; fi
echo "KOReader launcher not found" >&2
exit 2
