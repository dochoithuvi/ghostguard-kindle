# DCPRO IntentShield™ — 1.1.1 Stable

**YOUR INTENT. YOUR CONTROL.**

Developed by **Dochoithuvi**. IntentShield helps readers use jailbroken Kindles affected by ghost touches in KOReader with ZenOS. It filters unintended touchscreen contacts and translates deliberate gestures into reading and navigation actions. It does not repair touchscreen hardware or protect the native Kindle interface.

**[Download OneClick (.sh)](https://github.com/dochoithuvi/ghostguard-kindle/releases/download/intentshield-v1.1.1/DCPRO_IntentShield_OneClick_Install.sh)** · [ZIP package](https://github.com/dochoithuvi/ghostguard-kindle/releases/download/intentshield-v1.1.1/DCPRO_IntentShield_1.1.1_Stable_OneClick.zip) · [Release notes](https://github.com/dochoithuvi/ghostguard-kindle/releases/tag/intentshield-v1.1.1)

## Supported devices

| Device | Support status | Experimental Auto Boot firmware |
| --- | --- | --- |
| Kindle Basic 2022 (11th generation) | Tested on hardware | 5.18.6 or newer |
| Kindle Basic 2024 | Tested on hardware in earlier builds | 5.18.6 or newer |
| Kindle Paperwhite 4 (10th generation, 2018) | Experimental; hardware validation pending | 5.18.1, 5.18.1.1, 5.18.1.1.1 |
| Kindle Basic 2019 (10th generation) | Experimental; hardware validation pending | 5.18.1, 5.18.1.1, 5.18.1.1.1 |

Firmware ranges for Auto Boot are eligibility checks, not guarantees of compatibility. Jailbreak, KPM, Upstart, and the KOReader launcher must also pass preflight. Do not update firmware merely to meet these requirements.

## What's new in 1.1.1

- Input stability: respect KOReader input inhibition, discard contacts crossing an observed inhibition period, and drop actions queued for more than one second.
- Dictionary: correct word-box handling and reader context checks; contain dictionary API failures without stopping the entire shield.
- Diagnostics: record gesture rejection reasons, geometry and slow processing; automatically save local reports without logging looked-up words.
- Expanded experimental Auto Boot with firmware/model preflight and re-authorization after firmware changes.
- Unchanged IntentGate core, gesture thresholds, overlap rejection, device adapter, and RSA license system.

## Installation

Requirements: a jailbroken supported Kindle, root SH Integration, Wi-Fi, and KPM (install KOReader through KPM if not already installed). The installer checks compatible layouts in KOReader 2026.03+ and ZenOS 4.3+. Future releases are not automatically guaranteed to work.

1. Back up your data. Disable any legacy GhostGuard protection and exit KOReader.
2. Download the SH file, or extract it from the ZIP. Copy it to the Kindle's `documents` directory.
3. Disconnect USB, connect to Wi-Fi, and run the file using root SH Integration.
4. Follow the nine installation stages. The installer detects the model, installs missing components, verifies the plugin, launches KOReader, and removes the installer when possible.
5. Open DCPRO IntentShield from the navigation bar or plugin menu. A valid existing device license is retained; sync online if necessary.
6. On models with a trial startup session, verify gestures during the 60-second trial and select **Global Shield** for continuous protection.

## Gesture guide

| Gesture | Action |
| --- | --- |
| Horizontal swipe while reading | Turn pages |
| Horizontal swipe ending on a menu item | Select the item |
| Vertical swipe in a list | Scroll |
| Long vertical swipe in the reading area | Open the menu |
| Upward swipe from the bottom edge, outside the left quarter | Open Page Browser / Aa |
| Diagonal swipe ending on a word | Dictionary lookup in supported regions |

Dictionary gestures retain their existing directional and regional limits: up-left in the left half, downward diagonals near the bottom quarter, and up-right within the supported area. A dictionary must be installed, and the document must support word extraction. See the illustrated **Gesture Guide** in the plugin. Ordinary raw taps are blocked while protection is active.

## Auto Boot (experimental)

Auto Boot is opt-in. The installer prepares the Upstart job only when preflight succeeds. Enable it from the plugin after confirming Global Shield and USB recovery work. Firmware changes require enabling it again. No automatic reboot is triggered by installation. Firmware eligibility does not establish successful boot on every device; expanded Auto Boot remains experimental.

## Recovery and troubleshooting

- Stop protection from the plugin and confirm. Auto Shield may resume on the next KOReader launch depending on configuration.
- USB recovery: create empty files named `DISABLE_INTENTGATE` and `DISABLE_INTENTSHIELD_BOOT` at the Kindle's USB storage root, remove `ENABLE_INTENTSHIELD_GLOBAL` and `ENABLE_INTENTSHIELD_BOOT`, and restart if needed. USB recovery requires accessible USB storage.
- Local reports are saved under `GhostGuard_Reports/IntentGate/`. For dictionary or input issues, include relevant PROFILE, DICT_RESULT and PERF records and KOReader's crash.log. Remove personal identifiers before sharing.
- Overlapping ghost contacts can cause genuine swipes to be rejected. This conservative behavior is intentional; the filter is not loosened to accept ambiguous contacts.
- If external input devices are involved, compare behavior without HIDPassthrough or Bluetooth accessories. The installer does not uninstall them.
- A valid license is required. See the repository's [LICENSE](https://github.com/dochoithuvi/ghostguard-kindle/blob/main/LICENSE) for DCPRO terms; third-party components retain their respective licenses.

[Releases](https://github.com/dochoithuvi/ghostguard-kindle/releases) · [Report an issue](https://github.com/dochoithuvi/ghostguard-kindle/issues)
