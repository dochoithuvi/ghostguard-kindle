# GhostGuard 0.9.2

0.9.2 promotes the locally field-tested MTGuard5 runtime to the public Kindle package.

## Highlights

- Malformed-new-contact MT Guard for KOReader's multi-touch path.
- Adaptive Learning V3 with automatic atomic promotion of newly confirmed ghost regions.
- Approved profile remains live across sessions and receives promoted regions without relearning from scratch.
- Auto Protect survives normal KOReader restart and restores after suspend/resume.
- Reports moved to `/mnt/us/GhostGuard_Reports/` so they no longer appear as Kindle Library documents.
- Cloud upload and ZenUI runtime removed.
- Approved DCPRO GhostGuard 600x960 Library cover installed with forced re-index.
- SimpleUI Tools integration retained.
- Native service remains `SHADOW_ONLY`; no EVIOCGRAB/uinput/injection.

## Field qualification used for promotion

The final MTGuard5 test data showed:

- Continuous learning active with automatic profile updates.
- `PROMOTED_REGIONS=3`.
- Approved profile grew to 7 regions.
- A confirmed `FAST_STRONG` promotion for a repeated axis-incomplete region.
- Multiple `resume-auto-protect` sessions after suspend.
- No new GhostGuard/KOReader Lua crash after the MTGuard5 runtime was active.
- One conservative circuit-breaker fail-open during a dense blocked burst; later sessions recovered through normal resume. The tested breaker threshold is intentionally unchanged in 0.9.2.

## Safety

```text
NATIVE_FILTER=SHADOW_ONLY
INPUT_GRAB=OFF
EVENT_INJECTION=OFF
FAIL_OPEN=YES
```
