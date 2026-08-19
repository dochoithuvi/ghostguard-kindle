#!/bin/sh
# DCPRO GhostGuard OneClick v12.1
# Self-contained production bootstrap for KPM v0.2.x.
# Installs/checks KOReader, applies tested KOReader GestureGuard + TouchMenuGuard
# fail-safes, optionally installs SimpleUI, refreshes the current multi-package
# KPM repository, installs GhostGuard 0.6.15, syncs the latest SimpleUI Tools
# bridge, then launches GhostGuard.

LIB_ONLY=${DCPRO_ONECLICK_LIB_ONLY:-0}
ROOT=${DCPRO_ONECLICK_ROOT:-/mnt/us}
LOG=${DCPRO_ONECLICK_LOG:-"$ROOT/documents/GhostGuard_Installer.log"}
TMP=${DCPRO_ONECLICK_TMP:-"$ROOT/.dcpro_ghostguard"}
FONT_SCALE=3

KPM=/var/local/kmc/bin/kpm
[ -x "$KPM" ] || KPM=/var/local/kmc/kindlehf/bin/kpm
[ -x "$KPM" ] || KPM=/var/local/kmc/kindlepw2/bin/kpm
if [ "$LIB_ONLY" != "1" ]; then
  [ -x "$KPM" ] || exit 1
fi

GG_REPO_ID=dochoithuvi-ghostguard
GG_REPO=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.v2.json
GG_EXPECT=0.6.15
GG_ARTIFACT=packages/ghostguard/artifacts/ghostguard_0.6.15_kindle5-kindlepw2-kindlehf.kpkg
GG_BRIDGE_URL=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/source/payload/dcghostguardpro.koplugin/simpleui_bridge.lua

KMC_REPO_ID=kindlemodding
KMC_REPO=https://cdn.jsdelivr.net/gh/KindleModding/repo@main/manifest.v2.json
KO_VER=2026.07

GG_GESTURE_MARKER=DCPRO_KOREADER_GESTURE_NIL_GUARD_V1
GG_TOUCHMENU_MARKER=DCPRO_KOREADER_TOUCHMENU_PAGE_GUARD_V1
GG_GESTURE_STATE="$TMP/KOREADER_GESTURE_GUARD_V1"
GG_TOUCHMENU_STATE="$TMP/KOREADER_TOUCHMENU_GUARD_V1"

mkdir -p "$TMP" "$(dirname "$LOG")" 2>/dev/null || true
: > "$LOG" 2>/dev/null || true

log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null; }

FBINK="$(command -v fbink 2>/dev/null || true)"
[ -n "$FBINK" ] || for x in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink; do
  [ -x "$x" ] && FBINK="$x" && break
done
say(){ [ -n "$FBINK" ] && "$FBINK" -S "$FONT_SCALE" -x 1 -y "$1" -r "$2" >/dev/null 2>&1 || true; }
run(){ log "> $*"; "$@" >> "$LOG" 2>&1; RC=$?; log "< rc=$RC"; return $RC; }
kpm_list(){ "$KPM" -y list-repo 2>&1; }
get(){
  U="$1"; O="$2"; rm -f "$O" 2>/dev/null
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --silent --show-error "$U" -o "$O"
  else
    wget -q -O "$O" "$U"
  fi
}

has_ko(){ [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ] || [ -x "$ROOT/koreader/koreader.sh" ]; }
ko_target(){
  case "$KPM" in
    */kindlehf/bin/kpm) echo kindlehf;;
    */kindlepw2/bin/kpm) echo kindlepw2;;
    *) [ -d /var/local/kmc/kindle5 ] && echo kindle5 || echo kindle;;
  esac
}

gg_plugin_target(){
  for b in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
    if [ -f "$b/plugins/dcghostguardpro.koplugin/main.lua" ]; then
      printf '%s\n' "$b/plugins/dcghostguardpro.koplugin"
      return 0
    fi
  done
  return 1
}
has_gg(){ T="$(gg_plugin_target 2>/dev/null || true)"; [ -n "$T" ] && [ -f "$T/simpleui_bridge.lua" ]; }

sync_simpleui_bridge(){
  T="$(gg_plugin_target 2>/dev/null || true)"
  [ -n "$T" ] || { log "ERROR: GhostGuard plugin target not found for SimpleUI bridge sync"; return 1; }
  B="$TMP/simpleui_bridge.lua"
  log "Syncing latest SimpleUI bridge: $GG_BRIDGE_URL"
  get "$GG_BRIDGE_URL" "$B" || { log "ERROR: SimpleUI bridge download failed"; return 1; }
  grep -q 'features/sui_quickactions' "$B" || { log "ERROR: bridge missing features/sui_quickactions"; return 1; }
  grep -q 'infra/sui_config' "$B" || { log "ERROR: bridge missing infra/sui_config"; return 1; }
  grep -q 'engines/sui_window' "$B" || { log "ERROR: bridge missing engines/sui_window"; return 1; }
  cp -f "$B" "$T/simpleui_bridge.lua" || { log "ERROR: cannot update installed SimpleUI bridge"; return 1; }
  grep -q 'features/sui_quickactions' "$T/simpleui_bridge.lua" || return 1
  grep -q 'infra/sui_config' "$T/simpleui_bridge.lua" || return 1
  grep -q 'engines/sui_window' "$T/simpleui_bridge.lua" || return 1
  log "SimpleUI Tools bridge sync: PASS ($T/simpleui_bridge.lua)"
  return 0
}

install_ko_direct(){
  T="$(ko_target)"; A="koreader-${T}-v${KO_VER}.zip"; U="https://github.com/koreader/koreader/releases/download/v${KO_VER}/${A}"; Z="$TMP/$A"; D="$TMP/ko_unpack"
  say 3 "KOReader: tai goi chinh thuc..."; log "Direct KOReader: $U"
  rm -rf "$D" "$Z"; mkdir -p "$D" || return 1
  get "$U" "$Z" || return 1
  command -v unzip >/dev/null 2>&1 || return 1
  unzip -q "$Z" -d "$D" >/dev/null 2>&1 || return 1
  S=""
  for d in "$D" "$D"/*; do
    if [ -x "$d/koreader/koreader.sh" ] || [ -x "$d/extensions/koreader/bin/koreader.sh" ]; then S="$d"; break; fi
  done
  [ -n "$S" ] || return 1
  [ -d "$S/koreader" ] && { rm -rf "$ROOT/koreader"; cp -R "$S/koreader" "$ROOT/koreader" || return 1; }
  [ -d "$S/extensions/koreader" ] && { mkdir -p "$ROOT/extensions"; rm -rf "$ROOT/extensions/koreader"; cp -R "$S/extensions/koreader" "$ROOT/extensions/koreader" || return 1; }
  rm -rf "$D" "$Z"
  has_ko
}

install_ko(){
  has_ko && { log "KOReader already installed."; return 0; }
  say 2 "[1/9] Cai KOReader..."
  R="$(kpm_list || true)"; printf '%s\n' "$R" >> "$LOG"
  printf '%s\n' "$R" | grep -q "$KMC_REPO_ID" || run "$KPM" -y add-repo "$KMC_REPO"
  run "$KPM" -y update || true
  run "$KPM" -y install koreader && has_ko && { log "KOReader installed by KPM."; return 0; }
  log "KPM KOReader install failed; using official release ZIP."
  install_ko_direct
}

koreader_find_luajit(){
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

koreader_validate_lua_syntax(){
  LUAJIT_BIN="$1"
  LUA_FILE="$2"
  LUA_EXPR="local f,e=loadfile([[$LUA_FILE]]); if not f then io.stderr:write((e or 'syntax error') .. '\\n'); os.exit(1) end"
  if "$LUAJIT_BIN" -e "$LUA_EXPR" >> "$LOG" 2>&1; then
    log "LuaJIT loadfile syntax validation: PASS ($LUA_FILE)"
    return 0
  fi
  log "ERROR: LuaJIT loadfile syntax validation failed; original file left untouched ($LUA_FILE)"
  return 1
}

patch_gesture_guard_one(){
  TARGET="$1"
  KO_ROOT="${TARGET%/frontend/device/gesturedetector.lua}"
  BACKUP="$TARGET.dcpro-pre-gesture-guard-v1.bak"
  PATCH_TMP="$TARGET.dcpro-gesture-guard-v1.tmp.$$"

  log "GestureGuard target: $TARGET"

  if grep -q "$GG_GESTURE_MARKER" "$TARGET" 2>/dev/null; then
    log "GestureGuard already patched: $TARGET"
    return 0
  fi

  grep -q '^local Contact = {}' "$TARGET" || { log "SKIP: GestureGuard Contact class anchor missing"; return 2; }
  grep -q '^function Contact:isTwoFingerTap(buddy_contact)' "$TARGET" || { log "SKIP: GestureGuard isTwoFingerTap anchor missing"; return 2; }
  grep -q '^function Contact:getPath(simple, diagonal, initial_tev)' "$TARGET" || { log "SKIP: GestureGuard getPath anchor missing"; return 2; }
  grep -q '^function Contact:isSwipe()' "$TARGET" || { log "SKIP: GestureGuard isSwipe anchor missing"; return 2; }
  grep -q '^function GestureDetector:feedEvent(tevs)' "$TARGET" || { log "SKIP: GestureGuard feedEvent anchor missing"; return 2; }
  grep -Fq 'local y_diff0 = math.abs(self.current_tev.y - self.initial_tev.y)' "$TARGET" || { log "SKIP: GestureGuard two-finger vulnerable expression not found"; return 2; }
  grep -Fq 'local y_diff = self.current_tev.y - initial_tev.y' "$TARGET" || { log "SKIP: GestureGuard getPath vulnerable expression not found"; return 2; }

  if [ ! -f "$BACKUP" ]; then
    cp -p "$TARGET" "$BACKUP" || { log "ERROR: cannot create GestureGuard backup $BACKUP"; return 1; }
    log "GestureGuard backup: $BACKUP"
  else
    log "GestureGuard backup already exists: $BACKUP"
  fi

  awk -v marker="$GG_GESTURE_MARKER" '
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
  ' "$TARGET" > "$PATCH_TMP" || { rm -f "$PATCH_TMP" 2>/dev/null; log "ERROR: GestureGuard awk patch failed"; return 1; }

  grep -q "$GG_GESTURE_MARKER" "$PATCH_TMP" || { rm -f "$PATCH_TMP"; log "ERROR: GestureGuard patch marker missing"; return 1; }
  grep -q 'normalizeTouchCoordinates(self.current_tev, self.initial_tev)' "$PATCH_TMP" || { rm -f "$PATCH_TMP"; log "ERROR: GestureGuard self coordinate guard missing"; return 1; }
  grep -q 'DCPRO Gesture nil-guard dropped incomplete path frame' "$PATCH_TMP" || { rm -f "$PATCH_TMP"; log "ERROR: GestureGuard getPath guard missing"; return 1; }
  grep -q 'sane_touch_frame = normalizeTouchCoordinates' "$PATCH_TMP" || { rm -f "$PATCH_TMP"; log "ERROR: GestureGuard feedEvent guard missing"; return 1; }

  LUAJIT="$(koreader_find_luajit "$KO_ROOT" 2>/dev/null || true)"
  if [ -n "$LUAJIT" ]; then
    if ! koreader_validate_lua_syntax "$LUAJIT" "$PATCH_TMP"; then
      rm -f "$PATCH_TMP" 2>/dev/null || true
      return 1
    fi
  else
    log "WARN: LuaJIT binary not found; GestureGuard syntax compile check skipped"
  fi

  mv -f "$PATCH_TMP" "$TARGET" || { rm -f "$PATCH_TMP" 2>/dev/null; log "ERROR: cannot replace GestureGuard target"; return 1; }
  grep -q "$GG_GESTURE_MARKER" "$TARGET" || { log "ERROR: GestureGuard final marker verification failed"; return 1; }
  log "GestureGuard PATCHED: $TARGET"
  return 0
}

apply_gesture_guard(){
  FOUND=0
  APPLIED=0
  SKIPPED=0
  FAILED=0

  for TARGET in \
    "$ROOT/koreader/frontend/device/gesturedetector.lua" \
    "$ROOT/extensions/koreader/frontend/device/gesturedetector.lua"
  do
    [ -f "$TARGET" ] || continue
    FOUND=$((FOUND + 1))
    patch_gesture_guard_one "$TARGET"
    RC=$?
    case "$RC" in
      0) APPLIED=$((APPLIED + 1));;
      2) SKIPPED=$((SKIPPED + 1));;
      *) FAILED=$((FAILED + 1));;
    esac
  done

  [ "$FOUND" -gt 0 ] || { log "ERROR: KOReader gesturedetector.lua not found"; return 1; }
  [ "$FAILED" -eq 0 ] || { log "ERROR: GestureGuard patch failed on one or more targets"; return 1; }

  if [ "$APPLIED" -gt 0 ]; then
    {
      echo "DCPRO_KOREADER_GESTURE_GUARD_V1"
      echo "PATCH_REVISION=1.1"
      echo "UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
      echo "TARGETS=$APPLIED"
      echo "LOG=$LOG"
    } > "$GG_GESTURE_STATE" 2>/dev/null || true
    log "GestureGuard v1.1: PASS on $APPLIED KOReader target(s)."
  fi

  if [ "$SKIPPED" -gt 0 ]; then
    log "WARN: GestureGuard skipped $SKIPPED unknown KOReader code shape(s)."
    [ "$APPLIED" -gt 0 ] || return 2
  fi
  return 0
}

patch_touchmenu_guard_one(){
  TARGET="$1"
  KO_ROOT="${TARGET%/frontend/ui/widget/touchmenu.lua}"
  BACKUP="$TARGET.dcpro-pre-touchmenu-guard-v1.bak"
  PATCH_TMP="$TARGET.dcpro-touchmenu-guard-v1.tmp.$$"

  log "TouchMenuGuard target: $TARGET"

  if grep -q "$GG_TOUCHMENU_MARKER" "$TARGET" 2>/dev/null; then
    log "TouchMenuGuard already patched: $TARGET"
    return 0
  fi

  grep -q '^function TouchMenu:onNextPage()' "$TARGET" || { log "SKIP: TouchMenuGuard onNextPage anchor missing"; return 2; }
  grep -q '^function TouchMenu:onPrevPage()' "$TARGET" || { log "SKIP: TouchMenuGuard onPrevPage anchor missing"; return 2; }
  grep -q '^function TouchMenu:onGotoPage(nb)' "$TARGET" || { log "SKIP: TouchMenuGuard onGotoPage anchor missing"; return 2; }
  grep -Fq 'return self:onGotoPage(self.page + 1)' "$TARGET" || { log "SKIP: TouchMenuGuard vulnerable next-page expression missing"; return 2; }
  grep -Fq 'return self:onGotoPage(self.page - 1)' "$TARGET" || { log "SKIP: TouchMenuGuard vulnerable prev-page expression missing"; return 2; }
  grep -Fq 'if nb > self.page_num then' "$TARGET" || { log "SKIP: TouchMenuGuard vulnerable goto-page expression missing"; return 2; }

  if [ ! -f "$BACKUP" ]; then
    cp -p "$TARGET" "$BACKUP" || { log "ERROR: cannot create TouchMenuGuard backup $BACKUP"; return 1; }
    log "TouchMenuGuard backup: $BACKUP"
  else
    log "TouchMenuGuard backup already exists: $BACKUP"
  fi

  awk -v marker="$GG_TOUCHMENU_MARKER" '
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
  ' "$TARGET" > "$PATCH_TMP" || { rm -f "$PATCH_TMP" 2>/dev/null; log "ERROR: TouchMenuGuard awk patch failed"; return 1; }

  grep -q "$GG_TOUCHMENU_MARKER" "$PATCH_TMP" || { rm -f "$PATCH_TMP"; log "ERROR: TouchMenuGuard patch marker missing"; return 1; }
  grep -q 'if self.page == nil or self.page_num == nil then' "$PATCH_TMP" || { rm -f "$PATCH_TMP"; log "ERROR: TouchMenuGuard next/prev guard missing"; return 1; }
  grep -q 'if nb == nil or self.page_num == nil then' "$PATCH_TMP" || { rm -f "$PATCH_TMP"; log "ERROR: TouchMenuGuard goto guard missing"; return 1; }

  LUAJIT="$(koreader_find_luajit "$KO_ROOT" 2>/dev/null || true)"
  if [ -n "$LUAJIT" ]; then
    if ! koreader_validate_lua_syntax "$LUAJIT" "$PATCH_TMP"; then
      rm -f "$PATCH_TMP" 2>/dev/null || true
      return 1
    fi
  else
    log "WARN: LuaJIT binary not found; TouchMenuGuard syntax compile check skipped"
  fi

  mv -f "$PATCH_TMP" "$TARGET" || { rm -f "$PATCH_TMP" 2>/dev/null; log "ERROR: cannot replace TouchMenuGuard target"; return 1; }
  grep -q "$GG_TOUCHMENU_MARKER" "$TARGET" || { log "ERROR: TouchMenuGuard final marker verification failed"; return 1; }
  log "TouchMenuGuard PATCHED: $TARGET"
  return 0
}

apply_touchmenu_guard(){
  FOUND=0
  APPLIED=0
  SKIPPED=0
  FAILED=0

  for TARGET in \
    "$ROOT/koreader/frontend/ui/widget/touchmenu.lua" \
    "$ROOT/extensions/koreader/frontend/ui/widget/touchmenu.lua"
  do
    [ -f "$TARGET" ] || continue
    FOUND=$((FOUND + 1))
    patch_touchmenu_guard_one "$TARGET"
    RC=$?
    case "$RC" in
      0) APPLIED=$((APPLIED + 1));;
      2) SKIPPED=$((SKIPPED + 1));;
      *) FAILED=$((FAILED + 1));;
    esac
  done

  [ "$FOUND" -gt 0 ] || { log "ERROR: KOReader touchmenu.lua not found"; return 1; }
  [ "$FAILED" -eq 0 ] || { log "ERROR: TouchMenuGuard patch failed on one or more targets"; return 1; }

  if [ "$APPLIED" -gt 0 ]; then
    {
      echo "DCPRO_KOREADER_TOUCHMENU_GUARD_V1"
      echo "UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
      echo "TARGETS=$APPLIED"
      echo "LOG=$LOG"
    } > "$GG_TOUCHMENU_STATE" 2>/dev/null || true
    log "TouchMenuGuard v1: PASS on $APPLIED KOReader target(s)."
  fi

  if [ "$SKIPPED" -gt 0 ]; then
    log "WARN: TouchMenuGuard skipped $SKIPPED unknown KOReader code shape(s)."
    [ "$APPLIED" -gt 0 ] || return 2
  fi
  return 0
}

apply_koreader_safety_patches(){
  GRC=0
  TRC=0
  apply_gesture_guard || GRC=$?
  apply_touchmenu_guard || TRC=$?

  if [ "$GRC" -eq 1 ] || [ "$TRC" -eq 1 ]; then
    return 1
  fi
  if [ "$GRC" -eq 2 ] || [ "$TRC" -eq 2 ]; then
    return 2
  fi

  log "KOReader safety guards: PASS (GestureGuard v1.1 + TouchMenuGuard v1)"
  return 0
}

install_simpleui(){
  if [ -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ] || [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ] || [ -f "$ROOT/extensions/koreader/plugins/zen_ui.koplugin/main.lua" ] || [ -f "$ROOT/extensions/koreader/plugins/simpleui.koplugin/main.lua" ]; then
    return 0
  fi
  Z="$TMP/simpleui.zip"; D="$TMP/simpleui_unpack"; U=https://codeload.github.com/doctorhetfield-cmd/simpleui.koplugin/zip/refs/heads/main
  say 5 "[3/9] Cai SimpleUI..."; rm -rf "$D" "$Z"; mkdir -p "$D"
  get "$U" "$Z" || return 1
  command -v unzip >/dev/null 2>&1 || return 1
  unzip -q "$Z" -d "$D" >/dev/null 2>&1 || return 1
  S=""
  for d in "$D"/simpleui.koplugin "$D"/simpleui.koplugin-*; do [ -f "$d/main.lua" ] && S="$d" && break; done
  [ -n "$S" ] || return 1
  KO_ROOT=""
  for b in "$ROOT/koreader" "$ROOT/extensions/koreader"; do [ -d "$b/plugins" ] && { KO_ROOT="$b"; break; }; done
  [ -n "$KO_ROOT" ] || return 1
  mkdir -p "$KO_ROOT/plugins"
  rm -rf "$KO_ROOT/plugins/simpleui.koplugin"
  cp -R "$S" "$KO_ROOT/plugins/simpleui.koplugin" || return 1
  rm -rf "$D" "$Z"
  return 0
}

manifest_check(){
  M="$TMP/ghostguard_manifest.v2.json"
  MC="$TMP/ghostguard_manifest.compact.json"
  rm -f "$M" "$MC"
  log "Checking manifest: $GG_REPO"
  get "$GG_REPO" "$M" || { log "ERROR: manifest download failed"; return 1; }
  grep -q '"manifest_version"[[:space:]]*:[[:space:]]*2' "$M" || { log "ERROR: manifest is not v2"; return 1; }
  grep -q '"id"[[:space:]]*:[[:space:]]*"'$GG_REPO_ID'"' "$M" || { log "ERROR: manifest repo id mismatch"; return 1; }
  tr -d '[:space:]' < "$M" > "$MC" || { log "ERROR: cannot normalize manifest"; return 1; }
  grep -Fq '"ghostguard":{' "$MC" || { log "ERROR: ghostguard package missing"; return 1; }
  grep -Fq '"url":"'$GG_ARTIFACT'"' "$MC" || { log "ERROR: GhostGuard 0.6.15 artifact missing"; return 1; }
  grep -Fq '"version":[0,6,15]' "$MC" || { log "ERROR: expected GhostGuard 0.6.15 not present"; return 1; }
  log "Manifest validation: PASS (GhostGuard $GG_EXPECT)"
  rm -f "$M" "$MC"
  return 0
}

search_gg(){ "$KPM" -y search ghostguard 2>&1; }
repo_ready(){
  R="$(search_gg || true)"
  printf '%s\n' "$R" >> "$LOG"
  printf '%s\n' "$R" | grep -q -- '- ghostguard ('
}
repo_registered_current(){
  R="$1"
  printf '%s\n' "$R" | grep -Fq "$GG_REPO"
}

repair_gg(){
  say 6 "Lam moi GhostGuard repo..."
  manifest_check || return 1

  R="$(kpm_list || true)"
  printf '%s\n' "$R" >> "$LOG"
  if ! repo_registered_current "$R"; then
    log "GhostGuard repo is missing or points to a legacy endpoint; re-registering current v2 manifest."
    run "$KPM" -y remove-repo "$GG_REPO_ID" || log "remove-repo returned non-zero (repo may not exist)."
    run "$KPM" -y add-repo "$GG_REPO" || return 1
  fi

  run "$KPM" -y update || return 1
  if repo_ready; then
    log "GhostGuard repository exposes package ghostguard after refresh."
    return 0
  fi

  log "GhostGuard package still not visible; re-registering repository once."
  run "$KPM" -y remove-repo "$GG_REPO_ID" || true
  run "$KPM" -y add-repo "$GG_REPO" || return 1
  run "$KPM" -y update || return 1
  repo_ready || { log "ERROR: GhostGuard package not visible after repo refresh"; return 1; }
  log "GhostGuard v2 repo refresh complete."
  return 0
}

main(){
  log "========================================"
  log "DCPRO GhostGuard OneClick v12.1"
  log "Target: GitHub Raw manifest.v2.json"
  log "Expected: GhostGuard $GG_EXPECT + KOReader safety guards + latest SimpleUI Tools bridge"
  log "Date: $(date)"
  log "KPM=$KPM"
  log "========================================"

  say 1 "DCPRO GhostGuard Installer v12.1"
  say 2 "KPM v2 + KOReader safety guards"

  install_ko || { log "ERROR: KOReader install failed"; say 5 "LOI: Khong cai duoc KOReader"; exit 1; }
  say 4 "KOReader... OK"

  say 5 "[2/9] Ap dung KOReader safety guards..."
  PATCH_RC=0
  apply_koreader_safety_patches || PATCH_RC=$?
  case "$PATCH_RC" in
    0)
      say 6 "Gesture + TouchMenu guards... OK"
      ;;
    2)
      log "WARN: KOReader safety guards skipped for an unknown KOReader code shape; installer will continue without modifying unknown code."
      say 6 "KOReader guards: SKIP"
      ;;
    *)
      log "ERROR: KOReader safety guard patch failed; original target was preserved where validation failed."
      say 6 "LOI: KOReader safety guard"
      exit 1
      ;;
  esac

  install_simpleui || log "SimpleUI skipped; native/ZenUI may be used."
  say 7 "Kiem tra GhostGuard 0.6.15..."

  repair_gg || { log "ERROR: GhostGuard repo setup failed"; say 8 "LOI: Khong lam moi duoc repo"; exit 1; }
  say 8 "Cai/cap nhat GhostGuard 0.6.15..."

  INSTALL_OK=0
  if run "$KPM" -y install ghostguard; then
    INSTALL_OK=1
  else
    log "GhostGuard install returned non-zero; refreshing v2 repo and retrying once."
    run "$KPM" -y remove-repo "$GG_REPO_ID" || true
    run "$KPM" -y add-repo "$GG_REPO" || true
    run "$KPM" -y update || true
    if run "$KPM" -y install ghostguard; then INSTALL_OK=1; fi
  fi

  if [ "$INSTALL_OK" -ne 1 ] && ! has_gg; then
    log "ERROR: GhostGuard install failed and no existing runtime was found."
    say 9 "LOI: Cai GhostGuard that bai"
    exit 1
  fi

  [ "$INSTALL_OK" -eq 1 ] && log "GhostGuard install command completed." || log "Using existing GhostGuard runtime; applying latest bridge hotfix."

  say 9 "Dong bo SimpleUI Tools bridge..."
  sync_simpleui_bridge || { log "ERROR: SimpleUI Tools bridge sync failed"; say 10 "LOI: SimpleUI Tools bridge"; exit 1; }
  say 10 "GhostGuard + Tools... OK"

  run "$KPM" -y launch ghostguard || log "Launch returned non-zero; installation remains complete. Restart KOReader manually."

  log "Bootstrap complete. Registry endpoint: $GG_REPO"
  log "SimpleUI bridge endpoint: $GG_BRIDGE_URL"
  log "KOReader safety guards integrated: GestureGuard v1.1 + TouchMenuGuard v1"
  say 11 "HOAN TAT! RESTART KOREADER"
  exit 0
}

if [ "$LIB_ONLY" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

main "$@"
