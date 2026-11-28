# Maintainer signing notes

The production update key is separate from the DCPRO licensing key. Keep the private key offline and never commit it, upload it to a public release, or include it in any installer. The public trust anchor is embedded in OneClick as IntentShield_UPDATE_RC.pub (legacy filename).

The current Stable sequence is 12010. A future update must have a strictly increasing sequence and matching update-version.txt, with the fixed 23-file plugin layout and protected core/gesture/license files unchanged. For incompatible changes, ship a trusted OneClick instead.

Create the five-line ASCII manifest with a trailing newline:
```
DCPRO-UPDATE-1
sequence=<new integer>
version=<version>
sha256=<64 lowercase hex digits of plugin ZIP>
bytes=<exact plugin ZIP byte size>
```
Sign on the maintainer's trusted computer:
```sh
openssl dgst -sha256 -sign update-private.pem -out IntentShield_UPDATE.sig IntentShield_UPDATE.manifest
```
Publish the manifest, signature and plugin ZIP together only after testing. The private key is not present in this repository. See README for client limitations.
