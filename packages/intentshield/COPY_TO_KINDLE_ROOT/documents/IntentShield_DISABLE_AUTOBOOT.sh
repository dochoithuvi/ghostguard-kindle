#!/bin/sh
set -eu
ROOT=/mnt/us
mkdir -p "$ROOT/GhostGuard_Reports/IntentGate"
exec >>"$ROOT/GhostGuard_Reports/IntentGate/boot-install.log" 2>&1
touch "$ROOT/DISABLE_INTENTSHIELD_BOOT" "$ROOT/DISABLE_INTENTGATE"
rm -f "$ROOT/ENABLE_INTENTSHIELD_BOOT" "$ROOT/ENABLE_INTENTSHIELD_GLOBAL"
J=/etc/upstart/dcpro-intentshield-boot.conf
if [ "$(id -u)" = 0 ] && [ -f "$J" ] && cmp -s "$J" "$ROOT/GhostGuardIntentTrial/dcpro-intentshield-boot.conf" && command -v mntroot >/dev/null; then
    if mntroot rw; then
        trap 'mntroot ro >/dev/null 2>&1 || :' EXIT
        rm -f "$J"; mntroot ro; trap - EXIT
    fi
fi
sync
echo 'Disabled via USB markers; reboot manually if needed.'
