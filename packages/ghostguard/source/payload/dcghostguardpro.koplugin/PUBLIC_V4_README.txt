DCPRO GhostGuard public-v4 integration preview

SOURCE BASIS
- Runtime payload: Kindle v0.5.1 Hotfix3 ExitTrace CopyToPlugins.
- Change scope: license verifier + public KPM packaging + removal of embedded private Cloud credentials.
- This preview does NOT claim to include the later TouchMap Beta code; merge these licensing files into the latest v0.5.x engine before the final public release.

LICENSE V4
- RSA-3072 public-key signatures, SHA-256, PKCS#1 v1.5.
- Fixed canonical field order.
- key_id supports future public-key rotation.
- libcrypto verification through KOReader LuaJIT FFI; no openssl CLI required.
- v3 licenses are rejected.

FAIL-OPEN
- Missing/invalid/expired license blocks operational START.
- Runtime recheck remains controlled by license_recheck_seconds (30s in the base build).
- STOP and SAFE_MODE remain available.
