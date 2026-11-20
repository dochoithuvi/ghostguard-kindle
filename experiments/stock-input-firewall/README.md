# GhostGuard Stock Input Firewall — Stage 0: safe probe

**Kindle Basic 2022 (KT5) / firmware 5.18.6 — experimental, read-only.**

Goal: re-use the existing GhostGuard Native/MTGuard5 logic to eventually suppress
phantom Goodix contacts **before** they reach the stock Kindle Home/Library and
Amazon reader, not just KOReader. This is NOT a working firewall yet.

## Existing GhostGuard code to re-use

- `packages/ghostguard/source/system/ghostguard-native-shadow.lua`: passive
  Goodix evdev parser and anomaly scoring while KOReader is closed.
- `packages/ghostguard/source/payload/dcghostguardpro.koplugin/ghostguard_core.lua`:
  MTGuard5 gesture/frame protection and adaptive decisions inside KOReader.
- `packages/ghostguard/source/system/ghostguard-service.sh`: lifecycle,
  controller fingerprint, resume handling, fail-open policy.
- `packages/ghostguard-native/source/probe.sh` and `watch.sh`: native input
  enumeration and short-lived passive event capture.
- `packages/ghostguard-native/source/launch.sh`: pre-existing appmgrd-based
  native launcher; it needs no KUAL.

Published GhostGuard 0.9.2 explicitly uses `NATIVE_FILTER=SHADOW_ONLY`,
`INPUT_GRAB=OFF`, `EVENT_INJECTION=OFF`. This experiment does not change it.

## Stage 0 — install and gather evidence from the physical stock Kindle

1. Copy `probe.sh` to Kindle USB root as
   `documents/GhostGuard_StockInput_Probe_Basic2022_5.18.6.sh`. SH Integration
   (from an existing jailbreak) makes it launchable from Library; no KUAL or
   KOReader needed.
2. Disconnect USB. Launch it from the **stock Kindle Library**.
3. The script forks a background read-only worker, then returns. **Within
   20 seconds**, open a book using the **Amazon stock reader** (not KOReader).
4. After 30–60 seconds, copy
   `GhostGuard_StockInput_Reports/stock-input-audit-latest.txt` and
   `GhostGuard_StockInput_Reports/launch.log` from the USB-visible Kindle root.
5. Keep reports private if they contain device/process details.

The probe reads only `/proc`, `/sys`, device-file *metadata* and symlinks; it
**does not open `/dev/input/event*` or `/dev/uinput`**. It never grabs the
physical Goodix event stream, changes IRQ settings or installs background boot
services. The worker terminates after a single two-phase audit.

The initial pass runs while Library is active; the delayed pass is intended to
run after the native reader has opened. The trace can reveal which processes
hold `/dev/input/event*`, the Goodix controller identity, and whether a uinput
node exists. However:

- A process showing no direct evdev FD does not prove that it receives no touch.
  Input may pass through the Amazon framework or X server.
- `/dev/uinput` existing does **not** prove the stock Amazon UI will recognize
  a virtual touchscreen device.
- This script does **not** perform virtual device creation, injection or a
  functional end-to-end stock touch acceptance test.
- This is not a substitute for reproducing ghost touch while watching the
  actual reader and for having USB/SSH or hardware recovery available.

## Stage 1 — proposed (not implemented)

With Stage 0 evidence from the **physical target**:

1. Determine which process / input subsystem actually serves stock Home,
   Library and reader; determine if Amazon can accept virtual evdev devices,
   including hot-plug, device name/IDs, coordinate ranges, `INPUT_PROP_DIRECT`,
   ABS_MT slots, tracking IDs, `SYN_REPORT` and event ordering.
2. Prove synthetic events are accepted using a **separate explicitly enabled
   and time-limited** virtual input test while leaving the physical event
   path untouched. No production actions unless explicitly approved.
3. Only after successful Stage 1, use a short-lived opt-in `EVIOCGRAB` gate
   and replay good complete frames through a virtual touch device. Never
   block a shared power-button device. Abort open/release on any error.
4. Port native-shadow's scorer and the MTGuard5 profile schema in a separate
   reader-agnostic classifier; preserve complete multi-touch slot lifetimes.
   Do not suppress fragments out of context.
5. Provide fail-open watchdog, controller fingerprint check, emergency disable
   file/command, no auto-start on boot before field validation, bounded logs,
   and clearly documented rollback.
6. Only after real-device qualification, integrate into GhostGuard Native's
   Library app, appmgrd/Mesquite lifecycle, and KPM packaging **without KUAL**.

**Never** claim production protection or an Amazon-compatible virtual
input device based only on this read-only probe or an x86/Linux fixture.

## Local tests

Run `sh -n probe.sh` and `sh test.sh` on a Linux development machine. These
verify script syntax and mocked `/proc`/`/sys` detection only. They cannot
verify Kindle 5.18.6 hardware, `powerd`, Amazon reader event routing, UI input
acceptance or recovery from a grabbed touchscreen.