#!/bin/sh
# Name: DCPRO KOReader GestureGuard TEST v1.1
# Experimental fail-safe patch for KOReader GestureDetector nil-coordinate crashes.
# Targeted at the v2026.07.1 code shape currently reproduced on KindleBasic4/goodix-ts.
# This script does NOT modify GhostGuard. It only patches KOReader's
# frontend/device/gesturedetector.lua and keeps a one-time backup beside it.

ROOT=/mnt/us
LOG="$ROOT/documents/KOReader_GestureGuard_Test.log"
STATE_DIR="$ROOT/.dcpro_ghostguard"
STATE_FILE="$STATE_DIR/KOREADER_GESTURE_GUARD_V1"
MARKER="DCPRO_KOREADER_GESTURE_NIL_GUARD_V1"

mkdir -p "$STATE_DIR" 2>/dev/null || true
: > "$LOG" 2>/dev/null || true

log() {
    printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true
}

fail() {
    log "ERROR: $*"
    printf '%s\n' "KOReader GestureGuard TEST v1.1: $*" >&2
    exit 1
}

find_luajit() {
    KO_ROOT="$1"
    if [ -x "$KO_ROOT/luajit" ]; then
        printf '%s\n' "$KO_ROOT/luajit"
        return 0
    fi
    if command -v luajit >/dev/null 2>&1; then
        command -v luajit
        return 0
    fi
    return 1
}

validate_lua_syntax() {
    LUAJIT_BIN="$1"
    LUA_FILE="$2"
    LUA_EXPR="local f,e=loadfile([[$LUA_FILE]]); if not f then io.stderr:write((e or 'syntax error') .. '\\n'); os.exit(1) end"
    if "$LUAJIT_BIN" -e "$LUA_EXPR" >> "$LOG" 2>&1; then
        log "LuaJIT loadfile syntax validation: PASS"
        return 0
    fi
    log "ERROR: LuaJIT loadfile syntax validation failed; original file left untouched"
    return 1
}

patch_one() {
    TARGET="$1"
    KO_ROOT="${TARGET%/frontend/device/gesturedetector.lua}"
    BACKUP="$TARGET.dcpro-pre-gesture-guard-v1.bak"
    TMP="$TARGET.dcpro-gesture-guard-v1.tmp.$$"

    log "Target: $TARGET"

    if grep -q "$MARKER" "$TARGET" 2>/dev/null; then
        log "Already patched: $TARGET"
        return 0
    fi

    # Refuse to modify an unknown future code shape. These are the exact vulnerable
    # functions/expressions seen in KOReader v2026.07.1 and current upstream source.
    grep -q '^local Contact = {}' "$TARGET" || { log "SKIP: Contact class anchor missing"; return 2; }
    grep -q '^function Contact:isTwoFingerTap(buddy_contact)' "$TARGET" || { log "SKIP: isTwoFingerTap anchor missing"; return 2; }
    grep -q '^function Contact:getPath(simple, diagonal, initial_tev)' "$TARGET" || { log "SKIP: getPath anchor missing"; return 2; }
    grep -q '^function Contact:isSwipe()' "$TARGET" || { log "SKIP: isSwipe anchor missing"; return 2; }
    grep -q '^function GestureDetector:feedEvent(tevs)' "$TARGET" || { log "SKIP: feedEvent anchor missing"; return 2; }
    grep -Fq 'local y_diff0 = math.abs(self.current_tev.y - self.initial_tev.y)' "$TARGET" || { log "SKIP: two-finger vulnerable expression not found"; return 2; }
    grep -Fq 'local y_diff = self.current_tev.y - initial_tev.y' "$TARGET" || { log "SKIP: getPath vulnerable expression not found"; return 2; }

    if [ ! -f "$BACKUP" ]; then
        cp -p "$TARGET" "$BACKUP" || { log "ERROR: cannot create backup $BACKUP"; return 1; }
        log "Backup: $BACKUP"
    else
        log "Backup already exists: $BACKUP"
    fi

    awk -v marker="$MARKER" '
        BEGIN {
            helper_done = 0
            in_getpath = 0
        }

        /^local Contact = \{\}/ && !helper_done {
            print
            print ""
            print "-- " marker
            print "-- Fail-safe for broken/out-of-order MT frames that leave x/y nil."
            print "-- Missing coordinates are repaired from the other snapshot when possible;"
            print "-- otherwise the malformed gesture frame is ignored instead of crashing KOReader."
            print "local function normalizeTouchCoordinates(current_tev, initial_tev)"
            print "    if not current_tev or not initial_tev then"
            print "        return false"
            print "    end"
            print "    local repaired = false"
            print "    if initial_tev.x == nil and current_tev.x ~= nil then initial_tev.x = current_tev.x; repaired = true end"
            print "    if initial_tev.y == nil and current_tev.y ~= nil then initial_tev.y = current_tev.y; repaired = true end"
            print "    if current_tev.x == nil and initial_tev.x ~= nil then current_tev.x = initial_tev.x; repaired = true end"
            print "    if current_tev.y == nil and initial_tev.y ~= nil then current_tev.y = initial_tev.y; repaired = true end"
            print "    if repaired then"
            print "        logger.warn(\"DCPRO Gesture nil-guard repaired incomplete touch coordinates\")"
            print "    end"
            print "    return current_tev.x ~= nil and current_tev.y ~= nil and initial_tev.x ~= nil and initial_tev.y ~= nil"
            print "end"
            helper_done = 1
            next
        }

        /^function Contact:isTwoFingerTap\(buddy_contact\)/ {
            print
            print "    if not buddy_contact or"
            print "       not normalizeTouchCoordinates(self.current_tev, self.initial_tev) or"
            print "       not normalizeTouchCoordinates(buddy_contact.current_tev, buddy_contact.initial_tev) or"
            print "       not self.current_tev.timev or not self.initial_tev.timev or"
            print "       not buddy_contact.current_tev.timev or not buddy_contact.initial_tev.timev then"
            print "        logger.warn(\"DCPRO Gesture nil-guard dropped incomplete two-finger tap frame\")"
            print "        return"
            print "    end"
            next
        }

        /^function Contact:getPath\(simple, diagonal, initial_tev\)/ {
            in_getpath = 1
            print
            next
        }

        in_getpath && /^    initial_tev = initial_tev or self.initial_tev$/ {
            print
            print "    if not normalizeTouchCoordinates(self.current_tev, initial_tev) then"
            print "        logger.warn(\"DCPRO Gesture nil-guard dropped incomplete path frame\")"
            print "        return nil, 0"
            print "    end"
            in_getpath = 0
            next
        }

        /^function Contact:isSwipe\(\)/ {
            print
            print "    if not normalizeTouchCoordinates(self.current_tev, self.initial_tev) or"
            print "       not self.current_tev.timev or not self.initial_tev.timev then"
            print "        logger.warn(\"DCPRO Gesture nil-guard dropped incomplete swipe frame\")"
            print "        return"
            print "    end"
            next
        }

        /^        local ges = contact.state\(contact\)$/ {
            print "        local sane_touch_frame = true"
            print "        if contact.initial_tev then"
            print "            sane_touch_frame = normalizeTouchCoordinates(contact.current_tev, contact.initial_tev)"
            print "        end"
            print "        local ges"
            print "        if sane_touch_frame then"
            print "            ges = contact.state(contact)"
            print "        else"
            print "            logger.warn(\"DCPRO Gesture nil-guard ignored malformed touch frame for slot\", slot)"
            print "            if tev.id == -1 then"
            print "                self:dropContact(contact)"
            print "            end"
            print "        end"
            next
        }

        { print }
    ' "$TARGET" > "$TMP" || { rm -f "$TMP" 2>/dev/null; log "ERROR: awk patch failed"; return 1; }

    grep -q "$MARKER" "$TMP" || { rm -f "$TMP"; log "ERROR: patch marker missing"; return 1; }
    grep -q 'normalizeTouchCoordinates(self.current_tev, self.initial_tev)' "$TMP" || { rm -f "$TMP"; log "ERROR: self coordinate guard missing"; return 1; }
    grep -q 'DCPRO Gesture nil-guard dropped incomplete path frame' "$TMP" || { rm -f "$TMP"; log "ERROR: getPath guard missing"; return 1; }
    grep -q 'sane_touch_frame = normalizeTouchCoordinates' "$TMP" || { rm -f "$TMP"; log "ERROR: feedEvent guard missing"; return 1; }

    LUAJIT="$(find_luajit "$KO_ROOT" 2>/dev/null || true)"
    if [ -n "$LUAJIT" ]; then
        if ! validate_lua_syntax "$LUAJIT" "$TMP"; then
            rm -f "$TMP" 2>/dev/null || true
            return 1
        fi
    else
        log "WARN: LuaJIT binary not found; syntax compile check skipped"
    fi

    mv -f "$TMP" "$TARGET" || { rm -f "$TMP" 2>/dev/null; log "ERROR: cannot replace target"; return 1; }
    grep -q "$MARKER" "$TARGET" || { log "ERROR: final marker verification failed"; return 1; }
    log "PATCHED: $TARGET"
    return 0
}

log "========================================"
log "DCPRO KOReader GestureGuard TEST v1.1"
log "Date: $(date)"
log "Purpose: prevent GestureDetector nil x/y arithmetic crashes"
log "========================================"

FOUND=0
PATCHED=0
FAILED=0
for TARGET in \
    "$ROOT/koreader/frontend/device/gesturedetector.lua" \
    "$ROOT/extensions/koreader/frontend/device/gesturedetector.lua"
do
    [ -f "$TARGET" ] || continue
    FOUND=$((FOUND + 1))
    patch_one "$TARGET"
    RC=$?
    if [ "$RC" -eq 0 ]; then
        PATCHED=$((PATCHED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done

[ "$FOUND" -gt 0 ] || fail "KOReader gesturedetector.lua not found"
[ "$FAILED" -eq 0 ] || fail "one or more KOReader targets did not match the safe patch shape; see $LOG"
[ "$PATCHED" -gt 0 ] || fail "no KOReader target patched"

{
    echo "DCPRO_KOREADER_GESTURE_GUARD_V1"
    echo "PATCH_REVISION=1.1"
    echo "UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
    echo "TARGETS=$PATCHED"
    echo "LOG=$LOG"
} > "$STATE_FILE" 2>/dev/null || true

log "SUCCESS: gesture nil-guard v1.1 installed on $PATCHED KOReader target(s)."
log "Restart KOReader before testing."
printf '%s\n' "OK: KOReader GestureGuard TEST v1.1 installed. Restart KOReader."
exit 0
