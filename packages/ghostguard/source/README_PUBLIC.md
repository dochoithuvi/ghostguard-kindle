# DCPRO GhostGuard 0.9.2 — Public Kindle Build

GhostGuard 0.9.2 is the public promotion of the field-tested MTGuard5 runtime.

## Included

- KOReader GhostGuard plugin
- MT Guard malformed-new-contact compatibility layer
- Adaptive Learning V3 with atomic automatic profile promotion
- SimpleUI integration
- persistent fail-open service and passive native shadow observer
- approved 600x960 Library cover (stored as base64 source and decoded at build time)
- KPM install/uninstall scripts

## Removed in 0.9.2

- Cloud upload runtime/outbox
- ZenUI integration
- Library-indexed continuous-learning report files

Reports now live under:

```text
/mnt/us/GhostGuard_Reports/
```

## Safety boundary

Native system-wide blocking is **not** enabled in this package.

```text
NATIVE_FILTER=SHADOW_ONLY
INPUT_GRAB=OFF
EVENT_INJECTION=OFF
FAIL_OPEN=YES
```

Actual touch suppression remains in the tested KOReader protection path.

## Version

```text
0.9.2
mtguard5-adaptive-v3-stable
```

See `RELEASE_NOTES_0.9.2.md` for field-qualification notes.
