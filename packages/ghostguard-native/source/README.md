# DCPRO GhostGuard Native 0.2.0

GhostGuard Native is an isolated native-Kindle research package. It does not depend on KOReader and does not modify the stable GhostGuard KOReader package.

## v0.2 scope — Passive Watch

- discovers likely touchscreen controllers from `/proc/bus/input/devices` and `/sys/class/input/event*`
- selects a readable touchscreen candidate
- opens that `/dev/input/event*` node **read-only** for a short 12-second capture when the Native panel launches
- records raw evdev bytes as hex for device/controller analysis
- mirrors the latest metadata and watch snapshots into the Mesquite control panel
- capture exits automatically; there is no resident daemon

## Hard safety boundary

Version 0.2.0 does **not**:

- call `EVIOCGRAB`
- create or write to `/dev/uinput`
- inject synthetic input
- block, filter, suppress, or rewrite touches
- modify the Amazon reader input path
- modify KOReader, GhostGuard KOReader, or KindleForge

Amazon's original reader continues to receive the same touchscreen stream while the short passive watcher is active.

## Test flow

1. Upgrade/install `ghostguard-native`.
2. Run `;kpm launch ghostguard-native`.
3. While the panel is open, tap, swipe and turn several pages for about 12 seconds.
4. The panel refreshes the `Passive event watch` section automatically.
5. Inspect `EVENT`, `NAME`, `STATUS` and `[RAW_EVDEV_HEX]` to validate the controller path.

## Planned progression

1. v0.1 — metadata-only controller probe
2. **v0.2 — passive read-only event observation**
3. v0.3 — Controller Fingerprint + normalized touch stream
4. v0.4 — Auto Learn/profile generation
5. v0.5 — Shadow Protect (`WOULD_BLOCK`) without blocking input
6. v0.6+ — real filtering only after device testing proves a fail-safe interception/reinjection path
