#!/bin/sh
# DCPRO GhostGuard OneClick v11.4
# Touch-broken Kindle bootstrap: KOReader first, then SimpleUI, then GhostGuard.
# KPM v0.2.x: use the v2 repository manifest explicitly.
# v11.4: GhostGuard 0.6.12; fixes KOReader plugin loader syntax issue and verifies the new package.
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
GG_EXPECT=0.6.12
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
  say 2 "[1/6] Cai KOReader..."
  R="$(kpm_list || true)"; printf '%s\n' "$R" >> "$LOG"
  printf '%s\n' "$R" | grep -q "$KMC_REPO_ID" || run "$KPM" -y add-repo "$KMC_REPO"
  run "$KPM" -y update || true
  run "$KPM" -y install koreader && has_ko && { log "KOReader installed by KPM."; return 0; }
  log "KPM KOReader install failed; using official release ZIP."
  install_ko_direct
}
install_simpleui(){
  if [ -f "$ROOT/koreader/plugins/zen_ui.koplugin/main.lua" ] || [ -f "$ROOT/koreader/plugins/simpleui.koplugin/main.lua" ]; then return 0; fi
  Z="$TMP/simpleui.zip"; D="$TMP/simpleui_unpack"; U=https://codeload.github.com/doctorhetfield-cmd/simpleui.koplugin/zip/refs/heads/main
  say 3 "[2/6] Cai SimpleUI..."; rm -rf "$D" "$Z"; mkdir -p "$D"; get "$U" "$Z" || return 1; command -v unzip >/dev/null 2>&1 || return 1; unzip -q "$Z" -d "$D" >/dev/null 2>&1 || return 1
  S=""; for d in "$D"/simpleui.koplugin "$D"/simpleui.koplugin-*; do [ -f "$d/main.lua" ] && S="$d" && break; done
  [ -n "$S" ] || return 1; mkdir -p "$ROOT/koreader/plugins"; rm -rf "$ROOT/koreader/plugins/simpleui.koplugin"; cp -R "$S" "$ROOT/koreader/plugins/simpleui.koplugin"; rm -rf "$D" "$Z"; return 0
}
manifest_check(){
  M="$TMP/ghostguard_manifest.v2.json"; rm -f "$M"; log "Checking manifest: $GG_REPO"; get "$GG_REPO" "$M" || { log "ERROR: manifest download failed"; return 1; }
  grep -q '"manifest_version"[[:space:]]*:[[:space:]]*2' "$M" || { log "ERROR: manifest is not v2"; return 1; }
  grep -q '"id"[[:space:]]*:[[:space:]]*"'$GG_REPO_ID'"' "$M" || { log "ERROR: manifest repo id mismatch"; return 1; }
  grep -q '"ghostguard"' "$M" || { log "ERROR: ghostguard package missing"; return 1; }
  grep -q '"version"[[:space:]]*:[[:space:]]*\[0,[[:space:]]*6,[[:space:]]*12\]' "$M" || { log "ERROR: expected GhostGuard 0.6.12 not present"; return 1; }
  log "Manifest validation: PASS (GhostGuard $GG_EXPECT)"; rm -f "$M"; return 0
}
search_gg(){ "$KPM" -y search ghostguard 2>&1; }
repo_ready(){
  R="$(search_gg || true)"; printf '%s\n' "$R" >> "$LOG"; printf '%s\n' "$R" | grep -q '0\.6\.12'
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
log "========================================"; log "DCPRO GhostGuard OneClick v11.4"; log "Target: GitHub Raw manifest.v2.json"; log "Expected: GhostGuard $GG_EXPECT"; log "Date: $(date)"; log "KPM=$KPM"; log "========================================"
say 1 "DCPRO GhostGuard Installer v11.4"; say 2 "GitHub KPM v2 registry"
install_ko || { log "ERROR: KOReader install failed"; say 5 "LOI: Khong cai duoc KOReader"; exit 1; }
say 4 "KOReader... OK"
install_simpleui || log "SimpleUI skipped; native/ZenUI may be used."
say 5 "Kiem tra GhostGuard 0.6.12..."
repair_gg || { log "ERROR: GhostGuard repo setup failed"; say 6 "LOI: Khong lam moi duoc repo"; exit 1; }
say 7 "Cai GhostGuard 0.6.12..."
if ! run "$KPM" -y install ghostguard; then
  log "First GhostGuard install failed; refreshing v2 repo and retrying once."
  run "$KPM" -y remove-repo "$GG_REPO_ID" || true
  run "$KPM" -y add-repo "$GG_REPO" || { say 8 "LOI: Repo GhostGuard"; exit 1; }
  run "$KPM" -y update || { say 8 "LOI: Update repo"; exit 1; }
  run "$KPM" -y install ghostguard || { say 8 "LOI: Cai GhostGuard that bai"; exit 1; }
fi
log "GhostGuard install command completed."
say 9 "GhostGuard... OK"
run "$KPM" -y launch ghostguard || log "Launch returned non-zero; installation remains complete."
log "Bootstrap complete. Registry endpoint: $GG_REPO"
say 10 "HOAN TAT!"
exit 0
