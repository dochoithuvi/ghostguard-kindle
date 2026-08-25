from pathlib import Path

p = Path('DCPRO_GhostGuard_OneClick_Installer_v12.1.sh')
s = p.read_text(encoding='utf-8')

anchor = '''koreader_validate_lua_syntax(){\n  LUAJIT_BIN="$1"\n  LUA_FILE="$2"\n  LUA_EXPR="local f,e=loadfile([[$LUA_FILE]]); if not f then io.stderr:write((e or 'syntax error') .. '\\\\n'); os.exit(1) end"\n  if "$LUAJIT_BIN" -e "$LUA_EXPR" >> "$LOG" 2>&1; then\n    log "LuaJIT loadfile syntax validation: PASS ($LUA_FILE)"\n    return 0\n  fi\n  log "ERROR: LuaJIT loadfile syntax validation failed; original file left untouched ($LUA_FILE)"\n  return 1\n}\n'''
helper = anchor + '''\ncopy_backup_portable(){\n  SRC="$1"\n  DST="$2"\n\n  # /mnt/us is commonly FAT-backed on Kindle. BusyBox cp -p may copy the bytes\n  # successfully but still return non-zero when ownership/mode metadata cannot\n  # be preserved. The guard only needs a byte-for-byte restore point, so retry\n  # with a plain copy before treating the backup as a hard failure.\n  if cp -p "$SRC" "$DST" >> "$LOG" 2>&1; then\n    return 0\n  fi\n\n  log "WARN: metadata-preserving KOReader backup failed; retrying content-only copy ($DST)"\n  rm -f "$DST" 2>/dev/null || true\n  cp "$SRC" "$DST" >> "$LOG" 2>&1 || return 1\n\n  if command -v cmp >/dev/null 2>&1 && ! cmp -s "$SRC" "$DST"; then\n    log "ERROR: KOReader backup content verification failed ($DST)"\n    rm -f "$DST" 2>/dev/null || true\n    return 1\n  fi\n\n  log "Portable KOReader backup: PASS ($DST)"\n  return 0\n}\n\nlog_koreader_guard_context(){\n  log "KOReader safety guard failure context:"\n  log "ROOT=$ROOT"\n  command -v mount >/dev/null 2>&1 && mount 2>&1 | grep ' /mnt/us ' >> "$LOG" 2>&1 || true\n  for F in \\\n    "$ROOT/koreader/frontend/device/gesturedetector.lua" \\\n    "$ROOT/extensions/koreader/frontend/device/gesturedetector.lua" \\\n    "$ROOT/koreader/frontend/ui/widget/touchmenu.lua" \\\n    "$ROOT/extensions/koreader/frontend/ui/widget/touchmenu.lua"\n  do\n    [ -e "$F" ] || continue\n    ls -l "$F" >> "$LOG" 2>&1 || true\n  done\n}\n'''

if 'copy_backup_portable(){' not in s:
    if anchor not in s:
        raise SystemExit('syntax validation anchor not found')
    s = s.replace(anchor, helper, 1)

old_g = 'cp -p "$TARGET" "$BACKUP" || { log "ERROR: cannot create GestureGuard backup $BACKUP"; return 1; }'
new_g = 'copy_backup_portable "$TARGET" "$BACKUP" || { log "ERROR: cannot create GestureGuard backup $BACKUP"; return 1; }'
if old_g in s:
    s = s.replace(old_g, new_g, 1)
elif new_g not in s:
    raise SystemExit('GestureGuard backup anchor not found')

old_t = 'cp -p "$TARGET" "$BACKUP" || { log "ERROR: cannot create TouchMenuGuard backup $BACKUP"; return 1; }'
new_t = 'copy_backup_portable "$TARGET" "$BACKUP" || { log "ERROR: cannot create TouchMenuGuard backup $BACKUP"; return 1; }'
if old_t in s:
    s = s.replace(old_t, new_t, 1)
elif new_t not in s:
    raise SystemExit('TouchMenuGuard backup anchor not found')

old_fail = '''    *)\n      log "ERROR: KOReader safety guard patch failed; original target was preserved where validation failed."\n      say 6 "LOI: KOReader safety guard"\n      exit 1\n      ;;\n'''
new_fail = '''    *)\n      log "ERROR: KOReader safety guard patch failed; original target was preserved where validation failed."\n      log_koreader_guard_context\n      say 6 "LOI: KOReader safety guard"\n      exit 1\n      ;;\n'''
if old_fail in s:
    s = s.replace(old_fail, new_fail, 1)
elif 'log_koreader_guard_context' not in s.split('main(){', 1)[-1]:
    raise SystemExit('main failure anchor not found')

p.write_text(s, encoding='utf-8')

readme = Path('README.md')
r = readme.read_text(encoding='utf-8')
needle = 'The KOReader safety guards keep one-time backups beside the patched KOReader files and refuse to modify unknown code shapes. A real patch/compile failure is treated as an installer error; a future unknown KOReader code shape is skipped instead of being modified blindly.\n'
replacement = needle + '\nOn Kindle storage where metadata-preserving `cp -p` is rejected by the `/mnt/us` filesystem, OneClick retries the safety-guard backup as a verified content-only copy before failing. Guard failures also append filesystem/target context to `GhostGuard_Installer.log` for diagnosis.\n'
if 'metadata-preserving `cp -p`' not in r:
    if needle not in r:
        raise SystemExit('README OneClick anchor not found')
    r = r.replace(needle, replacement, 1)
    readme.write_text(r, encoding='utf-8')
