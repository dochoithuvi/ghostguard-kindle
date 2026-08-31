# DCPRO GhostGuard 0.9.2

GhostGuard is a KOReader touch-protection plugin for Kindle devices with intermittent ghost-touch / malformed multi-touch input.

## 0.9.2 stable runtime

This release promotes the field-tested MTGuard5 runtime to public 0.9.2.

### Protection path

- Existing approved profile remains the source of coordinate-region confidence.
- MT Guard rejects only malformed **new** multi-touch contacts before KOReader creates an invalid GestureDetector contact.
- Established KOReader contacts are not dropped by MT Guard.
- Existing GhostGuard classifier and Protect thresholds remain unchanged from the tested MTGuard5 build.
- Runtime failures fail open.

### Continuous learning

Adaptive Learning V3 remains active while Protect is running.

New suspicious regions are tracked first and are promoted only after sufficient evidence.
A narrow `FAST_STRONG` path exists for repeated, short, high-score, axis-incomplete ghost contacts.

Automatic promotions are written atomically to the approved profile and are used immediately by future Protect decisions.

Reports are kept outside Kindle Library indexing:

```text
/mnt/us/GhostGuard_Reports/ContinuousLearning_Status.txt
/mnt/us/GhostGuard_Reports/ContinuousLearning_Changes.log
/mnt/us/GhostGuard_Reports/ActiveProfile_AutoLearned.txt
```

### UI cleanup

- SimpleUI integration is retained.
- Cloud upload runtime is removed.
- ZenUI integration is removed.
- Customer-setup-only Tools entries are not exposed.
- GhostGuard Library launcher uses the approved 600x960 cover and forces a clean re-index on install.

### Sleep / wake

If Auto Protect is enabled and an approved profile exists, GhostGuard stops fail-open on suspend and restores Protect after wake.
The persistent native service remains observation-only:

```text
NATIVE_FILTER=SHADOW_ONLY
INPUT_GRAB=OFF
EVENT_INJECTION=OFF
FAIL_OPEN=YES
```

## Privacy

GhostGuard 0.9.2 does not upload reports to Cloud.
Runtime reports and learned profiles stay on the Kindle unless the user manually copies them.
