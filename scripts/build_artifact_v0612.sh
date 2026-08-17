#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard/source"
OUT="$ROOT/packages/ghostguard/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.6.14
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
# 0.6.14 protect fix: the previous SAFE diagnostic reset self.input/self.bridge
# and then immediately called ensureProtectWrapper(), producing the exact
# "PROTECT_WRAPPER: input bridge unavailable" error seen on Kindle.
python3 - "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '''    -- 0.6.11 SAFE DIAGNOSTIC: do not attach to Device.input at all.\n    self.observer_enabled = false\n    self.hook_installed = false\n    self.input = nil\n    self.bridge = nil\n    local protect = mode == self.config.protect_mode    local protect = mode == self.config.protect_mode\n    local calibrate = mode == self.config.calibration_mode\n'''
new = '''    -- Observe/Calibration remain safe without a touch wrapper. Real Protect\n    -- mode, however, needs the raw-event bridge before installing the wrapper.\n    -- The old SAFE diagnostic cleared self.input/self.bridge and then called\n    -- ensureProtectWrapper(), which deterministically returned:\n    -- "PROTECT_WRAPPER: input bridge unavailable".\n    self.observer_enabled = false\n    self.hook_installed = false\n    self.input = nil\n    self.bridge = nil\n    local protect = mode == self.config.protect_mode\n    local calibrate = mode == self.config.calibration_mode\n'''
if old not in s:
    raise SystemExit("expected GhostGuard start preamble not found")
s = s.replace(old, new, 1)
old2 = '''    if protect or self.config.protect_wrapper_all_modes == true then\n        self.protect_enabled = protect\n        local wrapper_ok, wrapper_err = self:ensureProtectWrapper()\n        if not wrapper_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(wrapper_err)\n        end\n        self.wrapper_mode = protect and "PROTECT" or "PASS_THROUGH"\n    end\n'''
new2 = '''    if protect or self.config.protect_wrapper_all_modes == true then\n        local bridge_ok, bridge_err = self:ensureInputBridge()\n        if not bridge_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(bridge_err)\n        end\n        self.protect_enabled = protect\n        local wrapper_ok, wrapper_err = self:ensureProtectWrapper()\n        if not wrapper_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(wrapper_err)\n        end\n        self.wrapper_mode = protect and "PROTECT" or "PASS_THROUGH"\n    end\n'''
if old2 not in s:
    raise SystemExit("expected GhostGuard wrapper block not found")
s = s.replace(old2, new2, 1)
open(p, "w", encoding="utf-8").write(s)
PY
# Keep the package's internal version aligned with the repository manifest.
python3 - "$TMP/payload/dcghostguardpro.koplugin/defaults.lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('version = "0.6.13"', 'version = "0.6.14"', 1)
open(p, "w", encoding="utf-8").write(s)
PY
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/scriptlets/DCPRO_GhostGuard.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
if [ -f "$SRC/assets/ghostguard_library_600x960.jpg" ]; then
  cp "$SRC/assets/ghostguard_library_600x960.jpg" "$TMP/assets/ghostguard_library_600x960.jpg"
fi
chmod +x "$TMP/install.sh" "$TMP/launch.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
for f in main.lua ghostguard.lua defaults.lua license_manager.lua keys/keyring.lua adaptive_bootstrap.lua simpleui_bridge.lua zenui_bridge.lua; do
  test -f "$TMP/payload/dcghostguardpro.koplugin/$f"
done
test -f "$TMP/manifest.json"
test -f "$TMP/scriptlets/DCPRO_GhostGuard.sh"
test -f "$TMP/assets/ghostguard_library_600x960.jpg"
! grep -q 'end    return true' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
grep -q 'SimpleUIBridge.new' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
! grep -q 'self.simpleui = nil' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
grep -q 'local bridge_ok, bridge_err = self:ensureInputBridge()' "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua"
! grep -q 'local protect = mode == self.config.protect_mode    local protect' "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua"
grep -q 'version = "0.6.14"' "$TMP/payload/dcghostguardpro.koplugin/defaults.lua"
tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh launch.sh scriptlets assets
# Sync the patched runtime/config back into the source tree for reproducibility.
cp "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua" "$SRC/payload/dcghostguardpro.koplugin/ghostguard.lua"
cp "$TMP/payload/dcghostguardpro.koplugin/defaults.lua" "$SRC/payload/dcghostguardpro.koplugin/defaults.lua"
printf '%s\n' "$PKG"
