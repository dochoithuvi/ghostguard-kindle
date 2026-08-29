# GhostGuard Native Guarded Micro-Grab v2.1 TEST

One 30-minute qualification build for a jailbroken Kindle touchscreen.

## Why this version

Previous on-device testing established that long-lived `EVIOCGRAB + uinput` is not suitable on this Kindle. Passive evdev observation remains useful, while reactive blocking showed promise but the previous 160 ms / repeat-3 short-grab test was too aggressive to qualify safely.

## Test structure

### Phase A — first 10 minutes

- PASSIVE ONLY
- ZERO `EVIOCGRAB`
- ZERO uinput
- collect a clean baseline while reading normally

### Phase B — final 20 minutes

Active mode is allowed only if Phase A collected at least:

- `RAW_EVENTS >= 150`
- `COMPLETED_CONTACTS >= 15`

Strict trigger:

- exactly X-only or Y-only
- same 2% one-dimensional bin
- repeat >= 4 inside 500 ms
- duration <= 60 ms
- `touch_major <= 15`
- path <= 20 raw units

Response:

- `EVIOCGRAB` opens a 60 ms burst-acquisition window
- if no contact starts, ungrab at 60 ms
- if a contact starts, swallow the whole contact through `TRACKING_ID` end
- hard contact-boundary cap: 750 ms
- explicit ungrab
- cooldown 3 seconds

## Safety

- complete X+Y contacts never trigger a grab
- no-X/no-Y contacts never trigger a grab
- grab begins only after the triggering contact has ended
- active contact count must be zero before grabbing
- max 6 successful grabs in the whole 30-minute session
- if a micro-grab catches a complete contact, active blocking is disabled for the rest of the session
- if a swallowed contact cannot close inside the 750 ms boundary cap, active blocking is disabled for the rest of the session
- no uinput
- no long-lived grab
- no autostart
- atomic singleton lock with stale-lock recovery
- heartbeat + incremental report every ~5 seconds
- independent 30m30s watchdog
- process exit releases `EVIOCGRAB`
- emergency rescue marker

## KUAL test

Install the packaged extension at:

`/mnt/us/extensions/ghostguard-native-guarded-micrograb`

Then run:

1. `Preflight - ZERO Grab`
2. `ONE QUALIFICATION - 30 min`

During the first 10 minutes actively read, turn pages, open menus, and change font/layout/spacing/margins. Continue normal reading for the remaining 20 minutes and allow natural ghost touch to occur if possible.

If the touchscreen behaves abnormally, use Emergency Rescue if possible; otherwise reboot. Do not rerun before reviewing the report.

## Key pass conditions

- first 10 minutes remains responsive
- `BASELINE_PASS=YES`
- `BOUNDARY_CAP_HITS=0`
- `GRAB_HIT_COMPLETE_CONTACTS=0`
- no persistent touch freeze
- if a ghost burst occurs, `ARMED_TRIGGERS` / `GRAB_SUCCEEDED` may increase

This is a qualification prototype only. Do not install it as an autostart service.
