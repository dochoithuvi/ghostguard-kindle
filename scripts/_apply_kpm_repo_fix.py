from pathlib import Path
import re

ONE = Path('DCPRO_GhostGuard_OneClick_Installer_v12.1.sh')
WF = Path('.github/workflows/build-artifact-v0612.yml')

s = ONE.read_text()

old_constants = '''GG_REPO_ID=dochoithuvi-ghostguard
GG_REPO=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.v2.json
GG_EXPECT=0.6.15
GG_ARTIFACT=packages/ghostguard/artifacts/ghostguard_0.6.15_kindle5-kindlepw2-kindlehf.kpkg
GG_BRIDGE_URL=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/source/payload/dcghostguardpro.koplugin/simpleui_bridge.lua
'''
new_constants = '''GG_REPO_ID=dochoithuvi-ghostguard
GG_REPO=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.v2.json
GG_REPO_MIRROR=https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/manifest.mirror.json
GG_EXPECT=0.6.15
GG_ARTIFACT=packages/ghostguard/artifacts/ghostguard_0.6.15_kindle5-kindlepw2-kindlehf.kpkg
GG_ARTIFACT_NAME=ghostguard_0.6.15_kindle5-kindlepw2-kindlehf.kpkg
GG_BRIDGE_URL=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/source/payload/dcghostguardpro.koplugin/simpleui_bridge.lua
GG_BRIDGE_MIRROR_URL=https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/source/payload/dcghostguardpro.koplugin/simpleui_bridge.lua
'''
if old_constants not in s:
    raise SystemExit('constants anchor missing')
s = s.replace(old_constants, new_constants, 1)

old_has = 'has_gg(){ T="$(gg_plugin_target 2>/dev/null || true)"; [ -n "$T" ] && [ -f "$T/simpleui_bridge.lua" ]; }\n'
new_has = old_has + 'has_gg_expected(){ T="$(gg_plugin_target 2>/dev/null || true)"; [ -n "$T" ] && grep -Fq "version = \\"$GG_EXPECT\\"" "$T/defaults.lua" 2>/dev/null; }\n'
if old_has not in s:
    raise SystemExit('has_gg anchor missing')
s = s.replace(old_has, new_has, 1)

old_sync = '''  B="$TMP/simpleui_bridge.lua"
  log "Syncing latest SimpleUI bridge: $GG_BRIDGE_URL"
  get "$GG_BRIDGE_URL" "$B" || { log "ERROR: SimpleUI bridge download failed"; return 1; }
'''
new_sync = '''  B="$TMP/simpleui_bridge.lua"
  log "Syncing latest SimpleUI bridge: $GG_BRIDGE_URL"
  if ! get "$GG_BRIDGE_URL" "$B"; then
    log "WARN: primary SimpleUI bridge download failed; trying jsDelivr mirror"
    get "$GG_BRIDGE_MIRROR_URL" "$B" || { log "ERROR: SimpleUI bridge download failed on primary and mirror"; return 1; }
  fi
'''
if old_sync not in s:
    raise SystemExit('bridge anchor missing')
s = s.replace(old_sync, new_sync, 1)

new_repo = r'''manifest_check_url(){
  URL="$1"
  M="$TMP/ghostguard_manifest.v2.json"
  MC="$TMP/ghostguard_manifest.compact.json"
  rm -f "$M" "$MC"
  log "Checking manifest: $URL"
  get "$URL" "$M" || { log "WARN: manifest download failed: $URL"; return 1; }
  grep -q '"manifest_version"[[:space:]]*:[[:space:]]*2' "$M" || { log "WARN: manifest is not v2: $URL"; return 1; }
  grep -q '"id"[[:space:]]*:[[:space:]]*"'$GG_REPO_ID'"' "$M" || { log "WARN: manifest repo id mismatch: $URL"; return 1; }
  tr -d '[:space:]' < "$M" > "$MC" || { log "WARN: cannot normalize manifest: $URL"; return 1; }
  grep -Fq '"ghostguard":{' "$MC" || { log "WARN: ghostguard package missing: $URL"; return 1; }
  grep -Fq "$GG_ARTIFACT_NAME" "$MC" || { log "WARN: GhostGuard $GG_EXPECT artifact missing: $URL"; return 1; }
  grep -Fq '"version":[0,6,15]' "$MC" || { log "WARN: expected GhostGuard $GG_EXPECT not present: $URL"; return 1; }
  log "Manifest validation: PASS (GhostGuard $GG_EXPECT via $URL)"
  rm -f "$M" "$MC"
  return 0
}

manifest_check(){
  GG_ACTIVE_REPO=""
  if manifest_check_url "$GG_REPO"; then
    GG_ACTIVE_REPO="$GG_REPO"
    return 0
  fi
  log "WARN: primary GhostGuard manifest unavailable; trying jsDelivr mirror"
  if manifest_check_url "$GG_REPO_MIRROR"; then
    GG_ACTIVE_REPO="$GG_REPO_MIRROR"
    return 0
  fi
  log "ERROR: GhostGuard manifest unavailable on primary and mirror"
  return 1
}

search_gg(){ "$KPM" -y search ghostguard 2>&1; }
repo_ready(){
  R="$(search_gg || true)"
  printf '%s\n' "$R" >> "$LOG"
  printf '%s\n' "$R" | grep -q -- '- ghostguard ('
}
registered_gg_endpoint(){
  R="$1"
  if printf '%s\n' "$R" | grep -Fq "$GG_REPO"; then
    printf '%s\n' "$GG_REPO"
    return 0
  fi
  if printf '%s\n' "$R" | grep -Fq "$GG_REPO_MIRROR"; then
    printf '%s\n' "$GG_REPO_MIRROR"
    return 0
  fi
  return 1
}
repo_registered_current(){ registered_gg_endpoint "$1" >/dev/null 2>&1; }
register_gg_repo(){
  URL="$1"
  log "Registering GhostGuard repository endpoint: $URL"
  run "$KPM" -y remove-repo "$GG_REPO_ID" || log "remove-repo returned non-zero (repo may not exist)."
  run "$KPM" -y add-repo "$URL" || return 1
  return 0
}
refresh_gg_index(){
  UPDATE_RC=0
  run "$KPM" -y update || UPDATE_RC=$?
  if repo_ready; then
    [ "$UPDATE_RC" -eq 0 ] || log "WARN: kpm update returned rc=$UPDATE_RC because another repository may have failed, but ghostguard is indexed; continuing."
    return 0
  fi
  [ "$UPDATE_RC" -eq 0 ] || log "WARN: kpm update returned rc=$UPDATE_RC and ghostguard is not visible yet."
  return 1
}

repair_gg(){
  say 6 "Lam moi GhostGuard repo..."
  manifest_check || return 1
  R="$(kpm_list || true)"
  printf '%s\n' "$R" >> "$LOG"
  CURRENT="$(registered_gg_endpoint "$R" 2>/dev/null || true)"
  if [ -z "$CURRENT" ]; then
    CURRENT="$GG_ACTIVE_REPO"
    log "GhostGuard repo is missing or legacy; registering validated endpoint."
    register_gg_repo "$CURRENT" || return 1
  fi
  if refresh_gg_index; then
    GG_ACTIVE_REPO="$CURRENT"
    log "GhostGuard repository exposes package ghostguard after refresh ($CURRENT)."
    return 0
  fi
  if [ "$CURRENT" = "$GG_REPO_MIRROR" ]; then FALLBACK="$GG_REPO"; else FALLBACK="$GG_REPO_MIRROR"; fi
  log "GhostGuard package not visible via current endpoint; trying fallback: $FALLBACK"
  manifest_check_url "$FALLBACK" || { log "ERROR: fallback GhostGuard manifest validation failed"; return 1; }
  register_gg_repo "$FALLBACK" || return 1
  refresh_gg_index || { log "ERROR: GhostGuard package not visible on primary or mirror"; return 1; }
  GG_ACTIVE_REPO="$FALLBACK"
  log "GhostGuard v2 repo refresh complete via fallback endpoint."
  return 0
}'''
pat = re.compile(r'manifest_check\(\)\{.*?\n\}\n\nmain\(\)\{', re.S)
m = pat.search(s)
if not m:
    raise SystemExit('repo repair block missing')
s = s[:m.start()] + new_repo + '\n\nmain(){' + s[m.end():]

install_pat = re.compile(r'''  INSTALL_OK=0\n  if run \"\$KPM\" -y install ghostguard; then.*?\n  \[ \"\$INSTALL_OK\" -eq 1 \] && log \"GhostGuard install command completed\.\" \|\| log \"Using existing GhostGuard runtime; applying latest bridge hotfix\.\"\n''', re.S)
new_install = '''  INSTALL_OK=0
  if run "$KPM" -y install ghostguard && has_gg_expected; then
    INSTALL_OK=1
  else
    log "GhostGuard install did not activate expected version $GG_EXPECT; repairing repository and retrying once."
    repair_gg || log "WARN: repository repair retry returned non-zero"
    if run "$KPM" -y install ghostguard && has_gg_expected; then INSTALL_OK=1; fi
  fi

  if [ "$INSTALL_OK" -ne 1 ]; then
    if has_gg; then log "ERROR: GhostGuard runtime exists but expected version $GG_EXPECT is not active."; else log "ERROR: GhostGuard install failed and no existing runtime was found."; fi
    say 9 "LOI: Cai GhostGuard $GG_EXPECT that bai"
    exit 1
  fi

  log "GhostGuard $GG_EXPECT install/verification completed."
'''
s, n = install_pat.subn(new_install, s, count=1)
if n != 1:
    raise SystemExit('install retry block missing')
ONE.write_text(s)

# Extend existing CI with static and behavioral regression checks.
t = WF.read_text()
marker = "          grep -q 'DCPRO_ONECLICK_LIB_ONLY' DCPRO_GhostGuard_OneClick_Installer_v12.1.sh\n"
if marker not in t:
    raise SystemExit('CI static anchor missing')
t = t.replace(marker, marker + "          grep -q 'GG_REPO_MIRROR=https://cdn.jsdelivr.net/' DCPRO_GhostGuard_OneClick_Installer_v12.1.sh\n          grep -q 'GG_BRIDGE_MIRROR_URL=https://cdn.jsdelivr.net/' DCPRO_GhostGuard_OneClick_Installer_v12.1.sh\n          grep -q 'refresh_gg_index' DCPRO_GhostGuard_OneClick_Installer_v12.1.sh\n          grep -q 'has_gg_expected' DCPRO_GhostGuard_OneClick_Installer_v12.1.sh\n", 1)

step_anchor = '      - name: Validate integrated KOReader safety guards\n'
repo_step = '''      - name: Validate KPM repository refresh fallback
        shell: bash
        run: |
          export DCPRO_ONECLICK_LIB_ONLY=1
          export DCPRO_ONECLICK_ROOT=/tmp/dcpro-repo-test
          export DCPRO_ONECLICK_LOG=/tmp/dcpro-repo-test.log
          export DCPRO_ONECLICK_TMP=/tmp/dcpro-repo-state
          . ./DCPRO_GhostGuard_OneClick_Installer_v12.1.sh
          manifest_check(){ GG_ACTIVE_REPO="$GG_REPO"; return 0; }
          manifest_check_url(){ return 0; }
          TEST_ENDPOINT="$GG_REPO"
          TEST_VISIBLE=1
          kpm_list(){ printf '  - %s - Test (%s)\\n' "$GG_REPO_ID" "$TEST_ENDPOINT"; }
          search_gg(){ if [ "$TEST_VISIBLE" = "1" ] || [ "$TEST_ENDPOINT" = "$GG_REPO_MIRROR" ]; then printf '  - ghostguard (DCPRO GhostGuard): test\\n'; else printf 'Found 0 package(s) for ghostguard:\\n'; fi; }
          run(){ case "${3:-}" in update) return 1 ;; remove-repo) return 0 ;; add-repo) TEST_ENDPOINT="$4"; return 0 ;; *) return 0 ;; esac; }
          repair_gg
          test "$TEST_ENDPOINT" = "$GG_REPO"
          TEST_VISIBLE=0
          TEST_ENDPOINT="$GG_REPO"
          repair_gg
          test "$TEST_ENDPOINT" = "$GG_REPO_MIRROR"

'''
if step_anchor not in t:
    raise SystemExit('CI step anchor missing')
t = t.replace(step_anchor, repo_step + step_anchor, 1)
WF.write_text(t)

# Remove temporary applicators from the final branch commit.
for tmp in [
    Path('scripts/_apply_kpm_repo_fix.py'),
    Path('.github/workflows/_apply-kpm-repo-fix-temp.yml'),
    Path('.github/workflows/_apply-kpm-repo-fix-pr.yml'),
]:
    if tmp.exists():
        tmp.unlink()
