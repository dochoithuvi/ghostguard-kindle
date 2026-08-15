from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "packages/ghostguard/source/payload/dcghostguardpro.koplugin"

def replace_once(path, old, new):
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 occurrence, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")

# 0.6.11 diagnostic build: keep the GhostGuard core/license/status UI,
# but remove every touch/input and UI-bridge integration. This isolates the
# KOReader document lifecycle from GhostGuard while preserving the core.
main = PLUGIN / "main.lua"
replace_once(
    main,
    '''    local SimpleUIBridge; SimpleUIBridge, err = load_local("simpleui_bridge.lua")
    if not SimpleUIBridge then return false, "simpleui_bridge.lua: " .. err end
    local ZenUIBridge; ZenUIBridge, err = load_local("zenui_bridge.lua")
    if not ZenUIBridge then return false, "zenui_bridge.lua: " .. err end
''',
    '''    -- 0.6.11 SAFE DIAGNOSTIC: deliberately do not load SimpleUI/ZenUI
    -- bridges. They are outside the diagnostic core and may register UI hooks.
''',
)
replace_once(
    main,
    '''    self.simpleui = SimpleUIBridge:new(self, plugin_dir)
    self.zenui = ZenUIBridge:new(self, plugin_dir)
''',
    '''    -- SAFE DIAGNOSTIC: no SimpleUI/ZenUI bridge instances.
    self.simpleui = nil
    self.zenui = nil
''',
)

ghost = PLUGIN / "ghostguard.lua"
replace_once(
    ghost,
    '''    local hook_ok, hook_err = self:ensureInputBridge()
    if not hook_ok then return false, hook_err end
''',
    '''    -- 0.6.11 SAFE DIAGNOSTIC: do not attach to Device.input at all.
    -- This intentionally disables touch observation/protection for the test.
    self.observer_enabled = false
    self.hook_installed = false
    self.input = nil
    self.bridge = nil
''',
)
replace_once(
    ghost,
    'version = "0.6.10-ko-reader-stability"',
    'version = "0.6.11-safe-diagnostic"',
) if 'version = "0.6.10-ko-reader-stability"' in (PLUGIN / "defaults.lua").read_text(encoding="utf-8") else None

# Version is stored in defaults.lua, not ghostguard.lua.
defaults = PLUGIN / "defaults.lua"
text = defaults.read_text(encoding="utf-8")
if 'version = "0.6.10-ko-reader-stability"' not in text:
    raise SystemExit("defaults.lua: expected 0.6.10 version string not found")
defaults.write_text(text.replace('version = "0.6.10-ko-reader-stability"', 'version = "0.6.11-safe-diagnostic"'), encoding="utf-8")

manifest = ROOT / "packages/ghostguard/source/manifest.json"
text = manifest.read_text(encoding="utf-8")
text = text.replace('KOReader GhostGuard v0.6.10 - Adaptive touch profiles', 'KOReader GhostGuard v0.6.11 - SAFE diagnostic: core/license/status only')
text = text.replace('"version": [\n    0,\n    6,\n    10\n  ]', '"version": [\n    0,\n    6,\n    11\n  ]')
manifest.write_text(text, encoding="utf-8")
print("Applied GhostGuard 0.6.11 SAFE diagnostic build")
