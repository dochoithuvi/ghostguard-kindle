# DCPRO GhostGuard Native 0.2.2

GhostGuard Native is an isolated native-Kindle research package. It does not depend on KOReader and does not modify the stable GhostGuard KOReader package.

## v0.2 scope — Passive Watch

- discovers likely touchscreen controllers from `/proc/bus/input/devices` and `/sys/class/input/event*`
- selects a readable touchscreen candidate
- opens that `/dev/input/event*` node **read-only** for a short 12-second capture when the Native panel launches
- records raw evdev bytes as hex for device/controller analysis
- mirrors the latest metadata and watch snapshots into the Mesquite control panel
- capture exits automatically; there is no resident daemon
- installs a **DCPRO GhostGuard Native** launcher in the Kindle Library/Home so normal use no longer requires typing `;kpm launch ghostguard-native`
- reuses the existing GhostGuard Library artwork/icon already shipped by DCPRO

## 0.2.2 launcher compatibility

0.2.2 aligns the Mesquite `config.xml` capability envelope with the known-good KindleForge application layout. It also records Native-only launch diagnostics at:

`/mnt/us/.dcpro_ghostguard_native/launch.log`

The log records Library/KPM app-manager launch requests, Native runtime startup and the Mesquite exit code. This is specifically for diagnosing devices that briefly open the icon and then return to Home.

## Hard safety boundary

Version 0.2.2 does **not**:

- call `EVIOCGRAB`
- create or write to `/dev/uinput`
- inject synthetic input
- block, filter, suppress, or rewrite touches
- modify the Amazon reader input path
- modify KOReader, GhostGuard KOReader, or KindleForge

Amazon's original reader continues to receive the same touchscreen stream while the short passive watcher is active.

## Install / upgrade

Fresh install:

`;kpm install ghostguard-native`

Upgrade an existing Native installation:

`;kpm upgrade`

After installation, open **DCPRO GhostGuard Native** directly from the Kindle Library/Home. The command `;kpm launch ghostguard-native` remains available as a fallback/test path.

If a device returns immediately to Home, copy `/mnt/us/.dcpro_ghostguard_native/launch.log` for diagnosis.

## Test flow

1. Open **DCPRO GhostGuard Native** from the Kindle Library/Home.
2. While the panel is open, tap and swipe for about 12 seconds.
3. The panel refreshes the `Passive event watch` section automatically.
4. Inspect `EVENT`, `NAME`, `STATUS` and `[RAW_EVDEV_HEX]` to validate the controller path.

## Planned progression

1. v0.1 — metadata-only controller probe
2. **v0.2 — passive read-only event observation**
3. v0.3 — Controller Fingerprint + normalized touch stream
4. v0.4 — Auto Learn/profile generation
5. v0.5 — Shadow Protect (`WOULD_BLOCK`) without blocking input
6. v0.6+ — real filtering only after device testing proves a fail-safe interception/reinjection path
