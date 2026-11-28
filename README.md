# DCPRO IntentShield™ 1.2.0 Stable

**YOUR INTENT. YOUR CONTROL.** Developed by Dochoithuvi.

IntentShield filters unintended touchscreen contacts in KOReader + ZenOS on jailbroken Kindles. It does not repair touch hardware or protect the native Kindle interface.

[Download OneClick](https://github.com/dochoithuvi/ghostguard-kindle/releases/latest/download/DCPRO_IntentShield_OneClick_Install.sh) · [Releases](https://github.com/dochoithuvi/ghostguard-kindle/releases)

## What's new

- Smart Update: user-initiated, RSA-3072 signed manifests and SHA-256 verified plugin packages, staged before restarting KOReader. No background polling or firmware reboot.
- Native Gesture Isolation on Kindle Basic 2022 only; raw IntentGate filtering remains active. Context transition protection, contact watchdog and conservative native gesture recovery after observed releases.
- Original IntentGate core, gesture thresholds, device adapter and license implementation unchanged.
- ZenFM 1.2.2 integration and navigation shortcut, with existing settings preserved; fresh setup uses HTTPS, documents root and five-minute inactivity timeout. Stop the server after transferring books.
- Auto Boot disabled. Open KOReader manually after installation; Global Shield and its normal resume behavior remain available.

## Install or upgrade from an older version

Requirements: jailbroken supported Kindle, root SH Integration, compatible KOReader 2026.03+ launcher, ZenOS 4.3+ (fresh installation uses verified 4.3.2), Wi-Fi for missing dependencies. KPM is required if KOReader is not installed. Basic 2022 was tested by the project owner with 1.2.0 RC1 and the offline update fixture. Basic 2024 was tested with earlier versions. Paperwhite 4 and Basic 2019 remain experimental. Native isolation is Basic 2022 only.

1. Back up your data, disable Auto Boot and exit KOReader fully. Disable legacy GhostGuard Pro if installed.
2. Download the current OneClick SH, copy to Kindle `documents`, and run with root SH Integration.
3. When installation is complete, open KOReader manually. Existing valid licenses are retained. Enable Global Shield from the menu if necessary.
4. All versions before 1.2.0 Stable (including RC1/RC2) require this one-time OneClick migration to install the production update trust anchor and compatible launcher hook. No uninstall or license reissue is normally needed.

## Future updates

Connect Wi-Fi, then choose IntentShield > Software Update > Check for Update. Confirm Update now, and restart KOReader when prompted. The updater verifies a signed manifest and ZIP digest, stages the package and applies it before `reader.lua` loads. It retains a backup; it does not automatically roll back runtime regressions. Requires curl, OpenSSL CLI, sha256sum, unzip, LuaJIT and a compatible launcher hook. If the hook is missing or replaced by a KOReader upgrade, use the current OneClick. Never launch two KOReader instances simultaneously. Do not suspend or disconnect during staging or activation.

The signed package is limited to the fixed 23-file plugin layout and preserves raw filter, gesture and license files. Changes to installer, launcher hook, trust anchor, protected files or external dependencies require a new trusted OneClick. The three `IntentShield_UPDATE.*` assets are for the updater, not manual installation. Do not use RC offline fixtures with Stable. Stable sequence: 12010.

## Gesture guide

| Gesture | Action |
| --- | --- |
| Horizontal swipe in Reader | Page turn |
| Horizontal swipe ending on a Home/Library item | Select item |
| Vertical swipe in lists | Scroll |
| Long vertical swipe in reading area | Open menu |
| Swipe up from bottom edge outside left quarter | Page Browser / Aa |
| Diagonal swipe ending on a word in supported regions | Dictionary lookup |

Use the in-plugin Gesture Guide. Raw taps are blocked during protection. Up-left lookup ends in the left half; downward diagonals end in the bottom quarter. A supported document and installed dictionary are required.

## Recovery

USB rescue: create empty `DISABLE_INTENTGATE` and `DISABLE_INTENTSHIELD_BOOT` at USB storage root; remove `ENABLE_INTENTSHIELD_GLOBAL` and `ENABLE_INTENTSHIELD_BOOT`, restart if necessary. If update fails, keep the current version or reinstall a trusted OneClick with KOReader closed. Reports: `GhostGuard_Reports/IntentGate/`, including `update.log`. Do not share device identifiers or license data publicly. Recovery does not guarantee that a physically stuck touchscreen will recover; Sleep/Wake remains a fallback. The production online feed and Stable trust provisioning need device validation even though RC1 and the offline update were owner-tested.

Third-party ZenOS, ZenFM and KOReader retain their own licenses. See [LICENSE](https://github.com/dochoithuvi/ghostguard-kindle/blob/main/LICENSE) for DCPRO terms.
