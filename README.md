# DCPRO Kindle Tools Repository

Public KPM v2 repository for Kindle tools maintained by Do Choi Thu Vi.

## Current packages

### GhostGuard

- Package ID: `ghostguard`
- Current version: `0.6.14`
- KOReader touch-protection plugin.
- Current artifact: `packages/ghostguard/artifacts/ghostguard_0.6.14_kindle5-kindlepw2-kindlehf.kpkg`

### KindleForge

- Package ID: `kindleforge`
- KPM integration revision: `4.1.1`
- Upstream KindleForge UI: `4.1.0 stable`
- Current artifact: `packages/kindleforge/artifacts/kindleforge_4.1.1_kindle5-kindlepw2-kindlehf.kpkg`

## Recommended GhostGuard OneClick

Use only:

```text
DCPRO_GhostGuard_OneClick_Installer_v12.1.sh
```

`v12.1` is self-contained. It:

1. Finds the installed KPM binary.
2. Installs/checks KOReader.
3. Attempts to install SimpleUI when missing.
4. Validates the current multi-package repository manifest.
5. Re-registers the repository only when the configured endpoint is missing/legacy.
6. Runs `kpm update` and verifies package `ghostguard` is indexed.
7. Installs GhostGuard `0.6.14`.
8. Syncs the latest compatible `simpleui_bridge.lua`.
9. Launches GhostGuard.

Installer log:

```text
/mnt/us/documents/GhostGuard_Installer.log
```

## KPM repository

Current KPM v2 manifest:

```text
https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.v2.json
```

Once the repository has been registered, packages can be managed directly:

```text
;kpm update
;kpm install ghostguard
;kpm install kindleforge
;kpm upgrade
```

## Backward compatibility

The following GhostGuard-only endpoints are intentionally retained for older devices/scripts and should not be used for new multi-package setup:

```text
manifest.json
manifest.mirror.json
bootstrap/DCPRO_GhostGuard_OneClick_Installer.sh
```

Do not delete or repoint these compatibility endpoints without a migration plan for existing devices.

## Repository layout

```text
manifest.v2.json
DCPRO_GhostGuard_OneClick_Installer_v12.1.sh
packages/
  ghostguard/
    source/
    artifacts/
  kindleforge/
    source/
    artifacts/
scripts/
.github/workflows/
```

## Public privacy boundary

This repository may contain public runtime/source, KPM artifacts, public verification keys, and hashed/signed license registries. It must not contain private signing keys, raw customer databases, customer license files, or private service tokens.
