# DCPRO IntentShield™ 1.2.1 RC1 — Touch Recovery V2

**YOUR INTENT. YOUR CONTROL.** Developed by Dochoithuvi.

Release candidate for hardware validation. The latest Stable remains 1.2.0. This RC is not offered by the Stable Smart Update feed.

## Changes

- Basic 2022 (KindleBasic4): read-only Goodix `EVIOCGABS` / `EVIOCGMTSLOTS` snapshots at activation and qualified recovery boundaries. The driver is never reset, grabbed or written to. Active startup contacts are drained; a quarantined parser resumes only after an explicit release boundary and matching idle kernel snapshot. The recovery frame is discarded. Unknown or active state stays quarantined; no timeout-based clearing of active slots. Unsupported/unavailable startup queries retain the existing parser path and log the limitation. Native gesture isolation remains enabled.
- Input inhibition: do not clear the drain flag until a completed contact-free frame; discard actions spanning inhibited input or recovery. The original IntentGate core, device and gesture profiles, signed license implementation, and all thresholds remain byte-identical to 1.2.0.
- Kindle Virtual Library v0.0.11 (official ARMv7 archive, SHA-256 pinned), installed by OneClick if absent. Existing installation and preferences retained. Fresh ZenOS 4.3.2 defaults enable the built-in Kindle Library tab; existing compatible configurations append it if fewer than seven tabs are visible. Unsupported configurations remain unchanged; add through Zen Settings manually. Reading-state sync remains off by upstream default. Some native books may not open; first preparation may take time. Use only books you are authorized to access.
- ZenFM 1.2.2 integration retained; Auto Boot remains disabled. Smart Update keeps the production key and 23-file protocol. The signed RC package is provided for verification, not automatic distribution.

## Install the RC

1. Back up books/settings; fully exit KOReader and stop ZenFM. Disable Auto Boot and legacy GhostGuard Pro if present.
2. Download the OneClick SH from the **1.2.1 RC1** release (not `latest`). Copy it to `documents`; execute using root SH Integration. Wi-Fi is needed for missing dependencies including the Kindle Library download (~22 MB).
3. Launch KOReader manually. Existing valid licenses are preserved. Enable Global Shield if necessary.
4. Test Home, Reader, Kindle Library, page swipes, dictionary, 10+ sleep/wake cycles, rapid overlapping touches, and first launch after reboot. Check `GhostGuard_Reports/IntentGate/` for `STARTUP` and `RECOVERY_V2` diagnostics. An active or continuously noisy touch panel may still block gestures; Sleep/Wake remains a fallback. Do not assume a hardware repair.

## Smart Update

Older releases and 1.2.0 Stable need the RC OneClick to install the external Kindle Library plugin. The existing 23-file signed updater cannot install external plugins or modify ZenOS preferences. After a compatible Stable release is published, the regular update menu can install later signed plugin-only updates. RC sequence 12101 is lower than planned 1.2.1 Stable sequence 12110. No private signing key is distributed. A rollback to 1.2.0 requires its trusted OneClick with KOReader closed.

## Validation and limits

11 mocked recovery/inhibition scenarios and Lua syntax checks passed locally; all 23 plugin files are checked and the update manifest is RSA verified against the existing production key. The actual ARM Goodix ioctl behavior, upstream binary loading, and full OneClick / hardware recovery have not yet been tested on a Kindle. Native recovery V2 is Basic 2022 only; other models retain existing device adapters. Fresh installs require compatible KOReader, ZenOS and root SH Integration. Basic 2019 and Paperwhite 4 remain experimental. This candidate is not a promise of complete resolution of physical ghost touch.

## Rescue

Create empty `DISABLE_INTENTGATE` and `DISABLE_INTENTSHIELD_BOOT` at USB storage root; remove `ENABLE_INTENTSHIELD_GLOBAL` and `ENABLE_INTENTSHIELD_BOOT`; restart if required. Backups are kept. Never share device identifiers or license details publicly. See the repository's Stable documentation for gesture rules and requirements.

Upstream [Kindle Virtual Library](https://github.com/kaikozlov/kindle.koplugin) (MIT), [ZenFM](https://github.com/xZenLabs/zen-fm), [ZenOS](https://github.com/xZenLabs/zen-os) and KOReader retain their respective licenses.
