#!/bin/sh
set -u
ROOT="${GHOSTGUARD_US_ROOT:-/mnt/us}"
KO_ROOT=""
for candidate in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -d "$candidate/plugins" ]; then KO_ROOT="$candidate"; break; fi
done
TARGET="${KO_ROOT:-$ROOT/koreader}/plugins/dcghostguardpro.koplugin"
DATA="$ROOT/.dcpro_ghostguard"
SERVICE_DIR="$DATA/service"
SERVICE_PID="$SERVICE_DIR/service.pid"
LAUNCHER="$ROOT/documents/DCPRO_GhostGuard.sh"
ASSET="$ROOT/dcpro/ghostguard/assets/ghostguard_library_600x960.jpg"
UPSTART_JOB="/etc/upstart/dcpro-ghostguard.conf"
mkdir -p "$DATA" 2>/dev/null || true

if [ "${1:-}" = "upgrade" ]; then
    echo "GhostGuard upgrade: active plugin, service policy and license preserved for transactional replacement."
    exit 0
fi

# Full uninstall: fail-safe first and preserve the purchased key outside the removed plugin.
printf 'DCPRO_GHOSTGUARD_SAFE_MODE=1\nREASON=kpm-uninstall\n' > "$DATA/SAFE_MODE" 2>/dev/null || true
if [ -s "$TARGET/license.key" ]; then
    umask 077
    cp -p "$TARGET/license.key" "$DATA/license.key.kpm-backup" 2>/dev/null || true
fi

pid_is_ghostguard_service() {
    pid="$1"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq 'ghostguard-service.sh'
}

# Stop current supervisor before removing its boot job. A stale service.pid can
# refer to a reused PID after reboot, so verify /proc before sending a signal.
if [ -r "$SERVICE_PID" ]; then
    pid="$(cat "$SERVICE_PID" 2>/dev/null || true)"
    if pid_is_ghostguard_service "$pid"; then kill "$pid" 2>/dev/null || true; fi
fi
if command -v initctl >/dev/null 2>&1; then initctl stop dcpro-ghostguard >/dev/null 2>&1 || true; fi

remove_upstart_job() {
    [ -e "$UPSTART_JOB" ] || return 0
    method=""
    if command -v mntroot >/dev/null 2>&1 && mntroot rw >/dev/null 2>&1; then
        method="mntroot"
    elif mount -o remount,rw / >/dev/null 2>&1; then
        method="mount"
    else
        return 1
    fi
    rm -f "$UPSTART_JOB" 2>/dev/null || true
    if [ "$method" = "mntroot" ]; then mntroot ro >/dev/null 2>&1 || true
    else mount -o remount,ro / >/dev/null 2>&1 || true; fi
    return 0
}
remove_upstart_job || true

rm -rf "$TARGET"
if [ -f "$LAUNCHER" ] && grep -q 'DCPRO GhostGuard' "$LAUNCHER" 2>/dev/null; then rm -f "$LAUNCHER"; fi
rm -f "$ASSET"
rm -f "$SERVICE_DIR/ghostguard-service.sh" "$SERVICE_DIR/ghostguard-native-capture.sh" "$SERVICE_PID"
rm -f "$DATA/KPM_INSTALL_OK"

echo "GhostGuard v0.8 removed. Reports/profile/license backup/service policy kept in $DATA. SAFE_MODE left ON."
exit 0
