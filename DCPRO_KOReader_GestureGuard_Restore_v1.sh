#!/bin/sh
# Name: DCPRO KOReader GestureGuard RESTORE v1
# Restores the one-time backup created by DCPRO_KOReader_GestureGuard_Test_v1.sh.

ROOT=/mnt/us
LOG="$ROOT/documents/KOReader_GestureGuard_Restore.log"
STATE_FILE="$ROOT/.dcpro_ghostguard/KOREADER_GESTURE_GUARD_V1"

: > "$LOG" 2>/dev/null || true
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

FOUND=0
RESTORED=0
for TARGET in \
    "$ROOT/koreader/frontend/device/gesturedetector.lua" \
    "$ROOT/extensions/koreader/frontend/device/gesturedetector.lua"
do
    BACKUP="$TARGET.dcpro-pre-gesture-guard-v1.bak"
    [ -f "$BACKUP" ] || continue
    FOUND=$((FOUND + 1))
    if cp -p "$BACKUP" "$TARGET"; then
        RESTORED=$((RESTORED + 1))
        log "RESTORED: $TARGET"
    else
        log "ERROR: cannot restore $TARGET"
    fi
done

if [ "$FOUND" -eq 0 ]; then
    log "ERROR: no GestureGuard v1 backup found"
    printf '%s\n' "No GestureGuard v1 backup found." >&2
    exit 1
fi

if [ "$RESTORED" -ne "$FOUND" ]; then
    log "ERROR: restored $RESTORED of $FOUND target(s)"
    printf '%s\n' "Restore incomplete. See $LOG" >&2
    exit 1
fi

rm -f "$STATE_FILE" 2>/dev/null || true
log "SUCCESS: restored $RESTORED KOReader target(s). Restart KOReader."
printf '%s\n' "OK: KOReader GestureGuard v1 restored. Restart KOReader."
exit 0
