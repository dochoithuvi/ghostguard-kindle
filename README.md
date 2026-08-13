# DCPRO GhostGuard for Kindle

Public KPM repository for **DCPRO GhostGuard**, a KOReader touch-protection plugin for jailbroken Kindle devices.

## Current release

**0.6.0 RC — License Sync**

This release is based on the v0.5.1 HF3/ExitTrace runtime and adds the v4.1 hybrid licensing layer. It does **not** claim that the later Adaptive/TouchMap branch has been merged yet.

## Package ID

```text
ghostguard
```

## Install

If this repository is already registered in KPM:

```text
;kpm install ghostguard
```

First-time setup can use the short repository URL:

```text
;kpm add-repo https://bit.ly/ghostguard
;kpm install ghostguard
```

The direct manifest URL remains:

```text
https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.json
```

## One-click Library bootstrap

`bootstrap/DCPRO_GhostGuard_OneClick_Installer.sh` is a small bootstrap launcher intended for KMC shell integration.

Prerequisites:
- KOReader already installed.
- KPM/KMC already installed.
- Network access for first install/update.

The bootstrap finds the KPM binary, registers `https://bit.ly/ghostguard`, installs/updates package `ghostguard`, writes a `LAUNCH_ONCE` request, and opens KOReader.

This bootstrap is still an RC path and requires physical Kindle testing before being treated as production.

## License v4.1

GhostGuard v4.1 supports two signed authorization paths:

1. A local per-device RSA-signed `license.key`.
2. A signed online registry at `licenses/licenses.json` + `licenses/licenses.sig`.

Online registry properties:
- Kindle serials are normalized and SHA-256 hashed before lookup.
- The public registry contains no raw serial field and no customer-name field.
- Registry bytes are signed with RSA-SHA256 and verified with the public key already shipped in GhostGuard.
- Active signed registry cache can authorize offline for the configured grace period.
- A valid local RSA v4 license remains an offline fallback.
- Explicit signed `revoked`, `paused`, or expired online state can deny Protect.
- Network failure or crypto/runtime error fails open: GhostGuard must not interfere with touch input.
- STOP and SAFE_MODE remain available independently of license validity.

The private signing key is **never** included in this repository, `.kpkg`, registry, or Kindle payload.

## Public privacy boundary

This repository may contain:
- GhostGuard public runtime/source.
- KPM artifacts.
- RSA public verification key.
- Hashed signed license registry.

It must not contain:
- Private RSA signing keys.
- Customer license-manager HTML containing private material.
- Raw customer database exports.
- Customer `license.key` files.
- Private Cloud tokens.

## Package layout

```text
manifest.json
licenses/licenses.json
licenses/licenses.sig
bootstrap/DCPRO_GhostGuard_OneClick_Installer.sh
packages/ghostguard/artifacts/ghostguard_0.6.0_kindle5-kindlepw2-kindlehf.kpkg
packages/ghostguard/source/
```

## RC warning

The signing key currently referenced by this RC is the **test/RC key** `ghostguard-rc-2026-08`. Before a production customer rollout, generate and keep a production RSA private key offline, add only its public PEM/key ID to the package, and re-sign the registry with that production key.
