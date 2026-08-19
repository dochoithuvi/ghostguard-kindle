from pathlib import Path
import json

root = Path('.')
version = [0, 6, 16]
version_s = '0.6.16'
old_s = '0.6.15'
artifact = 'packages/ghostguard/artifacts/ghostguard_0.6.16_kindle5-kindlepw2-kindlehf.kpkg'

# Runtime/source text files.
for rel in [
    'DCPRO_GhostGuard_OneClick_Installer_v12.1.sh',
    'README.md',
    'packages/ghostguard/source/payload/dcghostguardpro.koplugin/defaults.lua',
    'packages/ghostguard/source/payload/dcghostguardpro.koplugin/_meta.lua',
    'scripts/build_artifact_v0612.sh',
    '.github/workflows/build-artifact-v0612.yml',
]:
    p = root / rel
    s = p.read_text()
    s = s.replace(old_s, version_s)
    s = s.replace('[0,6,15]', '[0,6,16]')
    s = s.replace('[0, 6, 15]', '[0, 6, 16]')
    s = s.replace(r'\[0, 6, 15\]', r'\[0, 6, 16\]')
    s = s.replace('PROFILE_LEARNING_0615_PASS', 'PROFILE_LEARNING_0616_PASS')
    p.write_text(s)

# Build script should also be able to normalize an older 0.6.15 source tree.
p = root / 'scripts/build_artifact_v0612.sh'
s = p.read_text()
s = s.replace("for old in ('0.6.13', '0.6.14'):", "for old in ('0.6.13', '0.6.14', '0.6.15'):", 1)
p.write_text(s)

# Package and repository manifests.
source_manifest = root / 'packages/ghostguard/source/manifest.json'
data = json.loads(source_manifest.read_text())
data['version'] = version
if 'description' in data:
    data['description'] = data['description'].replace(old_s, version_s)
source_manifest.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')

for rel in ['manifest.v2.json', 'manifest.json', 'manifest.mirror.json']:
    p = root / rel
    data = json.loads(p.read_text())
    pkg = data['packages']['ghostguard'] if 'packages' in data and 'ghostguard' in data['packages'] else None
    if pkg is not None:
        pkg['description'] = pkg.get('description', '').replace(old_s, version_s)
        pkg['artifacts'][0]['url'] = artifact
        pkg['artifacts'][0]['version'] = version
    else:
        if data.get('id') == 'ghostguard':
            data['version'] = version
            data['description'] = data.get('description', '').replace(old_s, version_s)
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')

# Safety assertions: release must retain the actual calibration fix.
def need(path, text):
    s = (root / path).read_text()
    if text not in s:
        raise SystemExit(f'missing {text!r} in {path}')

need('packages/ghostguard/source/payload/dcghostguardpro.koplugin/defaults.lua', 'version = "0.6.16"')
need('packages/ghostguard/source/payload/dcghostguardpro.koplugin/defaults.lua', 'runtime_revision = "calibration-flow-v2"')
need('packages/ghostguard/source/payload/dcghostguardpro.koplugin/ghostguard.lua', 'CALIBRATION_INPUT:')
need('packages/ghostguard/source/payload/dcghostguardpro.koplugin/main.lua', '_resume_calibration_after_suspend')
need('packages/ghostguard/source/payload/dcghostguardpro.koplugin/profile_manager.lua', 'function ProfileManager:checkpoint()')
need('DCPRO_GhostGuard_OneClick_Installer_v12.1.sh', 'GG_EXPECT=0.6.16')
need('DCPRO_GhostGuard_OneClick_Installer_v12.1.sh', 'GG_RUNTIME_REVISION=calibration-flow-v2')
need('DCPRO_GhostGuard_OneClick_Installer_v12.1.sh', 'ghostguard_0.6.16_kindle5-kindlepw2-kindlehf.kpkg')
need('.github/workflows/build-artifact-v0612.yml', 'ghostguard_0.6.16_kindle5-kindlepw2-kindlehf.kpkg')
need('.github/workflows/build-artifact-v0612.yml', r'"version": \[0, 6, 16\]')

print('RELEASE_0616_PREPARED')
