from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "packages/ghostguard/source/payload/dcghostguardpro.koplugin"

def replace_between(path, start_marker, end_marker, replacement):
    text = path.read_text(encoding="utf-8")
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0 or end <= start:
        raise SystemExit(f"{path}: markers not found")
    path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")

# Remove the external UI bridge loaders/constructors by marker boundaries.
main = PLUGIN / "main.lua"
replace_between(
    main,
    '    local SimpleUIBridge; SimpleUIBridge, err = load_local("simpleui_bridge.lua")',
    '    local ok, guard_or_err = pcall(GhostGuard.new',
    '    -- 0.6.11 SAFE DIAGNOSTIC: SimpleUI/ZenUI bridges intentionally disabled.\n',
)
replace_between(
    main,
    '    self.simpleui = SimpleUIBridge:new(self, plugin_dir)',
    '    return true\nend',
    '    -- 0.6.11 SAFE DIAGNOSTIC: no SimpleUI/ZenUI bridge instances.\n    self.simpleui = nil\n    self.zenui = nil\n    return true\nend',
)

ghost = PLUGIN / "ghostguard.lua"
replace_between(
    ghost,
    '    local hook_ok, hook_err = self:ensureInputBridge()',
    '    local protect = mode == self.config.protect_mode',
    '    -- 0.6.11 SAFE DIAGNOSTIC: do not attach to Device.input at all.\n'
    '    self.observer_enabled = false\n'
    '    self.hook_installed = false\n'
    '    self.input = nil\n'
    '    self.bridge = nil\n'
    '    local protect = mode == self.config.protect_mode',
)

defaults = PLUGIN / "defaults.lua"
text = defaults.read_text(encoding="utf-8")
text = re.sub(r'version\s*=\s*"0\.6\.10-ko-reader-stability"', 'version = "0.6.11-safe-diagnostic"', text, count=1)
if 'version = "0.6.11-safe-diagnostic"' not in text:
    raise SystemExit("defaults.lua: could not set 0.6.11 version")
defaults.write_text(text, encoding="utf-8")

manifest = ROOT / "packages/ghostguard/source/manifest.json"
text = manifest.read_text(encoding="utf-8")
text = text.replace('KOReader GhostGuard v0.6.10 - Adaptive touch profiles', 'KOReader GhostGuard v0.6.11 - SAFE diagnostic: core/license/status only')
text = re.sub(r'"version"\s*:\s*\[\s*0,\s*6,\s*10\s*\]', '"version": [\n    0,\n    6,\n    11\n  ]', text, count=1)
manifest.write_text(text, encoding="utf-8")

print("Applied GhostGuard 0.6.11 SAFE diagnostic build")
