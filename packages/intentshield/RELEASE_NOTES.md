# DCPRO IntentShield™ 1.0 Final — Global Protection

By Dochoithuvi. Standalone successor to the legacy GhostGuard filter, for jailbroken Kindle Basic 2022 (KindleBasic4), portrait 1072×1448, existing KOReader and ZenOS v4.3.2.

- Intent-based swipe authorization across Home, Library, Reader and supported menus.
- Continuous shielding, optional auto-resume, USB kill switches and two-stroke escape.
- Strict classifier and Global action logic preserved from device-tested 0.5.
- Offline installer, checksum verification, versioned rollback and optional reversible legacy-plugin migration.
- ZenOS Auto Boot is EXPERIMENTAL: v0.5 firmware preflight refused installation on the test unit; v1.0 expands version detection and diagnostics, but actual boot is not verified on hardware.
- Requires preinstalled compatible KOReader (2026.07 recommended) and ZenOS; does not ship or replace them. Only authorized completed strokes can produce actions while Shield is active; this is a software workaround, not a hardware repair.
- User confirmed v0.5 Global works on one Basic 2022. Reader 0.3 was tested independently of legacy Protect with no unintended page turns in a 15-minute trial. v1.0 installer and Auto Boot changes have not been validated on physical hardware. Lua 5.4 local synthetic/mock tests pass; not a LuaJIT or device certification.

## Install
Download the ZIP asset; extract COPY_TO_KINDLE_ROOT into Kindle USB root. Close KOReader; run GhostGuard_IntentGate_INSTALL.sh via SH Integration. Test Global Shield for 5 minutes, then continuous. To replace legacy GhostGuard, close KOReader and run IntentShield_REPLACE_LEGACY.sh. Existing license and profiles are preserved; legacy native shadow service is not modified.

Auto Boot: run IntentShield_BOOT_PROBE.sh, verify exact firmware 5.18.6, then IntentShield_ENABLE_AUTOBOOT.sh as root only after manual Global testing. See README_VI.txt. If firmware check refuses, do not bypass it. Recovery: create DISABLE_INTENTGATE and DISABLE_INTENTSHIELD_BOOT in USB root; delete ENABLE_INTENTSHIELD_GLOBAL and ENABLE_INTENTSHIELD_BOOT. No forced reboot or respawn.

SHA-256 (ZIP): 2ba8bb7731f27430841c92982d2e74068cc169965f38987ad2034720a27b1f24

The legacy main branch and release channel remain untouched. No SimpleUI dependency. No diagnostic reports or personal device identifiers are distributed.
