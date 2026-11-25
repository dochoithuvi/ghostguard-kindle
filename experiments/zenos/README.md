# GhostGuard ZenOS — v1 experimental source

Target: Kindle Basic 11 (KT5, 2022), 5.18.6. Upstream ZenOS v4.3.2, with KOReader 2026.03+ (ZenOS docs recommend 2026.07). This is a KOReader integration, not a replacement firmware. Keep Amazon framework and recovery paths intact.

## What changed
- Existing MTGuard5, Adaptive V3, licensing, profile approval, fault and suspend handling preserved.
- With ZenOS installed alongside GhostGuard, opt in via DCPRO GhostGuard menu → ZenOS: bảo vệ sớm (thử nghiệm). Restart. Only the existing approved, licensed Auto Protect path uses a 1-second schedule instead of the ordinary startup delay. Online license flow and new calibration retain existing timings.
- With this opt-in, unapproved candidates older than 30 minutes expire before matching or promotion; approved regions are not deleted. This is a first step toward adaptive aging, not a new classifier or guaranteed ghost removal.
- ZenOS can expose the existing GhostGuard menu via Launcher → Plugin Menu / KOReader menu. No ZenOS source modifications.
- No changes to evdev, Goodix IRQ, power, or /dev/uinput.

## Manual qualification first
1. Back up the installed plugin folder and existing profiles. Copy the changed main.lua and adaptive_bootstrap.lua into the same existing GhostGuard plugin version (base commit a88d948); do not mix versions.
2. Install ZenOS from its official release and follow its documented conflict migration; do not run SimpleUI and ZenOS together.
3. Launch KOReader normally from Library; confirm ZenOS Home and GhostGuard menu, license, existing profile, ordinary touches, page turns, Home → Library → Reader → Home, sleep/resume, and exit to Amazon UI.
4. Enable experimental Zen option and restart; repeat the checks with a good panel and with ghost touch. Use existing SAFE_MODE if needed. Do not claim protection before first accepted input hook, outside KOReader, or during Amazon startup.
5. Copy boot-launch.sh into /mnt/us/GhostGuardZenOS/. Run sh /mnt/us/GhostGuardZenOS/boot-launch.sh probe from root SSH or a verified SH Integration launcher. Report is GhostGuard_Reports/ZenOS-boot.log. Then manual mode can start the already installed stack without KUAL, only after the earlier steps pass.

## Optional boot integration (NOT installed)
The .conf is a template referencing event names reported for another Kindle firmware/model. It must be checked against actual /etc/upstart jobs and boot events on KT5 before installation. Do not install blindly. After manual qualification and verified root USB/SSH rescue, a qualified maintainer can install that job, with no respawn and no framework-stop, and explicitly create ENABLE_GHOSTGUARD_ZEN_BOOT in the USB root. An opt-in early protection marker must also exist. The job attempts a launch once per kernel boot ID; Amazon remains available before launch or on exit.

Rollback: create DISABLE_GHOSTGUARD_ZEN_BOOT in USB root or remove ENABLE_GHOSTGUARD_ZEN_BOOT, then reboot. Remove the optional Upstart job if installed; remove .dcpro_ghostguard/ZEN_EARLY_PROTECT or disable the menu option to revert timings; restore backed-up Lua files if needed. Verify recovery before arming. No automatic installation or enabled boot job is shipped.

## Evidence and limits
- https://zen-labs.org/zen-os/docs/installation
- https://github.com/xZenLabs/zen-os/releases/tag/v4.3.2
- https://github.com/xZenLabs/zen-os/blob/main/docs/launcher.md
- https://github.com/koreader/koreader/blob/master/platform/kindle/koreader.sh
- https://gist.github.com/SuleMareVientu/822b2b51d1ea043ce2b190669c0df38b (different Kindle/firmware; example only)

No hardware or UI compatibility test performed. Do not use for severe ghost touch or assume no exposure to stock Home. No licensing bypass; do not distribute the full patched product until acceptance testing and packaging are complete.
