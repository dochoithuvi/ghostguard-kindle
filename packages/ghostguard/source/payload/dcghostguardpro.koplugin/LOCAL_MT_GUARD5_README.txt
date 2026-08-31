DCPRO GhostGuard LOCAL MTGuard5
================================

LOCAL TEST ONLY — not pushed to GitHub.

Base:
  MTGuard4 Clean

MTGuard5 change:
  Uses the exact DCPRO GhostGuard cover approved by the user.
  Source aspect ratio: 960x1536 (5:8)
  Kindle library cover: 600x960 JPEG

Preserved unchanged:
- MT Guard 1 malformed-contact compatibility guard
- approved profile / learned regions
- classifier and Protect thresholds
- Adaptive Learning v3 + FAST_STRONG
- Auto Protect on KOReader start
- suspend/resume auto-protect lifecycle
- SimpleUI integration
- online license validation
- local reports under /mnt/us/GhostGuard_Reports/
- Cloud removed
- ZenUI removed
- native layer remains SHADOW_ONLY

KUAL installer behavior:
- FULL plugin replacement, preserving license.key
- installs exact approved cover to:
    /mnt/us/dcpro/ghostguard/assets/ghostguard_library_600x960.jpg
- rewrites launcher:
    /mnt/us/documents/DCPRO_GhostGuard.sh
  so '# Icon:' points to the installed JPEG
- removes:
    /mnt/us/documents/DCPRO_GhostGuard.sh.sdr
- touches/syncs launcher + cover to force Kindle Library re-index
- keeps learned profile data under /mnt/us/.dcpro_ghostguard/

If Kindle still displays an old cached thumbnail:
  KUAL > GhostGuard Local MTGuard5 > 3. Refresh approved icon
