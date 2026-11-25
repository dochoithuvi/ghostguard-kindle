#!/bin/sh
# Static source checks, not a hardware or KOReader runtime test.
set -eu
BASE=packages/ghostguard/source/payload/dcghostguardpro.koplugin
sh -n experiments/zenos/boot-launch.sh
grep -F 'self:startupDelay(start_mode, start_reason)' "$BASE/main.lua"
grep -F 'and not self.guard:isSafeMode()' "$BASE/main.lua"
grep -F 'self:expireZenCandidates()' "$BASE/adaptive_bootstrap.lua"
grep -F 'ZEN_EARLY_PROTECT' "$BASE/main.lua"
grep -F 'DISABLE_GHOSTGUARD_ZEN_BOOT' experiments/zenos/boot-launch.sh
grep -F 'Already attempted this boot' experiments/zenos/boot-launch.sh
! grep -Eq '^[[:space:]]*respawn' experiments/zenos/ghostguard-zenos.conf.template
echo "ZenOS static checks passed"

! grep -Ei 'simpleui|sui_window' "$BASE/main.lua"
[ ! -e "$BASE/simpleui_bridge.lua" ]
grep -F 'ZEN_REALTIME_STRIP' "$BASE/touch_observer.lua"
if command -v lua >/dev/null 2>&1; then lua experiments/zenos/test-realtime.lua; else echo "Lua tests NOT RUN: lua missing"; fi
