# DCPRO IntentShield™ 1.2.0 Stable

**Smart Update · Input Stability · ZenFM**

This release promotes the owner-tested 1.2.0 RC1 and offline RC2 update test. Stable uses a new, independent production update trust anchor and sequence 12010. The original filter, gesture thresholds, device adapter and license implementation are preserved.

- Native gesture isolation for Kindle Basic 2022; context transition protection and conservative native gesture recovery.
- Signed, user-initiated plugin updates from GitHub. Verify RSA signatures and SHA-256, stage the package, restart KOReader, retain a backup.
- ZenFM 1.2.2 integration with navigation shortcut. Preserve existing settings; no automatic server start.
- Auto Boot disabled. Open KOReader manually after installation.
- KPM metadata timeout retained.

## Upgrade from older versions

Install the OneClick SH once using root SH Integration with KOReader closed. No uninstall or license reissue is normally required. This also applies to RC1/RC2, which use a separate test key. Later compatible plugin releases can be installed using **Software Update > Check for Update**. The three update assets are consumed by the updater automatically. Do not install them manually.

## Validation and limitations

Owner confirmed the RC1 device test and offline RC2 update. Production trust provisioning and online checking still need on-device validation. Native isolation applies only to Basic 2022; Paperwhite 4 and Basic 2019 remain experimental. No hardware repair or guaranteed recovery from persistent ghost contacts is claimed. The updater protects the original core/license files and has a fixed 23-file layout; incompatible changes require a new OneClick. Automatic rollback of runtime regressions is not provided. Keep a known-good installer.

See the English README for requirements, gestures, recovery and compatibility.
