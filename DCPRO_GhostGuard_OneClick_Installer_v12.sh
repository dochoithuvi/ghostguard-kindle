#!/bin/sh
# DCPRO GhostGuard OneClick v12.0
# Touch-broken Kindle bootstrap: KOReader first, then SimpleUI, then GhostGuard.
# KPM v0.2.x: use the v2 repository manifest explicitly.
# v12.0: keeps GhostGuard 0.6.14, but guarantees the post-fix SimpleUI Tools bridge is synced from main.
ROOT=/mnt/us
KPM=/var/local/kmc/bin/kpm
[ -x "$KPM" ] || KPM=/var/local/kmc/kindlehf/bin/kpm
[ -x "$KPM" ] || KPM=/var/local/kmc/kindlepw2/bin/kpm
[ -x "$KPM" ] || exit 1
LOG="$ROOT/documents/GhostGuard_Installer.log"
TMP="$ROOT/.dcpro_ghostguard"
FONT_SCALE=3
GG_REPO_ID=dochoithuvi-ghostguard
GG_REPO=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.v2.json
GG_EXPECT=0.6.14
GG_BRIDGE_URL=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/source/payload/dcghostguardpro.koplugin/simpleui_bridge.lua
KMC_REPO_ID=kindlemodding
KMC_REPO=https://cdn.jsdelivr.net/gh/KindleModding/repo@main/manifest.v2.json
KO_VER=2026.07
mkdir -p "$TMP" 2>/dev/null
: > "$LOG" 2>/dev/null
log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null; }
FBINK="$(command -v fbink 2>/dev/null || true)"
[ -n "$FBINK" ] || for x in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink; do [ -x "$x" ] && FBINK="$x" && break; done
say(){ [ -n "$FBINK" ] && "$FBINK" -S "$FONT_SCALE" -x 1 -y "$1" -r "$2" >/dev/null 2>&1 || true; }
run(){ log "> $*"; "$@" >> "$LOG" 2>&1; RC=$?; log "< rc=$RC"; return $RC; }
kpm_list(){ "$KPM" -y list-repo 2>&1; }
get(){ U="$1"; O="$2"; rm -f "$O" 2>/dev/null; if command -v curl >/dev/null 2>&1; then curl -L --fail --silent --show-error "$U" -o "$O"; else wget -q -O "$O" "$U"; fi; }
has_ko(){ [ -x "$ROOT/extensions/koreader/bin/koreader.sh" ] || [ -x "$ROOT/koreader/koreader.sh" ]; }
ko_target(){ case "$KPM" in */kindlehf/bin/kpm) echo kindlehf;; */kindlepw2/bin/kpm) echo kindlepw2;; *) [ -d /var/local/kmc/kindle5 ] && echo kindle5 || echo kindle;; esac; }
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
  say 3 "KOReader: tai goi chinh thuc..."; log "Direct KOReader: $U"; rm -rf "$D" "$Z"; mkdir -p "$D" || return 1
  get "$U" "$Z" || return 1; command -v unzip >/dev/null 2>&1 || return 1; unzip -q "$Z" -d "$D" >/dev/null 2>&1 || return 1
  S=""; for d in "$D" "$D"/*; do if [ -x "$d/koreader/koreader.sh" ] || [ -x "$d/extensions/koreader/bin/koreader.sh" ]; then S="$d"; break; fi; done
  [ -n "$S" ] || return 1
  [ -d "$S/koreader" ] && { rm -rf "$ROOT/koreader"; cp -R "$S/koreader" "$ROOT/koreader" || return 1; }
  [ -d "$S/extensions/koreader" ] && { mkdir -p "$ROOT/extensions"; rm -rf "$ROOT/extensions/koreader"; cp -R "$S/extensions/koreader" "$ROOT/extensions/koreader" || return 1; }
  rm -rf "$D" "$Z"; has_ko
}
install_ko(){
  has_ko && { log "KOReader already installed."; return 0; }
  say 2 "[1/7] Cai KOReader..."
  R="$(kpm_list || true)"; printf '%s\n' "$R" >> "$LOG"
  printf '%s\n' "$R" | grep -q "$KMC_REPO_ID" || run "$KPM" -y add-repo "$KMC_REPO"
  run "$KPM" -y update || true
  run "$KPM" -y install koreader && has_ko && { log "KOReader installed by KPM."; return 0; }
  log "KPM KOReader install failed; using official release ZIP."
  install_ko_direct
}
install_simpleui(){
  if [ -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ] || [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ] || [ -f "$ROOT/extensions/koreader/plugins/zen_ui.koplugin/main.lua" ] || [ -f "$ROOT/extensions/koreader/plugins/simpleui.koplugin/main.lua" ]; then return 0; fi
  Z="$TMP/simpleui.zip"; D="$TMP/simpleui_unpack"; U=https://codeload.github.com/doctorhetfield-cmd/simpleui.koplugin/zip/refs/heads/main
  say 3 "[2/7] Cai SimpleUI..."; rm -rf "$D" "$Z"; mkdir -p "$D"; get "$U" "$Z" || return 1; command -v unzip >/dev/null 2>&1 || return 1; unzip -q "$Z" -d "$D" >/dev/null 2>&1 || return 1
  S=""; for d in "$D"/simpleui.koplugin "$D"/simpleui.koplugin-*; do [ -f "$d/main.lua" ] && S="$d" && break; done
  [ -n "$S" ] || return 1
  KO_ROOT=""
  for b in "$ROOT/koreader" "$ROOT/extensions/koreader"; do [ -d "$b/plugins" ] && { KO_ROOT="$b"; break; }; done
  [ -n "$KO_ROOT" ] || return 1
  mkdir -p "$KO_ROOT/plugins"; rm -rf "$KO_ROOT/plugins/simpleui.koplugin"; cp -R "$S" "$KO_ROOT/plugins/simpleui.koplugin"; rm -rf "$D" "$Z"; return 0
}
manifest_check(){
  M="$TMP/ghostguard_manifest.v2.json"; MC="$TMP/ghostguard_manifest.compact.json"; rm -f "$M" "$MC"; log "Checking manifest: $GG_REPO"; get "$GG_REPO" "$M" || { log "ERROR: manifest download failed"; return 1; }
  grep -q '"manifest_version"[[:space:]]*:[[:space:]]*2' "$M" || { log "ERROR: manifest is not v2"; return 1; }
  grep -q '"id"[[:space:]]*:[[:space:]]*"'$GG_REPO_ID'"' "$M" || { log "ERROR: manifest repo id mismatch"; return 1; }
  tr -d '[:space:]' < "$M" > "$MC" || { log "ERROR: cannot normalize manifest"; return 1; }
  grep -Fq '"ghostguard":{' "$MC" || { log "ERROR: ghostguard package missing"; return 1; }
  grep -Fq '"url":"packages/ghostguard/artifacts/ghostguard_0.6.14_kindle5-kindlepw2-kindlehf.kpkg"' "$MC" || { log "ERROR: GhostGuard 0.6.14 artifact missing"; return 1; }
  grep -Fq '"version":[0,6,14]' "$MC" || { log "ERROR: expected GhostGuard 0.6.14 not present"; return 1; }
  log "Manifest validation: PASS (GhostGuard $GG_EXPECT)"; rm -f "$M" "$MC"; return 0
}
search_gg(){ "$KPM" -y search ghostguard 2>&1; }
repo_ready(){
  R="$(search_gg || true)"; printf '%s\n' "$R" >> "$LOG"; printf '%s\n' "$R" | grep -q '0\.6\.14'
}
repair_gg(){
  say 6 "Lam moi GhostGuard repo..."
  manifest_check || return 1
  R="$(kpm_list || true)"; printf '%s\n' "$R" >> "$LOG"
  if repo_ready; then log "GhostGuard repository already exposes $GG_EXPECT; no re-registration needed."; return 0; fi
  log "GhostGuard $GG_EXPECT not visible; migrating repository once."
  run "$KPM" -y remove-repo "$GG_REPO_ID" || log "remove-repo returned non-zero (repo may not exist)."
  run "$KPM" -y add-repo "$GG_REPO" || return 1
  run "$KPM" -y update || return 1
  repo_ready || { log "ERROR: GhostGuard $GG_EXPECT not visible after repo refresh"; return 1; }
  log "GhostGuard v2 repo refresh complete."
}
log "========================================"; log "DCPRO GhostGuard OneClick v12.0"; log "Target: GitHub Raw manifest.v2.json"; log "Expected: GhostGuard $GG_EXPECT + latest SimpleUI Tools bridge"; log "Date: $(date)"; log "KPM=$KPM"; log "========================================"
say 1 "DCPRO GhostGuard Installer v12.0"; say 2 "GitHub KPM v2 + SimpleUI Tools fix"
install_ko || { log "ERROR: KOReader install failed"; say 5 "LOI: Khong cai duoc KOReader"; exit 1; }
say 4 "KOReader... OK"
install_simpleui || log "SimpleUI skipped; native/ZenUI may be used."
say 5 "Kiem tra GhostGuard 0.6.14..."
repair_gg || { log "ERROR: GhostGuard repo setup failed"; say 6 "LOI: Khong lam moi duoc repo"; exit 1; }
say 7 "Cai/cap nhat GhostGuard 0.6.14..."
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
  say 8 "LOI: Cai GhostGuard that bai"
  exit 1
fi
[ "$INSTALL_OK" -eq 1 ] && log "GhostGuard install command completed." || log "Using existing GhostGuard runtime; applying latest bridge hotfix."
say 8 "Dong bo SimpleUI Tools bridge..."
sync_simpleui_bridge || { log "ERROR: SimpleUI Tools bridge sync failed"; say 9 "LOI: SimpleUI Tools bridge"; exit 1; }
say 9 "GhostGuard + Tools... OK"
run "$KPM" -y launch ghostguard || log "Launch returned non-zero; installation remains complete. Restart KOReader manually."
log "Bootstrap complete. Registry endpoint: $GG_REPO"
log "SimpleUI bridge endpoint: $GG_BRIDGE_URL"
say 10 "HOAN TAT! RESTART KOREADER"
exit 0
