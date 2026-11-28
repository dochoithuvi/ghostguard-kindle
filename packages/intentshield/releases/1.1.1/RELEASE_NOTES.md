# DCPRO IntentShield™ 1.1.1 Stable

This release promotes the user-tested 1.1.1 Stability RC1. Only the release labels and documentation have changed since RC1.

### Stability improvements
- Respect KOReader input inhibition and discard stale queued actions.
- Correct dictionary word-box handling and reader-context checks; isolate lookup errors.
- Add detailed gesture and performance diagnostics with automatic local reporting.
- Preserve the original IntentGate core, gesture geometry and timing thresholds, overlap rejection, device adapter, and RSA licensing.
- Include the expanded Auto Boot Beta 2 implementation. Auto Boot is still experimental and opt-in; firmware/model, KPM, Upstart and launcher checks remain mandatory.

### Compatibility
Basic 2022 and Basic 2024 have been tested on hardware in the project. The 1.1.1 RC1 build was confirmed by the user. Paperwhite 4 and Basic 2019 remain experimental pending hardware validation. No claim is made that Auto Boot works on every eligible firmware.

### Install
Download the OneClick SH or the ZIP, then follow the English README. Existing valid licenses are retained. No license registry changes are included.

### Installer hotfix (same 1.1.1 Stable)
- Bounded KPM metadata operations: list-repo 30 seconds, add-repo 60 seconds, update 120 seconds. Retry once on ordinary update failure; stop on timeout and retain the installer. Requires setsid for fresh KPM installation. No forced interruption of package installation or final storage sync.
- No changes to the embedded IntentShield code, filtering, license, or experimental Auto Boot. Download the refreshed SH/ZIP and SHA256SUMS from this same release.
