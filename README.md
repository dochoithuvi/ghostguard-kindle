# DCPRO Kindle Tools Repository

Public KPM v2 repository for Kindle tools maintained by Do Choi Thu Vi.

## GhostGuard

- Package ID: `ghostguard`
- Current version: **`0.9.2`**
- Runtime: `mtguard5-adaptive-v3-stable`
- Artifact: `packages/ghostguard/artifacts/ghostguard_0.9.2_kindle5-kindlepw2-kindlehf.kpkg`

GhostGuard 0.9.2 promotes the field-tested MTGuard5 runtime: malformed-new-contact MT Guard, Adaptive Learning V3 with atomic automatic profile promotion, Auto Protect across normal restart/suspend/resume, local-only reports outside Kindle Library indexing, approved launcher cover, and a cleaned runtime with Cloud/ZenUI removed.

Reports:

```text
/mnt/us/GhostGuard_Reports/
```

Native filtering remains passive:

```text
NATIVE_FILTER=SHADOW_ONLY
INPUT_GRAB=OFF
EVENT_INJECTION=OFF
FAIL_OPEN=YES
```

## Recommended OneClick

```text
DCPRO_GhostGuard_OneClick_Installer_v14.sh
```

OneClick v14 uses the dedicated `bootstrap/koreader-simpleui-v14.sh` helper to install or verify KOReader + SimpleUI when needed, then downloads, verifies and installs GhostGuard 0.9.2.

Legacy OneClick v12.1/v13 installers have been removed from the public root. Current public installs should use v14.

## KPM repository

```text
https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.v2.json
```

Then:

```text
;kpm update
;kpm install ghostguard
;kpm upgrade
```

## KindleForge

- Package ID: `kindleforge`
- KPM integration revision: `4.1.1`
- Upstream UI: `4.1.0 stable`

## Release notes

See `packages/ghostguard/source/RELEASE_NOTES_0.9.2.md`.

## Backward compatibility

Older GhostGuard package artifacts remain available where they are still referenced by the public manifests for rollback/compatibility. Obsolete standalone OneClick installers are not kept in the public root.

## Public privacy boundary

The repository may contain public runtime/source, KPM artifacts, public verification keys, and hashed/signed license registries. It must not contain private signing keys, raw customer databases, customer license files, device reports, or private service tokens.
