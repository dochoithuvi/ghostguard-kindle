# DCPRO IntentShield™ 1.2.1 Stable

**YOUR INTENT. YOUR CONTROL.** Developed by Dochoithuvi.

IntentShield filters unintended touchscreen contacts in KOReader + ZenOS on jailbroken Kindles. It does not repair touch hardware or protect the native Kindle interface.

[Download OneClick](https://github.com/dochoithuvi/ghostguard-kindle/releases/latest/download/DCPRO_IntentShield_OneClick_Install.sh) · [Releases](https://github.com/dochoithuvi/ghostguard-kindle/releases)

## What's new

- Smart Update: user-initiated, RSA-3072 signed manifests and SHA-256 verified plugin packages, staged before restarting KOReader. No background polling or firmware reboot.
- Touch Recovery V2 (Basic 2022 only): read-only Goodix slot snapshots, startup contact drain, explicit all-up plus verified idle state before parser recovery, and discard contacts spanning input inhibition. No driver reset, timeout clearing, or relaxed thresholds.
- Kindle Virtual Library v0.0.11 (official ARMv7 package, SHA-256 pinned) via OneClick if absent. Adds the built-in Kindle Library navigation tab on compatible ZenOS configurations when space permits; existing settings retained. Reading-state sync is off by upstream default. First book preparation may take time; use only authorized books.
- Native Gesture Isolation on Kindle Basic 2022 only; raw IntentGate filtering remains active. Context transition protection, contact watchdog and conservative native gesture recovery after observed releases.
- Original IntentGate core, gesture thresholds, device adapter and license implementation unchanged.
- ZenFM 1.2.2 integration and navigation shortcut, with existing settings preserved; fresh setup uses HTTPS, documents root and five-minute inactivity timeout. Stop the server after transferring books.
- Auto Boot disabled. Open KOReader manually after installation; Global Shield and its normal resume behavior remain available.

## Install or upgrade from an older version

Requirements: jailbroken supported Kindle, root SH Integration, compatible KOReader 2026.03+ launcher, ZenOS 4.3+ (fresh installation uses verified 4.3.2), Wi-Fi for missing dependencies. KPM is required if KOReader is not installed. The project owner confirmed 1.2.1 RC1 works on their Kindle Basic 2022 after testing. The Stable promotion changes version labels and sequence only, not recovery logic. Basic 2024 was tested with earlier versions. Paperwhite 4 and Basic 2019 remain experimental. Native isolation is Basic 2022 only.

1. Back up your data, disable Auto Boot and exit KOReader fully. Disable legacy GhostGuard Pro if installed.
2. Download the current OneClick SH, copy to Kindle `documents`, and run with root SH Integration.
3. When installation is complete, open KOReader manually. Existing valid licenses are retained. Enable Global Shield from the menu if necessary.
4. Versions before 1.2.0 Stable (including 1.2.0 RC1/RC2) need OneClick once for the production trust anchor and launcher hook. No uninstall or license reissue is normally needed.
5. 1.2.0 Stable and 1.2.1 RC1 can update IntentShield by OTA. To install Kindle Virtual Library and its navbar tab on a device that does not already have it, run the full OneClick. OTA does not install external plugins.

## Future updates

Connect Wi-Fi, then choose IntentShield > Software Update > Check for Update. Confirm Update now, and restart KOReader when prompted. The updater verifies a signed manifest and ZIP digest, stages the package and applies it before `reader.lua` loads. It retains a backup; it does not automatically roll back runtime regressions. Requires curl, OpenSSL CLI, sha256sum, unzip, LuaJIT and a compatible launcher hook. If the hook is missing or replaced by a KOReader upgrade, use the current OneClick. Never launch two KOReader instances simultaneously. Do not suspend or disconnect during staging or activation.

The signed package is limited to the fixed 23-file plugin layout and preserves raw filter, gesture and license files. Changes to installer, launcher hook, trust anchor, protected files or external dependencies require a new trusted OneClick. The three `IntentShield_UPDATE.*` assets are for the updater, not manual installation. Do not use RC offline fixtures with Stable. Stable sequence: 12110 (RC1: 12101).

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

USB rescue: create empty `DISABLE_INTENTGATE` and `DISABLE_INTENTSHIELD_BOOT` at USB storage root; remove `ENABLE_INTENTSHIELD_GLOBAL` and `ENABLE_INTENTSHIELD_BOOT`, restart if necessary. If update fails, keep the current version or reinstall a trusted OneClick with KOReader closed. Reports: `GhostGuard_Reports/IntentGate/`, including `update.log`. Do not share device identifiers or license data publicly. Recovery does not guarantee that a physically stuck touchscreen will recover; Sleep/Wake remains a fallback. The owner reported successful RC1 hardware testing; the Stable packaging and OTA path are checked in software, not independently retested on a physical Kindle. Persistent physical ghost touch can still block gestures.

Third-party [Kindle Virtual Library](https://github.com/kaikozlov/kindle.koplugin) (MIT), ZenOS, ZenFM and KOReader retain their own licenses. See [LICENSE](https://github.com/dochoithuvi/ghostguard-kindle/blob/main/LICENSE) for DCPRO terms.
