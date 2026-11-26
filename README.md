# DCPRO IntentShield™ — Global Protection

**YOUR INTENT. YOUR CONTROL.**

[![Release](https://img.shields.io/badge/release-1.0%20Final-238636)](https://github.com/dochoithuvi/ghostguard-kindle/releases/tag/intentshield-v1.0.0-r2)
![Device](https://img.shields.io/badge/Kindle-Basic%202022-333333)
![ZenOS](https://img.shields.io/badge/ZenOS-4.3.2-blue)

Developed by **Dochoithuvi** · Intent-based ghost touch protection for Kindle.

IntentShield is the standalone next-generation successor to GhostGuard. Instead of trying to identify every false touch, it authorizes actions only after a completed swipe satisfies an intentional-gesture classifier. Ordinary taps are blocked while Shield is active.

**[Download IntentShield 1.0 Final (ZIP)](https://github.com/dochoithuvi/ghostguard-kindle/releases/download/intentshield-v1.0.0-r2/DCPRO_IntentShield_1.0_Final_Basic2022.zip)** · [Release notes & checksums](https://github.com/dochoithuvi/ghostguard-kindle/releases/tag/intentshield-v1.0.0-r2) · [Vietnamese installation guide](https://github.com/dochoithuvi/ghostguard-kindle/blob/intent-shield/packages/intentshield/README_VI.txt)

## What makes IntentShield different?

| Legacy GhostGuard | IntentShield |
| --- | --- |
| Classifies suspicious touch contacts and learned ghost regions | Authorizes completed swipes that meet intent criteria |
| Conventional touch interactions | Swipe-based selection, navigation and page turns |
| Protect inside KOReader | Global Shield across ZenOS Home, Library, Reader and supported menus |
| Legacy profile and Protect engine | Independent engine, no SimpleUI dependency |

## Requirements

- Jailbroken Kindle Basic 2022 (KOReader model `KindleBasic4`), portrait 1072 × 1448.
- Existing compatible [KOReader](https://github.com/koreader/koreader) (2026.07 recommended) and [ZenOS v4.3.2](https://github.com/xZenLabs/zen-os/releases/tag/v4.3.2).
- SH Integration or appropriate shell access for installation.
- Auto Boot specifically requires verified firmware **5.18.6** and root access.

The ZIP is an offline IntentShield installer; it does not bundle or replace KOReader or ZenOS.

## Quick start

1. Back up your Kindle, stop legacy GhostGuard Protect and exit KOReader.
2. Download the release ZIP and copy the **contents** of `COPY_TO_KINDLE_ROOT` to the Kindle USB root.
3. Run `GhostGuard_IntentGate_INSTALL.sh` from Library using SH Integration.
4. Open ZenOS and find **DCPRO IntentShield 1.0** in Launcher / Plugin Menu.
5. Open **License**, verify or sync an existing valid GhostGuard license, then enable **Global Shield — liên tục + Auto Resume**.

## Global Shield controls

| Screen / action | Gesture |
| --- | --- |
| Home, Library, supported menus | Swipe horizontally and lift at the item to select |
| Scroll a supported list | Swipe vertically near the center |
| Reader page turn | Swipe left or right |
| Open Reader menu | Long vertical swipe (at least 300 px) near the center |
| Exit Shield | Two opposing long vertical swipes (at least 350 px each) within 8 seconds, both starting and ending in the left quarter |

Single taps, holds and normal pan gestures are blocked. Some special widgets and keyboards may need a different workflow. The power button remains available; optional resume re-arms protection after a five-second delay.

## Replace legacy GhostGuard (optional)

After testing Global Shield, exit KOReader and run `IntentShield_REPLACE_LEGACY.sh`. The old plugin is moved to a backup outside the active plugin directory; license, profiles and native diagnostic service are preserved. Use `IntentShield_RESTORE_LEGACY.sh` to reverse the migration.

## ZenOS Auto Boot — experimental

**Auto Boot is optional and is not yet verified on physical hardware.** Version 0.5 refused installation during firmware detection; version 1.0 improves detection and diagnostics.

Run `IntentShield_BOOT_PROBE.sh`, confirm the exact firmware and check the report, then run `IntentShield_ENABLE_AUTOBOOT.sh` as root only after manual Global Shield works. Do not bypass a failed preflight. Follow the [full guide](https://github.com/dochoithuvi/ghostguard-kindle/blob/intent-shield/packages/intentshield/README_VI.txt) for the firmware verification procedure.

The Upstart job makes at most one launch attempt per boot; no respawn loop or forced shutdown of the Amazon framework. The stock Kindle UI and boot/loading period are not protected. KOReader's startup settings determine whether Home or the last book is shown.

### Recovery

If touch becomes difficult, use the power button, let a timed session expire, or connect USB and create empty files at the Kindle root:

```text
DISABLE_INTENTGATE
DISABLE_INTENTSHIELD_BOOT
```

Remove `ENABLE_INTENTSHIELD_GLOBAL` and `ENABLE_INTENTSHIELD_BOOT`. Run `IntentShield_DISABLE_AUTOBOOT.sh` to disable and remove the optional job. Exit KOReader before running `GhostGuard_IntentGate_ROLLBACK.sh`. Reboot if necessary; USB availability is not guaranteed during a system hang.

## Validation and limitations

- Reader 0.3 was tested on one Basic 2022 with legacy Protect off: the user reported no unintended page turns in a 15-minute trial.
- The same user confirmed Global Shield 0.5 worked well. Version 1.0 retains that Strict classifier and Global action logic.
- Local Lua 5.4 synthetic and mock integration tests passed. The 1.0 installer changes and Auto Boot still need physical-device validation.
- IntentShield mitigates unintended UI actions; it cannot repair a damaged touchscreen or guarantee zero false accepts.

Local reports: `/mnt/us/GhostGuard_Reports/IntentGate/`. Do not post reports containing personal device identifiers publicly.

---

## Distribution channels

- **DCPRO IntentShield™ 1.0 Final**: [Release ZIP](https://github.com/dochoithuvi/ghostguard-kindle/releases/tag/intentshield-v1.0.0-r2) and [dedicated source branch](https://github.com/dochoithuvi/ghostguard-kindle/tree/intent-shield).
- Legacy GhostGuard and GhostGuard Native KPM packages and the old SimpleUI OneClick installer have been retired. They are no longer offered from the current main branch. Existing signed license registry and public verification keys remain available. Git history is preserved.
- KindleForge continues to be offered via [KPM v2 manifest](manifest.v2.json). IntentShield is not installed by KPM.

The latest 1.0 Final unified licensed revision is published. It retains the tested Strict swipe logic and uses existing GhostGuard RSA v4 keys and signed registry policy. CI passed including real RSA acceptance and tamper rejection with an ephemeral test key. Physical-device validation of the integrated license and Auto Boot is still pending. Download the latest release ZIP (revision r2), not the earlier unlicensed 1.0 build.
