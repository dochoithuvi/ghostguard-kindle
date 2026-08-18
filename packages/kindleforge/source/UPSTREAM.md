# KindleForge KPM repack

This package adds KindleForge to the same KPM repository as GhostGuard without modifying GhostGuard itself.

Upstream project: `KindleTweaks/KindleForge`

Application ID: `xyz.penguins184.kindleforge`

Upstream displayed version: `4.1.0 stable`

KPM package revision: `4.1.1`

## Upstream payload

The artifact builder downloads the official upstream release asset directly from:

`https://github.com/KindleTweaks/KindleForge/releases/download/v4.1.0/KindleForge.zip`

This intentionally mirrors KindleForge's own `Update KForge` strategy instead of rebuilding the application bundle from individual Git blobs. The build validates the App ID, displayed upstream version, updater menu entry, KFPM path, and both hard-float/soft-float Utild binaries before publishing the `.kpkg`.

The SHA-256 of the exact release ZIP used for each artifact is stored inside the package as `UPSTREAM_RELEASE_SHA256`.

## KPM integration revision 4.1.1

The first KPM repack isolated Utild inside `/var/local/mesquite/KindleForge`. Upstream KindleForge expects the ABI-selected Utild service under `/var/local/kmc`, and its troubleshooting documentation specifically points users with ABI-loading failures to `Update KForge`.

Revision 4.1.1 therefore follows upstream behavior more closely while keeping GhostGuard isolated:

- installs the official release bundle to `/mnt/us/documents/KindleForge`;
- mirrors the active WAF to `/var/local/mesquite/KindleForge`;
- selects `UtildHF` when `/lib/ld-linux-armhf.so.3` exists, otherwise `UtildSF`;
- copies only the selected Utild binary to `/var/local/kmc` and starts it;
- registers `xyz.penguins184.kindleforge` through a KPM runtime wrapper;
- before each app launch, the wrapper syncs `/mnt/us/documents/KindleForge` back to the Mesquite target, so a bundle downloaded by `Update KForge` is applied automatically on the next launch;
- keeps `/mnt/us/.KFPM` and shared Utild binaries on uninstall to avoid damaging packages or other Kindle apps.

GhostGuard source, GhostGuard artifacts, KOReader, SimpleUI, and `DCPRO_GhostGuard_OneClick_Installer_v12.sh` are not part of this package.
