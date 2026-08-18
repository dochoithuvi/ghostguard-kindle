#!/bin/sh
set -u

DOCS="/mnt/us/documents/KindleForge"
TARGET="/var/local/mesquite/KindleForge"
STAGING="/var/local/mesquite/.KindleForge.runtime-new.$$"
BACKUP="/var/local/mesquite/.KindleForge.runtime-old"
APP_ID="xyz.penguins184.kindleforge"

valid_bundle() {
    [ -f "$1/config.xml" ] && [ -f "$1/index.html" ] && [ -f "$1/script.js" ] && \
    [ -f "$1/binaries/KFPM" ] && [ -f "$1/binaries/UtildHF" ] && [ -f "$1/binaries/UtildSF" ]
}

sync_docs_bundle() {
    valid_bundle "$DOCS" || return 0
    rm -rf "$STAGING" "$BACKUP"
    cp -Rp "$DOCS" "$STAGING" || return 1
    chmod 755 "$STAGING/binaries/KFPM" "$STAGING/binaries/UtildHF" "$STAGING/binaries/UtildSF" 2>/dev/null || true
    [ -d "$TARGET" ] && mv "$TARGET" "$BACKUP"
    if mv "$STAGING" "$TARGET"; then
        rm -rf "$BACKUP"
        return 0
    fi
    rm -rf "$STAGING"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET" 2>/dev/null || true
    return 1
}

start_utild() {
    if [ -e /lib/ld-linux-armhf.so.3 ]; then
        NAME="UtildHF"
        OTHER="UtildSF"
    else
        NAME="UtildSF"
        OTHER="UtildHF"
    fi

    SRC="$TARGET/binaries/$NAME"
    DST="/var/local/kmc/$NAME"
    [ -f "$SRC" ] || return 1
    mkdir -p /var/local/kmc 2>/dev/null || true
    cp -p "$SRC" "$DST" || return 1
    chmod 755 "$DST" 2>/dev/null || true

    if ! ps 2>/dev/null | grep "[$(printf '%s' "$NAME" | cut -c1)]$(printf '%s' "$NAME" | cut -c2-)" >/dev/null 2>&1; then
        killall "$OTHER" >/dev/null 2>&1 || true
        "$DST" >/dev/null 2>&1 || true
        sleep 1
    fi
    return 0
}

sync_docs_bundle || { echo "KindleForge runtime: cannot sync updated bundle" >&2; exit 1; }
valid_bundle "$TARGET" || { echo "KindleForge runtime: application bundle missing" >&2; exit 1; }
start_utild || { echo "KindleForge runtime: compatible Utild unavailable" >&2; exit 1; }

exec /usr/bin/mesquite -l "$APP_ID" -c "file://$TARGET/"
