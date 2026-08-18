#!/bin/sh
set -u

TARGET="/var/local/mesquite/KindleForge"
APP_ID="xyz.penguins184.kindleforge"

[ -d "$TARGET" ] || { echo "KindleForge launch: app not installed" >&2; exit 1; }
command -v lipc-set-prop >/dev/null 2>&1 || { echo "KindleForge launch: lipc-set-prop not found" >&2; exit 1; }

if [ -e /lib/ld-linux-armhf.so.3 ]; then
    UTILD="$TARGET/binaries/UtildHF"
else
    UTILD="$TARGET/binaries/UtildSF"
fi

[ -x "$UTILD" ] || chmod 755 "$UTILD" 2>/dev/null || true
[ -x "$UTILD" ] || { echo "KindleForge launch: compatible Utild binary missing" >&2; exit 1; }

# Utild provides the com.kindlemodding.utild messaging endpoint used by the WAF.
# Keep it isolated inside KindleForge instead of copying into /var/local/kmc,
# which may be immutable under KPM and is shared with unrelated packages.
if ! ps 2>/dev/null | grep -E '[U]tild(HF|SF)' >/dev/null 2>&1; then
    nohup "$UTILD" >/dev/null 2>&1 &
    sleep 1
fi

lipc-set-prop com.lab126.appmgrd start "app://$APP_ID" >/dev/null 2>&1 || {
    echo "KindleForge launch: appmgrd refused start request" >&2
    exit 1
}
exit 0
