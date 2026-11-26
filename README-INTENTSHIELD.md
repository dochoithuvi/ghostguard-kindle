# DCPRO IntentShield™ 1.0 Final — Unified Licensed Edition

**YOUR INTENT. YOUR CONTROL.** · By Dochoithuvi

This is the licensed revision of the same 1.0 Final product, not version 1.1. Standalone successor to legacy GhostGuard for jailbroken Kindle Basic 2022 (KindleBasic4), portrait 1072 × 1448, with compatible preinstalled KOReader (2026.07 recommended) and ZenOS v4.3.2.

## What's new
- A single Vietnamese IntentShield menu: continuous Global Shield + Auto Resume, Stop, Status, License, Reports & Help.
- The strict swipe classifier and Global action mapping from the device-tested 0.5 are retained. No legacy tap/profile engine, SimpleUI or old calibration menu.
- Existing valid GhostGuard RSA v4 keys and signed online registry policy are reused. Manual start, automatic start, resume and active sessions are checked. Stop and recovery remain available without a license. First-time users of the online registry may need to sync over Wi-Fi.
- Offline installer preserves a prior signed license.key from IntentShield, GhostGuard or the recorded legacy backup. Run IntentShield_REPLACE_LEGACY.sh after validating the new installation to remove the old plugin from the active plugin directory without destroying user data. License/profile backups and read-only native diagnostic service are preserved.
- Legacy GhostGuard KPM distributions and old SimpleUI OneClick installer removed from main and intent-shield. KindleForge and signed license registry preserved.

## Install
Exit KOReader, back up your device, extract the ZIP and copy the contents of COPY_TO_KINDLE_ROOT to the Kindle USB root. Run GhostGuard_IntentGate_INSTALL.sh through SH Integration. Open ZenOS → Launcher / Plugin Menu → DCPRO IntentShield™ → License, check or sync your license; enable Global Shield — liên tục + Auto Resume. Once confirmed, exit KOReader and run IntentShield_REPLACE_LEGACY.sh. See README_VI.txt.

## Recovery and Auto Boot
Two opposite long vertical strokes in the leftmost quarter within 8 seconds exit Shield. Power and USB recovery remain available. Use DISABLE_INTENTGATE and DISABLE_INTENTSHIELD_BOOT in the USB root; remove ENABLE_INTENTSHIELD_GLOBAL and ENABLE_INTENTSHIELD_BOOT. Auto Boot remains experimental, only for verified firmware 5.18.6 with root access; do not bypass its preflight. No respawn loop; the stock Kindle UI and loading period remain unprotected.

## Validation
Classifier and mock integration tests, actual RSA signature acceptance/tamper/mismatched serial checks using an ephemeral CI key, mock revocation-policy and license-start/resume checks, shell syntax and archive checksum tests passed in CI. The earlier swipe engine was tested on one Basic 2022; the integrated license, updated installer and actual Auto Boot still require physical-device validation. This software mitigates ghost-triggered UI actions; it does not repair the touchscreen or promise perfect recognition. The build does not bundle KOReader or ZenOS.

Local reports: GhostGuard_Reports/IntentGate/. Never share private licenses or raw device identifiers publicly.

[Source and offline installer](packages/intentshield/)
