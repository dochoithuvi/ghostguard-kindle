#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
mkdir -p "$DATA" 2>/dev/null || true
# Direct KOReader launch only. Do not create LAUNCH_ONCE/MODE=AUTO here: that
# older hand-off caused GhostGuard to attach during KOReader's startup window.
rm -f "$DATA/LAUNCH_ONCE" 2>/dev/null || true
if [ -x "$ROOT/koreader/koreader.sh" ]; then exec "$ROOT/koreader/koreader.sh" --asap; fi
if [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ]; then exec "$ROOT/extensions/koreader/bin/koreader.sh" --asap; fi
echo "KOReader launcher not found" >&2
exit 2
