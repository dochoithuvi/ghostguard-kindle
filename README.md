# DCPRO Kindle Tools Repository

Public KPM v2 repository for Kindle tools maintained by Do Choi Thu Vi.

## Current packages

### GhostGuard

- Package ID: `ghostguard`
- Current version: `0.6.17`
- KOReader touch-protection plugin.
- Current artifact: `packages/ghostguard/artifacts/ghostguard_0.6.17_kindle5-kindlepw2-kindlehf.kpkg`
- Learning completion supports two safe outcomes:
  - `GHOST_CLUSTER`: repeated ghost evidence is strong enough to activate learned coordinate clusters.
  - `BASELINE`: normal usage has supplied enough completed contacts but no ghost cluster is yet trustworthy; Protect stays conservative and does not use weak coordinates as a blocking bonus.

### KindleForge

- Package ID: `kindleforge`
- KPM integration revision: `4.1.1`
- Upstream KindleForge UI: `4.1.0 stable`
- Current artifact: `packages/kindleforge/artifacts/kindleforge_4.1.1_kindle5-kindlepw2-kindlehf.kpkg`

## GhostGuard learning flow

GhostGuard `0.6.17` keeps the existing ghost-signature thresholds (`12` suspect contacts with a strongest cluster of at least `5`) and adds a healthy-device completion path. Calibration counts every completed contact and stores both the contact count and learning time cumulatively across clean learning sessions.

A profile becomes ready only after at least `180` seconds of cumulative learning time. At that point it completes as:

- `GHOST_CLUSTER` when the repeated ghost evidence reaches `12` suspect contacts and the strongest cluster reaches `5` samples; or
- `BASELINE` when at least `40` completed contacts have been observed without a sufficiently trustworthy ghost cluster.

Because readiness time and contact progress are stored in the pending profile, ending or restarting a clean learning session does not reset the learning progress. The ready popup follows this cumulative readiness directly and does not impose another per-session `180` second wait.

A `BASELINE` profile can be approved and used for Protect, but `ProfileManager:match()` deliberately returns no coordinate match for Baseline profiles. Generic abnormality, incomplete-position, extreme-edge, burst scoring, probation limits, fail-open behavior, and circuit breaker protection remain unchanged.

Profiles written by GhostGuard `<=0.6.14` without `PROFILE_KIND` or `LEARNING_SECONDS` remain readable. Existing READY legacy profiles keep their readiness, and approved legacy profiles with clusters are treated as `GHOST_CLUSTER` profiles.

## Recommended GhostGuard OneClick

Use only:

```text
DCPRO_GhostGuard_OneClick_Installer_v12.1.sh
```

`v12.1` is self-contained. It:

1. Finds the installed KPM binary.
2. Installs/checks KOReader.
3. Applies the tested KOReader `GestureGuard v1.1` fail-safe for malformed/out-of-order touch frames.
4. Applies the tested KOReader `TouchMenuGuard v1` fail-safe for uninitialized menu page state.
5. Attempts to install SimpleUI when missing.
6. Validates the current multi-package repository manifest.
7. Re-registers the repository only when the configured endpoint is missing/legacy.
8. Runs `kpm update` and verifies package `ghostguard` is indexed.
9. Installs GhostGuard `0.6.17`.
10. Syncs the latest compatible `simpleui_bridge.lua`.
11. Launches GhostGuard.

The KOReader safety guards keep one-time backups beside the patched KOReader files and refuse to modify unknown code shapes. A real patch/compile failure is treated as an installer error; a future unknown KOReader code shape is skipped instead of being modified blindly.

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

Standalone KOReader guard TEST/RESTORE launchers are intentionally not kept in the repository after production integration; their tested logic now lives directly in OneClick v12.1 and is validated by the main build workflow.

## Public privacy boundary

This repository may contain public runtime/source, KPM artifacts, public verification keys, and hashed/signed license registries. It must not contain private signing keys, raw customer databases, customer license files, or private service tokens.
