from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "packages/ghostguard/source/payload/dcghostguardpro.koplugin"

def replace_once(path, pattern, replacement):
    text = path.read_text(encoding="utf-8")
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 regex match, found {count}")
    path.write_text(new, encoding="utf-8")

# 0.6.11 SAFE DIAGNOSTIC: isolate GhostGuard core/license/status from all
# KOReader touch/input and external UI bridge integration.
main = PLUGIN / "main.lua"
replace_once(
    main,
    r'\s*local SimpleUIBridge; SimpleUIBridge, err = load_local\("simpleui_bridge\\.lua"\).*?local ZenUIBridge; ZenUIBridge, err = load_local\("zenui_bridge\\.lua"\)\s*if not ZenUIBridge then return false, "zenui_bridge\\.lua: " \.\. err end\s*',
    '\n    -- SAFE DIAGNOSTIC: do not load SimpleUI/ZenUI bridges.\n',
)
replace_once(
    main,
    r'\s*self\.simpleui = SimpleUIBridge:new\(self, plugin_dir\)\s*self\.zenui = ZenUIBridge:new\(self, plugin_dir\)\s*',
    '\n    -- SAFE DIAGNOSTIC: no SimpleUI/ZenUI bridge instances.\n    self.simpleui = nil\n    self.zenui = nil\n',
)

ghost = PLUGIN / "ghostguard.lua"
# Works whether the previous stability hotfix is present or not.
replace_once(
    ghost,
    r'\s*local hook_ok, hook_err = self:ensureInputBridge\(\)\s*if not hook_ok then return false, hook_err end\s*',
    '\n    -- SAFE DIAGNOSTIC: do not attach to Device.input at all.\n    self.observer_enabled = false\n    self.hook_installed = false\n    self.input = nil\n    self.bridge = nil\n',
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
