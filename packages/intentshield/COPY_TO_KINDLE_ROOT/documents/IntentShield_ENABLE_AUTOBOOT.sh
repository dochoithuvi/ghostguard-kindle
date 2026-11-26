#!/bin/sh
# Explicit opt-in, after manual Global Shield test. No reboot here.
set -eu
ROOT=/mnt/us; B="$ROOT/GhostGuardIntentTrial"; LOG="$ROOT/GhostGuard_Reports/IntentGate/boot-install.log"
mkdir -p "$(dirname "$LOG")"; exec >>"$LOG" 2>&1
fail(){ echo "FAIL: $*"; exit 1; }
[ "$(id -u)" = 0 ] || fail 'requires root SH Integration or SSH'
[ ! -e "$ROOT/ENABLE_GHOSTGUARD_ZEN_BOOT" ] || fail 'disable old GhostGuard Zen boot first'
(cd "$B" && sha256sum -c BOOT_SHA256SUMS) || fail 'boot payload checksum mismatch'
[ ! -e "$ROOT/DISABLE_INTENTGATE" ] || fail 'remove DISABLE_INTENTGATE manually after recovery'
/bin/sh "$B/boot-launch.sh" probe || fail 'device preflight failed; see boot.log'
[ -d /etc/upstart ] && command -v mntroot >/dev/null || fail 'Upstart/mntroot unavailable'
J=/etc/upstart/dcpro-intentshield-boot.conf
[ ! -e "$J" ] || cmp -s "$J" "$B/dcpro-intentshield-boot.conf" || fail 'different job already exists'
if [ ! -e "$J" ]; then
    mntroot rw || fail 'root filesystem not writable'
    trap 'rm -f "$J.new.$$"; mntroot ro >/dev/null 2>&1 || :' EXIT
    trap 'exit 130' HUP INT TERM
    cp "$B/dcpro-intentshield-boot.conf" "$J.new.$$"
    chmod 644 "$J.new.$$"; cmp "$B/dcpro-intentshield-boot.conf" "$J.new.$$"
    mv "$J.new.$$" "$J"
    mntroot ro || fail 'could not remount read-only'
    trap - EXIT HUP INT TERM
fi
# Never start the job immediately; it must be triggered by next boot.
touch "$ROOT/ENABLE_INTENTSHIELD_GLOBAL" "$ROOT/ENABLE_INTENTSHIELD_BOOT"
rm -f "$ROOT/DISABLE_INTENTSHIELD_BOOT"
sync
echo 'SUCCESS: enabled for next reboot; no forced reboot. Delete ENABLE_INTENTSHIELD_BOOT to disable.'
