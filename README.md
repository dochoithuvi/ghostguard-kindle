# DCPRO GhostGuard for Kindle

Public KPM repository for **DCPRO GhostGuard**, a KOReader touch-protection plugin for jailbroken Kindle devices.

## Package ID

```text
ghostguard
```

## Install

Once this repository has been added to KPM, install with:

```text
;kpm install ghostguard
```

KPM refreshes package indexes automatically when `install` is run.

### First-time custom repository setup

A stock KPM installation only knows repositories already registered in its database. To use this GitHub-hosted repository directly, add its raw `manifest.json` URL once, then install:

```text
;kpm add-repo https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/manifest.json
;kpm update
;kpm install ghostguard
```

After that first registration, future installs/upgrades can use the normal package ID.

## License v4

GhostGuard v4 uses a per-device RSA-signed `license.key`.

- The public package contains only the RSA public key used for verification.
- The private signing key is **not** part of this repository or `.kpkg`.
- An invalid, missing, mismatched, or expired license must fail open and disable GhostGuard protection rather than break KOReader input.
- STOP / SAFE_MODE remain available for recovery.

## Package layout

```text
manifest.json
packages/ghostguard/artifacts/ghostguard_0.5.1_kindle5-kindlepw2-kindlehf.kpkg
packages/ghostguard/source/
docs/
```

## Current release

`0.5.1` — public v4 RC package based on the Kindle HF3/ExitTrace branch with the v4 RSA license layer and KPM package ID `ghostguard`.

The signing key bundled in this RC is a **test/RC public key**. A production release should replace it with the public half of an offline-generated production keypair before issuing production licenses.
