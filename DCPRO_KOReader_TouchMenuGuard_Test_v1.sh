#!/bin/sh
# Name: DCPRO KOReader TouchMenuGuard TEST v1
# Experimental fail-safe for KOReader TouchMenu page/page_num nil crashes.
# This script does NOT modify GhostGuard or GestureGuard.

ROOT=/mnt/us
LOG="$ROOT/documents/KOReader_TouchMenuGuard_Test.log"
STATE_DIR="$ROOT/.dcpro_ghostguard"
STATE_FILE="$STATE_DIR/KOREADER_TOUCHMENU_GUARD_V1"
MARKER="DCPRO_KOREADER_TOUCHMENU_PAGE_GUARD_V1"

mkdir -p "$STATE_DIR" 2>/dev/null || true
: > "$LOG" 2>/dev/null || true

log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }
fail(){ log "ERROR: $*"; printf '%s\n' "KOReader TouchMenuGuard TEST v1: $*" >&2; exit 1; }

find_luajit() {
    KO_ROOT="$1"
    if [ -x "$KO_ROOT/luajit" ]; then printf '%s\n' "$KO_ROOT/luajit"; return 0; fi
    if command -v luajit >/dev/null 2>&1; then command -v luajit; return 0; fi
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
    KO_ROOT="${TARGET%/frontend/ui/widget/touchmenu.lua}"
    BACKUP="$TARGET.dcpro-pre-touchmenu-guard-v1.bak"
    TMP="$TARGET.dcpro-touchmenu-guard-v1.tmp.$$"

    log "Target: $TARGET"
    if grep -q "$MARKER" "$TARGET" 2>/dev/null; then
        log "Already patched: $TARGET"
        return 0
    fi

    grep -q '^function TouchMenu:onNextPage()' "$TARGET" || { log "SKIP: onNextPage anchor missing"; return 2; }
    grep -q '^function TouchMenu:onPrevPage()' "$TARGET" || { log "SKIP: onPrevPage anchor missing"; return 2; }
    grep -q '^function TouchMenu:onGotoPage(nb)' "$TARGET" || { log "SKIP: onGotoPage anchor missing"; return 2; }
    grep -Fq 'return self:onGotoPage(self.page + 1)' "$TARGET" || { log "SKIP: vulnerable next-page expression missing"; return 2; }
    grep -Fq 'return self:onGotoPage(self.page - 1)' "$TARGET" || { log "SKIP: vulnerable prev-page expression missing"; return 2; }
    grep -Fq 'if nb > self.page_num then' "$TARGET" || { log "SKIP: vulnerable goto-page expression missing"; return 2; }

    if [ ! -f "$BACKUP" ]; then
        cp -p "$TARGET" "$BACKUP" || { log "ERROR: cannot create backup $BACKUP"; return 1; }
        log "Backup: $BACKUP"
    else
        log "Backup already exists: $BACKUP"
    fi

    awk -v marker="$MARKER" '
        /^function TouchMenu:onNextPage\(\)/ {
            print "-- " marker
            print
            print "    if self.page == nil or self.page_num == nil then"
            print "        return true"
            print "    end"
            next
        }
        /^function TouchMenu:onPrevPage\(\)/ {
            print
            print "    if self.page == nil or self.page_num == nil then"
            print "        return true"
            print "    end"
            next
        }
        /^function TouchMenu:onGotoPage\(nb\)/ {
            print
            print "    if nb == nil or self.page_num == nil then"
            print "        return true"
            print "    end"
            next
        }
        { print }
    ' "$TARGET" > "$TMP" || { rm -f "$TMP" 2>/dev/null; log "ERROR: awk patch failed"; return 1; }

    grep -q "$MARKER" "$TMP" || { rm -f "$TMP"; log "ERROR: patch marker missing"; return 1; }
    grep -q 'if self.page == nil or self.page_num == nil then' "$TMP" || { rm -f "$TMP"; log "ERROR: next/prev guard missing"; return 1; }
    grep -q 'if nb == nil or self.page_num == nil then' "$TMP" || { rm -f "$TMP"; log "ERROR: goto guard missing"; return 1; }

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
log "DCPRO KOReader TouchMenuGuard TEST v1"
log "Date: $(date)"
log "Purpose: prevent TouchMenu page/page_num nil crashes"
log "========================================"

FOUND=0
PATCHED=0
FAILED=0
for TARGET in \
    "$ROOT/koreader/frontend/ui/widget/touchmenu.lua" \
    "$ROOT/extensions/koreader/frontend/ui/widget/touchmenu.lua"
do
    [ -f "$TARGET" ] || continue
    FOUND=$((FOUND + 1))
    patch_one "$TARGET"
    RC=$?
    if [ "$RC" -eq 0 ]; then PATCHED=$((PATCHED + 1)); else FAILED=$((FAILED + 1)); fi
done

[ "$FOUND" -gt 0 ] || fail "KOReader touchmenu.lua not found"
[ "$FAILED" -eq 0 ] || fail "one or more KOReader targets did not match the safe patch shape; see $LOG"
[ "$PATCHED" -gt 0 ] || fail "no KOReader target patched"

{
    echo "DCPRO_KOREADER_TOUCHMENU_GUARD_V1"
    echo "UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
    echo "TARGETS=$PATCHED"
    echo "LOG=$LOG"
} > "$STATE_FILE" 2>/dev/null || true

log "SUCCESS: TouchMenu page guard installed on $PATCHED KOReader target(s)."
log "Restart KOReader before testing."
printf '%s\n' "OK: KOReader TouchMenuGuard TEST v1 installed. Restart KOReader."
exit 0
