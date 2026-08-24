# GhostGuard Native 0.2.1

- keeps the Passive Watch behavior from 0.2.0 unchanged
- installs a `DCPRO GhostGuard Native` launcher into the Kindle Library/Home
- reuses the existing DCPRO GhostGuard icon artwork already shipped by the stable Kindle package
- launcher opens the Native Mesquite app directly; users no longer need to type `;kpm launch ghostguard-native` for normal use
- `;kpm launch ghostguard-native` remains available as a fallback/test path
- uninstall removes the Native Library launcher and its private artwork directory
- GhostGuard KOReader 0.6.17, KindleForge, OneClick and legacy manifests remain untouched

Upgrade an existing Native installation with `;kpm upgrade`.
