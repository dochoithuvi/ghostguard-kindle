#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard/source"
OUT="$ROOT/packages/ghostguard/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.6.13
PKG="$OUT/ghostguard_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/payload" "$TMP/scriptlets" "$TMP/assets"
cp "$SRC/manifest.json" "$TMP/manifest.json"
cp -R "$SRC/payload/dcghostguardpro.koplugin" "$TMP/payload/"
# Repair legacy loader typo and restore the SimpleUI/ZenUI bridge instances.
# The bridge files are already shipped in the plugin; older source main.lua
# deliberately nulled them during the SAFE diagnostic build.
python3 - "$TMP/payload/dcghostguardpro.koplugin/main.lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("\nend    return true\nend\n", "\nend\n", 1)
old = '''    -- 0.6.11 SAFE DIAGNOSTIC: SimpleUI/ZenUI bridges intentionally disabled.\n    local ok, guard_or_err = pcall(GhostGuard.new, GhostGuard, config, Storage, TouchObserver,\n        ProfileManager, LicenseManager, CloudManager, plugin_dir)\n    if not ok then return false, "GhostGuard:new: " .. tostring(guard_or_err) end\n    self.config, self.guard = config, guard_or_err\n'''
new = '''    local ok, guard_or_err = pcall(GhostGuard.new, GhostGuard, config, Storage, TouchObserver,\n        ProfileManager, LicenseManager, CloudManager, plugin_dir)\n    if not ok then return false, "GhostGuard:new: " .. tostring(guard_or_err) end\n    self.config, self.guard = config, guard_or_err\n\n    -- SimpleUI and ZenUI integrations are optional UI bridges. Never fail\n    -- GhostGuard runtime if either host UI is absent or exposes an older API.\n    local SimpleUIBridge, bridge_err = load_local("simpleui_bridge.lua")\n    if SimpleUIBridge then\n        local bridge_ok, bridge_obj = pcall(SimpleUIBridge.new, SimpleUIBridge, self, plugin_dir)\n        if bridge_ok then\n            self.simpleui = bridge_obj\n        else\n            logger.warn("DCPRO GhostGuard SimpleUI bridge init failed:", bridge_obj)\n        end\n    else\n        logger.info("DCPRO GhostGuard SimpleUI bridge unavailable:", bridge_err)\n    end\n    local ZenUIBridge, zen_err = load_local("zenui_bridge.lua")\n    if ZenUIBridge then\n        local zen_ok, zen_obj = pcall(ZenUIBridge.new, ZenUIBridge, self, plugin_dir)\n        if zen_ok then\n            self.zenui = zen_obj\n        else\n            logger.warn("DCPRO GhostGuard ZenUI bridge init failed:", zen_obj)\n        end\n    else\n        logger.info("DCPRO GhostGuard ZenUI bridge unavailable:", zen_err)\n    end\n'''
if old not in s:
    raise SystemExit("expected SAFE diagnostic block not found")
s = s.replace(old, new, 1)
s = s.replace('    -- 0.6.11 SAFE DIAGNOSTIC: no SimpleUI/ZenUI bridge instances.\n    self.simpleui = nil\n    self.zenui = nil\n', '', 1)
open(p, "w", encoding="utf-8").write(s)
PY
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/scriptlets/DCPRO_GhostGuard.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
if [ -f "$SRC/assets/ghostguard_library_600x960.jpg" ]; then
  cp "$SRC/assets/ghostguard_library_600x960.jpg" "$TMP/assets/ghostguard_library_600x960.jpg"
fi
chmod +x "$TMP/install.sh" "$TMP/launch.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
for f in main.lua license_manager.lua keys/keyring.lua adaptive_bootstrap.lua simpleui_bridge.lua zenui_bridge.lua; do
  test -f "$TMP/payload/dcghostguardpro.koplugin/$f"
done
test -f "$TMP/manifest.json"
test -f "$TMP/scriptlets/DCPRO_GhostGuard.sh"
test -f "$TMP/assets/ghostguard_library_600x960.jpg"
! grep -q 'end    return true' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
# The shipped artifact must contain live bridge construction, not the old nil assignment.
grep -q 'SimpleUIBridge.new' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
! grep -q 'self.simpleui = nil' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh launch.sh scriptlets assets
printf '%s\n' "$PKG"
