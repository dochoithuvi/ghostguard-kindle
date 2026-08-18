# KindleForge KPM repack

This package repacks the user-supplied `KindleForge.zip` as a KPM package without modifying GhostGuard.

Upstream project: `KindleTweaks/KindleForge`

Application ID: `xyz.penguins184.kindleforge`

Displayed version: `4.1.0 stable`

The supplied ZIP was compared against upstream Git objects. Its ARM binaries and fonts match the upstream v4.1.0 payload exactly. Text files differ only by line endings except `script.js`, whose normalized content matches the later pinned upstream commit below.

Pinned payload sources used by the artifact builder:

- v4.1.0 tag for `config.xml`, `index.html`, `style.css`, `assets/*`, `KFPM`, `UtildHF`, and `UtildSF`.
- commit `64c8e264a01277f622c32340bc448c4f1f0e7822` for `script.js`, matching the supplied ZIP after CRLF normalization.

Important supplied-ZIP SHA-256 values:

- `KFPM`: `bbeb0ab7ee0b6d9acdfe6b6a3cc47634b75fd613449934356dc1f8458ecb6d7b`
- `UtildHF`: `c939d37262ac7b324e8deaa463a9c8152e7ceb55004f01e0511005c8661854d9`
- `UtildSF`: `a8a44e0f6c7f4869d0574197df9a304dbd25035d6fc45156f7431bcb8d72a9f8`
- `inter.ttf`: `0be2399ea925f1f83ff974764761da9860ec50742ed29a5d4c1ffd0c5c7ac3a8`
- `libre-baskerville.ttf`: `2101302538d9e88adb679031c04623e4578b5745e89566284fd2c508d79acae0`

Normalized text SHA-256 values used for reproducibility checks:

- `config.xml`: `44fc88b4f1d93c8486c9797756558c29a535fff720209a26929294489fdc45e0`
- `index.html`: `a42ddd5a8a983c3cfa3f3a2672e1beffd907176ece4024cbd6ceec135ec69d27`
- `script.js`: `2fe81dba2b2feaae4dbafd3d585e5fde363740812fcb7e82943ab7130f5272fc`
- `style.css`: `35ea472c025dac11ab2633c76c4a7f26a294a3424d45085c9f33255f79f66395`
- `assets/polyfill.js`: `e466d7d47e677c4cac0ee84525d49f33c5ed97350a05e0d4a96497344123abf9`

The KPM package installs the WAF under `/var/local/mesquite/KindleForge`. Unlike the original standalone installer, it does not copy Utild into `/var/local/kmc`; the correct Utild binary is launched from the isolated KindleForge directory instead. This avoids modifying KPM's own shared installation directory.
