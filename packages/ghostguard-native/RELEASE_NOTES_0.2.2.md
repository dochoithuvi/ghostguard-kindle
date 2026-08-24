# GhostGuard Native 0.2.2

- fixes the first real-device launch issue where tapping the Native Library icon can immediately return to Kindle Home
- aligns the Native Mesquite widget capability/configuration envelope with the known-good KindleForge layout
- changes the widget version to the conventional `1.0` used by KindleForge while keeping the KPM package version at `0.2.2`
- adds Native-only launch diagnostics at `/mnt/us/.dcpro_ghostguard_native/launch.log`
- records Library launch, KPM launch, runtime start, watcher start and Mesquite exit status
- keeps Passive Watch read-only: no `EVIOCGRAB`, no `/dev/uinput`, no input injection and no touch filtering
- does not modify GhostGuard KOReader 0.6.17, KindleForge, OneClick or legacy manifests

Upgrade with `;kpm upgrade`, then retry the DCPRO GhostGuard Native Library icon. If it still returns to Home, collect `/mnt/us/.dcpro_ghostguard_native/launch.log`.
