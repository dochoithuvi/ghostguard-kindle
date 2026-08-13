#!/bin/sh
# Name: DCPRO GhostGuard
# Author: Đồ Chơi Thú Vị
# Icon: /mnt/us/koreader/plugins/dcghostguardpro.koplugin/assets/ghostguard.svg
# DCPRO GhostGuard v0.5.0 Final launcher — direct KOReader launch.

MNT_US="${DCPRO_MNT_US:-/mnt/us}"
DATA="$MNT_US/.dcpro_ghostguard"
MARKER="$DATA/LAUNCH_ONCE"

mkdir -p "$DATA" || exit 1
printf 'REQUEST=HOME_LIBRARY\nMODE=AUTO\nCREATED_UTC=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$MARKER" || exit 1

if [ -x "$MNT_US/extensions/koreader/bin/koreader.sh" ]; then
    exec "$MNT_US/extensions/koreader/bin/koreader.sh"
fi
if [ -x "$MNT_US/koreader/koreader.sh" ]; then
    exec "$MNT_US/koreader/koreader.sh"
fi

command -v lipc-set-prop >/dev/null 2>&1 && \
    lipc-set-prop com.lab126.system toasterMessage "Không tìm thấy trình khởi chạy KOReader"
exit 2
