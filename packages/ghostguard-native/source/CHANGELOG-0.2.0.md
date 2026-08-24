# GhostGuard Native 0.2.0

- adds short-lived passive read-only `/dev/input/event*` capture
- automatically selects a likely readable touchscreen candidate
- records raw evdev bytes for controller/path validation
- refreshes capture output in the Mesquite panel
- keeps Protect, input grab and event injection disabled
- leaves GhostGuard KOReader 0.6.17 and KindleForge unchanged

Upgrade path for an existing Native 0.1.0 installation: `;kpm upgrade`.
