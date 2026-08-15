from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "packages/ghostguard/source/payload/dcghostguardpro.koplugin"


def replace_once(path, old, new):
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 occurrence, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")

# 1) Do not tear down a live bridge merely because KOReader reloads the
# plugin module. Reuse the existing GhostGuard owner instead.
replace_once(
    PLUGIN / "ghostguard.lua",
    '''    local existing_bridge = Device and Device.input and Device.input._dcpro_ghostguard_bridge\n    local existing_owner = existing_bridge and existing_bridge.owner\n    if existing_owner and type(existing_owner.stop) == "function" then\n        pcall(existing_owner.stop, existing_owner, "plugin-reload")\n    end\n''',
    '''    local existing_bridge = Device and Device.input and Device.input._dcpro_ghostguard_bridge\n    local existing_owner = existing_bridge and existing_bridge.owner\n    if existing_owner then\n        return existing_owner\n    end\n''',
)

# 2) Never stop the previous owner from the event-hook path. This is a
# fail-safe singleton handoff; the constructor above normally prevents it.
replace_once(
    PLUGIN / "ghostguard.lua",
    '''    elseif bridge.owner and bridge.owner ~= self then\n        pcall(bridge.owner.stop, bridge.owner, "replaced-by-new-instance")\n        bridge.owner = self\n    else\n''',
    '''    elseif bridge.owner and bridge.owner ~= self then\n        return false, "GhostGuard input bridge already owned by live runtime"\n    else\n''',
)

# 3) Never perform a forced online-license/network check from the raw touch
# event callback. A network timeout here blocks KOReader's input/UI path.
replace_once(
    PLUGIN / "ghostguard.lua",
    '        local licensed, detail = self:licenseValid(true)\n',
    '        local licensed, detail = self:licenseValid(false)\n',
)

# 4) Avoid reloading the whole runtime when the KOReader plugin instance is
# asked to load again during document/view transitions.
replace_once(
    PLUGIN / "main.lua",
    'function DCPROGhostGuard:loadRuntime()\n',
    'function DCPROGhostGuard:loadRuntime()\n    if self.guard then return true end\n',
)

# 5) Version the runtime and source manifest.
def bump_file(path, old, new):
    replace_once(path, old, new)

bump_file(PLUGIN / "defaults.lua", 'version = "0.6.9-kindle-adaptive-profiles"', 'version = "0.6.10-ko-reader-stability"')

manifest = PLUGIN / "../manifest.json"
# source manifest lives one directory above payload; normalize it explicitly
manifest = ROOT / "packages/ghostguard/source/manifest.json"
text = manifest.read_text(encoding="utf-8")
text = text.replace('KOReader GhostGuard v0.6.9 - Adaptive touch profiles', 'KOReader GhostGuard v0.6.10 - Adaptive touch profiles')
text = text.replace('"version": [\n    0,\n    6,\n    9\n  ]', '"version": [\n    0,\n    6,\n    10\n  ]')
manifest.write_text(text, encoding="utf-8")

print("Applied GhostGuard 0.6.10 KOReader stability hotfixes")
