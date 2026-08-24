# DCPRO GhostGuard Native Probe 0.1.0

This package is the first isolated native-Kindle research build for GhostGuard.

## Scope

- installs as an independent KPM package: `ghostguard-native`
- registers its own Mesquite application ID: `com.dcpro.ghostguardnative`
- inventories input devices from `/proc/bus/input/devices` and `/sys/class/input/event*`
- highlights likely touchscreen candidates from device names and ABS capabilities
- displays the latest probe snapshot in a small Mesquite control panel

## Hard safety boundary

Version 0.1.0 is metadata-only. It does **not**:

- open `/dev/input/event*`
- call `EVIOCGRAB`
- create a `uinput` device
- inject or block touch events
- install a background daemon
- modify KOReader or the existing GhostGuard KOReader package/data

The purpose of this version is to identify the Kindle-native touchscreen/controller path safely before Observe, Auto Learn, Shadow Protect, or real Protect are attempted.

## Planned progression

1. v0.1 — read-only input/controller probe
2. v0.2 — passive event observation after device-specific validation
3. v0.3 — Auto Learn/profile generation adapted from the stable KOReader GhostGuard concepts
4. v0.4 — Shadow Protect (`WOULD_BLOCK`) without blocking input
5. v0.5+ — real native filtering only after device testing proves a fail-safe interception/reinjection path

The KOReader GhostGuard package remains an independent stable product and is not a dependency of this package.
