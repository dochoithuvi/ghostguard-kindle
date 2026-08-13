#!/usr/bin/env python3
from __future__ import annotations
import json, pathlib, hashlib

ROOT = pathlib.Path('.').resolve()
SRC = ROOT / 'packages/ghostguard/source'
PLUGIN = SRC / 'payload/dcghostguardpro.koplugin'
MAIN = PLUGIN / 'main.lua'
MANIFEST = SRC / 'manifest.json'
SCRIPTLET = SRC / 'scriptlets/DCPRO_GhostGuard.sh'
META = PLUGIN / '_meta.lua'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f'missing patch marker: {label}')
    return text.replace(old, new, 1)


def main():
    for p in (MAIN, MANIFEST, SCRIPTLET, META, PLUGIN / 'zenui_bridge.lua'):
        if not p.exists():
            raise SystemExit(f'missing file: {p}')

    m = json.loads(MANIFEST.read_text(encoding='utf-8'))
    if m.get('version') not in ([0, 6, 4], [0, 6, 5]):
        raise SystemExit(f'unexpected source version: {m.get("version")}')

    text = MAIN.read_text(encoding='utf-8')

    text = replace_once(
        text,
        '    local SimpleUIBridge; SimpleUIBridge, err = load_local("simpleui_bridge.lua")\n'
        '    if not SimpleUIBridge then return false, "simpleui_bridge.lua: " .. err end\n',
        '    local SimpleUIBridge; SimpleUIBridge, err = load_local("simpleui_bridge.lua")\n'
        '    if not SimpleUIBridge then return false, "simpleui_bridge.lua: " .. err end\n'
        '    local ZenUIBridge; ZenUIBridge, err = load_local("zenui_bridge.lua")\n'
        '    if not ZenUIBridge then return false, "zenui_bridge.lua: " .. err end\n',
        'load ZenUIBridge',
    )

    text = replace_once(
        text,
        '    self.simpleui = SimpleUIBridge:new(self, plugin_dir)\n',
        '    self.simpleui = SimpleUIBridge:new(self, plugin_dir)\n'
        '    self.zenui = ZenUIBridge:new(self, plugin_dir)\n',
        'init ZenUIBridge',
    )

    text = replace_once(
        text,
        '    local extra = self.simpleui and ("\\nSimpleUI: " .. self.simpleui:statusText()) or ""\n'
        '    show(self.guard:statusText() .. extra, 18)\n',
        '    local extra = self.simpleui and ("\\nSimpleUI: " .. self.simpleui:statusText()) or ""\n'
        '    if self.zenui then extra = extra .. "\\nZenUI: " .. self.zenui:statusText() end\n'
        '    show(self.guard:statusText() .. extra, 18)\n',
        'status ZenUI',
    )

    text = replace_once(
        text,
        'function DCPROGhostGuard:registerSimpleUI(attempt)\n'
        '    if not self.simpleui or self.simpleui.registered then return end\n',
        'function DCPROGhostGuard:registerSimpleUI(attempt)\n'
        '    if type(rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")) == "function" then\n'
        '        logger.info("DCPRO GhostGuard: Zen UI active; SimpleUI bridge skipped")\n'
        '        return\n'
        '    end\n'
        '    if not self.simpleui or self.simpleui.registered then return end\n',
        'prefer ZenUI over SimpleUI',
    )

    text = replace_once(
        text,
        'function DCPROGhostGuard:unregisterSimpleUI()\n'
        '    if self.simpleui then self.simpleui:unregister() end\n'
        'end\n\n'
        'function DCPROGhostGuard:recordExitReason',
        'function DCPROGhostGuard:unregisterSimpleUI()\n'
        '    if self.simpleui then self.simpleui:unregister() end\n'
        'end\n\n'
        'function DCPROGhostGuard:registerZenUI(attempt)\n'
        '    if not self.zenui or self.zenui.registered then return end\n'
        '    attempt = attempt or 1\n'
        '    local ok, err = self.zenui:register()\n'
        '    if ok then return end\n'
        '    if attempt < 8 then\n'
        '        UIManager:scheduleIn(2, function() self:registerZenUI(attempt + 1) end)\n'
        '    else\n'
        '        logger.info("DCPRO GhostGuard ZenUI integration unavailable:", err)\n'
        '    end\n'
        'end\n\n'
        'function DCPROGhostGuard:unregisterZenUI()\n'
        '    if self.zenui then self.zenui:unregister() end\n'
        'end\n\n'
        'function DCPROGhostGuard:onZenUIReady()\n'
        '    self:unregisterSimpleUI()\n'
        '    self:registerZenUI(1)\n'
        'end\n\n'
        'function DCPROGhostGuard:recordExitReason',
        'ZenUI lifecycle methods',
    )

    text = replace_once(
        text,
        '        UIManager:scheduleIn(0.5, function() self:registerSimpleUI(1) end)\n',
        '        UIManager:scheduleIn(0.5, function() self:registerSimpleUI(1) end)\n'
        '        UIManager:scheduleIn(0.8, function() self:registerZenUI(1) end)\n',
        'startup ZenUI registration',
    )

    for marker in (
        '    self:unregisterSimpleUI()\n    if self.guard then self.guard:stop("poweroff") end',
        '    self:unregisterSimpleUI()\n    if self.guard then self.guard:stop("reboot") end',
        '    self:unregisterSimpleUI()\n    if self.guard then self.guard:stop("plugin-stop") end',
    ):
        if marker in text:
            text = text.replace(
                marker,
                marker.replace('    if self.guard', '    self:unregisterZenUI()\n    if self.guard'),
                1,
            )

    MAIN.write_text(text, encoding='utf-8', newline='\n')

    sl = SCRIPTLET.read_text(encoding='utf-8')
    old_icon = '# Icon: /mnt/us/dcpro/ghostguard/assets/ghostguard_library_600x960.jpg'
    new_icon = '# Icon: /mnt/us/koreader/plugins/dcghostguardpro.koplugin/assets/ghostguard.svg'
    if old_icon in sl:
        sl = sl.replace(old_icon, new_icon, 1)
    elif new_icon not in sl:
        raise RuntimeError('missing Library icon marker')
    SCRIPTLET.write_text(sl, encoding='utf-8', newline='\n')

    meta_text = META.read_text(encoding='utf-8')
    if 'GhostGuard v0.6.5 RC:' not in meta_text:
        lines = meta_text.splitlines()
        for i, line in enumerate(lines):
            if line.startswith('    description = _('):
                lines[i] = '    description = _("GhostGuard v0.6.5 RC: RSA v4.1 online activation, Native/SimpleUI/ZenUI bridges, KPM one-click workflow and fail-open touch protection."),'
                break
        meta_text = '\n'.join(lines) + '\n'
    META.write_text(meta_text, encoding='utf-8', newline='\n')

    m['description'] = 'KOReader GhostGuard v0.6.5 RC - Native/SimpleUI/ZenUI bridge support, Library icon fix and RSA v4.1 online activation.'
    m['version'] = [0, 6, 5]
    m['dependencies'] = []
    MANIFEST.write_text(json.dumps(m, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    checksum_file = SRC / 'checksums.sha256'
    rows = []
    for p in sorted(SRC.rglob('*')):
        if not p.is_file() or p == checksum_file:
            continue
        rel = './' + p.relative_to(SRC).as_posix()
        rows.append(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {rel}')
    checksum_file.write_text('\n'.join(rows) + '\n', encoding='utf-8')

    final = MAIN.read_text(encoding='utf-8')
    required = [
        'load_local("zenui_bridge.lua")',
        'function DCPROGhostGuard:onZenUIReady()',
        'self:unregisterSimpleUI()\n    self:registerZenUI(1)',
        'UIManager:scheduleIn(0.8, function() self:registerZenUI(1) end)',
    ]
    for needle in required:
        if needle not in final:
            raise RuntimeError('validation missing: ' + needle)

    print('GhostGuard v0.6.5 source patch: PASS')

if __name__ == '__main__':
    main()
