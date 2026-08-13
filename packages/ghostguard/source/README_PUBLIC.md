# DCPRO GhostGuard v0.6.0 RC — License Sync branch

This RC is based on the v0.5.1 HF3/ExitTrace runtime and adds signed online license registry support.
It does **not** claim the later Adaptive/TouchMap runtime is merged yet.

License v4.1:
- RSA local `license.key` remains supported.
- Signed `licenses.json` + `licenses.sig` may activate/renew/revoke by hashed Kindle serial.
- Raw serials and customer names are not published in the registry.
- Network sync happens outside the raw touch event hot path.
- STOP and SAFE_MODE remain available on any license failure.

# DCPRO GhostGuard — public v4 integration preview

KPM package ID: `ghostguard`

Install target after repository publication: `;kpm install ghostguard`

## Security model
- Per-device `license.key`.
- RSA-3072 / SHA-256 / PKCS#1 v1.5 signature.
- `.kpkg` and public repository contain only the RSA public key.
- Private issuer key is offline-only and is excluded by `.gitignore`.
- v3 licenses are intentionally incompatible and must be re-issued.
- No private Cloud token is bundled in this public payload.

## Runtime behavior
The plugin can load its diagnostics/status UI without a valid license, but operational Learning/Observe/Protect START requires a valid v4 key. Runtime license invalidation remains fail-open: protection is disabled/stopped rather than trapping touch input. STOP and SAFE_MODE are not license-gated.

## Source note
This preview patches the available Kindle v0.5.1 HF3 runtime. Merge `license_crypto.lua`, `license_manager.lua`, `keys/`, and the KPM/public-security changes into the latest Adaptive/TouchMap v0.5.x source before declaring the final official release.
