from pathlib import Path

p = Path('DCPRO_GhostGuard_OneClick_Installer_v12.1.sh')
s = p.read_text(encoding='utf-8')
repls = [
    ('# Self-contained production bootstrap for KPM v0.2.x.', '# Self-contained production bootstrap for KPM v0.1.x/v0.2.x.'),
    ('# fail-safes, optionally installs SimpleUI, refreshes the current multi-package', '# fail-safes, optionally installs SimpleUI, refreshes the GhostGuard compatibility'),
    ('# KPM repository, installs GhostGuard 0.6.17, syncs the latest SimpleUI Tools', '# KPM repository, installs GhostGuard 0.6.17, syncs the latest SimpleUI Tools'),
    ('GG_REPO=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.v2.json', 'GG_REPO=https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.json'),
    ('KMC_REPO=https://cdn.jsdelivr.net/gh/KindleModding/repo@main/manifest.v2.json', 'KMC_REPO=https://cdn.jsdelivr.net/gh/KindleModding/repo@main/manifest.json'),
    ('M="$TMP/ghostguard_manifest.v2.json"', 'M="$TMP/ghostguard_manifest.json"'),
    ('grep -q \'"manifest_version"[[:space:]]*:[[:space:]]*2\' "$M" || { log "WARN: manifest is not v2: $URL"; return 1; }', 'grep -q \'"manifest_version"[[:space:]]*:[[:space:]]*1\' "$M" || { log "WARN: manifest is not KPM v1-compatible: $URL"; return 1; }'),
    ('log "GhostGuard v2 repo refresh complete via fallback endpoint."', 'log "GhostGuard compatibility repo refresh complete via fallback endpoint."'),
    ('log "Target: GitHub Raw manifest.v2.json"', 'log "Target: GitHub Raw manifest.json (KPM v1 compatibility; manifest.v2.json remains available for newer KPM)"'),
    ('say 2 "KPM v2 + KOReader safety guards"', 'say 2 "KPM v1/v2 + KOReader safety guards"'),
]
for old, new in repls:
    if old not in s:
        raise SystemExit(f'anchor not found: {old}')
    s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')

for name in ('manifest.json', 'manifest.mirror.json'):
    q = Path(name)
    t = q.read_text(encoding='utf-8')
    old = '"manifest_version": 2'
    if old not in t:
        raise SystemExit(f'{name}: manifest v2 anchor missing')
    q.write_text(t.replace(old, '"manifest_version": 1', 1), encoding='utf-8')
