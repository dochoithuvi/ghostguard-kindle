#!/bin/sh
# Name: GhostGuard - Cai / Cap nhat
# Author: Do Choi Thu Vi
# DCPRO GhostGuard one-click bootstrap. Requires KPM/KMC + KOReader.

ROOT=/mnt/us
REPO="https://bit.ly/ghostguard"
LOG="$ROOT/.dcpro_ghostguard/BOOTSTRAP.log"
mkdir -p "$ROOT/.dcpro_ghostguard"
exec >>"$LOG" 2>&1
printf '\n=== %s ===\n' "$(date)"
KPM=""
for c in /var/local/kmc/kindlehf/bin/kpm /var/local/kmc/kindlepw2/bin/kpm; do
  if [ -x "$c" ]; then KPM="$c"; break; fi
done
if [ -z "$KPM" ]; then
  command -v lipc-set-prop >/dev/null 2>&1 && lipc-set-prop com.lab126.system toasterMessage "Khong tim thay KPM/KMC"
  exit 2
fi
PLAT_DIR="$(dirname "$(dirname "$KPM")")"
export LD_LIBRARY_PATH="$PLAT_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# add-repo is idempotent enough for bootstrap use; ignore duplicate-repo error.
"$KPM" add-repo "$REPO" || true
if ! "$KPM" install ghostguard; then
  command -v lipc-set-prop >/dev/null 2>&1 && lipc-set-prop com.lab126.system toasterMessage "GhostGuard: cai dat that bai - xem BOOTSTRAP.log"
  exit 3
fi
mkdir -p "$ROOT/.dcpro_ghostguard"
printf 'REQUEST=HOME_LIBRARY\nMODE=AUTO\nCREATED_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$ROOT/.dcpro_ghostguard/LAUNCH_ONCE"
if [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ]; then exec "$ROOT/extensions/koreader/bin/koreader.sh"; fi
if [ -x "$ROOT/koreader/koreader.sh" ]; then exec "$ROOT/koreader/koreader.sh"; fi
command -v lipc-set-prop >/dev/null 2>&1 && lipc-set-prop com.lab126.system toasterMessage "GhostGuard da cai, nhung khong tim thay KOReader"
exit 4
