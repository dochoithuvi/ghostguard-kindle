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
