#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/packages/ghostguard/source"
OUT="$ROOT/packages/ghostguard/artifacts"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$SRC/manifest.json" | head -1 | tr -d ' ' | tr ',' '.')
[ -n "$VERSION" ] || VERSION=0.6.16
PKG="$OUT/ghostguard_${VERSION}_kindle5-kindlepw2-kindlehf.kpkg"
rm -f "$PKG"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/payload" "$TMP/scriptlets" "$TMP/assets"
cp "$SRC/manifest.json" "$TMP/manifest.json"
cp -R "$SRC/payload/dcghostguardpro.koplugin" "$TMP/payload/"
# Idempotent repair for legacy 0.6.11 source. If the source is already on the
# current bridge implementation, leave it untouched instead of failing the build.
python3 - "$TMP/payload/dcghostguardpro.koplugin/main.lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("\nend    return true\nend\n", "\nend\n", 1)
old = '''    -- 0.6.11 SAFE DIAGNOSTIC: SimpleUI/ZenUI bridges intentionally disabled.\n    local ok, guard_or_err = pcall(GhostGuard.new, GhostGuard, config, Storage, TouchObserver,\n        ProfileManager, LicenseManager, CloudManager, plugin_dir)\n    if not ok then return false, "GhostGuard:new: " .. tostring(guard_or_err) end\n    self.config, self.guard = config, guard_or_err\n'''
new = '''    local ok, guard_or_err = pcall(GhostGuard.new, GhostGuard, config, Storage, TouchObserver,\n        ProfileManager, LicenseManager, CloudManager, plugin_dir)\n    if not ok then return false, "GhostGuard:new: " .. tostring(guard_or_err) end\n    self.config, self.guard = config, guard_or_err\n\n    -- SimpleUI and ZenUI integrations are optional UI bridges. Never fail\n    -- GhostGuard runtime if either host UI is absent or exposes an older API.\n    local SimpleUIBridge, bridge_err = load_local("simpleui_bridge.lua")\n    if SimpleUIBridge then\n        local bridge_ok, bridge_obj = pcall(SimpleUIBridge.new, SimpleUIBridge, self, plugin_dir)\n        if bridge_ok then\n            self.simpleui = bridge_obj\n        else\n            logger.warn("DCPRO GhostGuard SimpleUI bridge init failed:", bridge_obj)\n        end\n    else\n        logger.info("DCPRO GhostGuard SimpleUI bridge unavailable:", bridge_err)\n    end\n    local ZenUIBridge, zen_err = load_local("zenui_bridge.lua")\n    if ZenUIBridge then\n        local zen_ok, zen_obj = pcall(ZenUIBridge.new, ZenUIBridge, self, plugin_dir)\n        if zen_ok then\n            self.zenui = zen_obj\n        else\n            logger.warn("DCPRO GhostGuard ZenUI bridge init failed:", zen_obj)\n        end\n    else\n        logger.info("DCPRO GhostGuard ZenUI bridge unavailable:", zen_err)\n    end\n'''
if old in s:
    s = s.replace(old, new, 1)
s = s.replace('    -- 0.6.11 SAFE DIAGNOSTIC: no SimpleUI/ZenUI bridge instances.\n    self.simpleui = nil\n    self.zenui = nil\n', '', 1)
open(p, "w", encoding="utf-8").write(s)
PY
# Idempotent Protect fix. If the source is already repaired, keep it.
python3 - "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '''    -- 0.6.11 SAFE DIAGNOSTIC: do not attach to Device.input at all.\n    self.observer_enabled = false\n    self.hook_installed = false\n    self.input = nil\n    self.bridge = nil\n    local protect = mode == self.config.protect_mode    local protect = mode == self.config.protect_mode\n    local calibrate = mode == self.config.calibration_mode\n'''
new = '''    -- Observe/Calibration remain safe without a touch wrapper. Real Protect\n    -- mode, however, needs the raw-event bridge before installing the wrapper.\n    -- The old SAFE diagnostic cleared self.input/self.bridge and then called\n    -- ensureProtectWrapper(), which deterministically returned:\n    -- "PROTECT_WRAPPER: input bridge unavailable".\n    self.observer_enabled = false\n    self.hook_installed = false\n    self.input = nil\n    self.bridge = nil\n    local protect = mode == self.config.protect_mode\n    local calibrate = mode == self.config.calibration_mode\n'''
if old in s:
    s = s.replace(old, new, 1)
old2 = '''    if protect or self.config.protect_wrapper_all_modes == true then\n        self.protect_enabled = protect\n        local wrapper_ok, wrapper_err = self:ensureProtectWrapper()\n        if not wrapper_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(wrapper_err)\n        end\n        self.wrapper_mode = protect and "PROTECT" or "PASS_THROUGH"\n    end\n'''
new2 = '''    if protect or self.config.protect_wrapper_all_modes == true then\n        local bridge_ok, bridge_err = self:ensureInputBridge()\n        if not bridge_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(bridge_err)\n        end\n        self.protect_enabled = protect\n        local wrapper_ok, wrapper_err = self:ensureProtectWrapper()\n        if not wrapper_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(wrapper_err)\n        end\n        self.wrapper_mode = protect and "PROTECT" or "PASS_THROUGH"\n    end\n'''
if old2 in s:
    s = s.replace(old2, new2, 1)
open(p, "w", encoding="utf-8").write(s)
PY
# Keep package's internal version aligned with the repository manifest.
python3 - "$TMP/payload/dcghostguardpro.koplugin/defaults.lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
for old in ('0.6.13', '0.6.14', '0.6.16'):
    s = s.replace('version = "' + old + '"', 'version = "0.6.16"', 1)
open(p, "w", encoding="utf-8").write(s)
PY
cp "$SRC/install.sh" "$TMP/install.sh"
cp "$SRC/launch.sh" "$TMP/launch.sh"
cp "$SRC/scriptlets/DCPRO_GhostGuard.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
if [ -f "$SRC/assets/ghostguard_library_600x960.jpg" ]; then
  cp "$SRC/assets/ghostguard_library_600x960.jpg" "$TMP/assets/ghostguard_library_600x960.jpg"
fi
chmod +x "$TMP/install.sh" "$TMP/launch.sh" "$TMP/scriptlets/DCPRO_GhostGuard.sh"
for f in main.lua ghostguard.lua defaults.lua profile_manager.lua touch_observer.lua license_manager.lua keys/keyring.lua adaptive_bootstrap.lua simpleui_bridge.lua zenui_bridge.lua; do
  test -f "$TMP/payload/dcghostguardpro.koplugin/$f"
done
test -f "$TMP/manifest.json"
test -f "$TMP/scriptlets/DCPRO_GhostGuard.sh"
test -f "$TMP/assets/ghostguard_library_600x960.jpg"
! grep -q 'end    return true' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
grep -q 'SimpleUIBridge.new' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
! grep -q 'self.simpleui = nil' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
grep -q 'local bridge_ok, bridge_err = self:ensureInputBridge()' "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua"
! grep -q 'local protect = mode == self.config.protect_mode    local protect' "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua"
grep -q 'version = "0.6.16"' "$TMP/payload/dcghostguardpro.koplugin/defaults.lua"
grep -q 'runtime_revision = "calibration-flow-v2"' "$TMP/payload/dcghostguardpro.koplugin/defaults.lua"
grep -q 'CALIBRATION_INPUT:' "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua"
grep -q '_resume_calibration_after_suspend' "$TMP/payload/dcghostguardpro.koplugin/main.lua"
grep -q 'function ProfileManager:checkpoint()' "$TMP/payload/dcghostguardpro.koplugin/profile_manager.lua"
grep -q 'calibration_min_total_contacts = 40' "$TMP/payload/dcghostguardpro.koplugin/defaults.lua"
grep -q 'PROFILE_KIND=' "$TMP/payload/dcghostguardpro.koplugin/profile_manager.lua"
grep -q 'profile_kind == "BASELINE"' "$TMP/payload/dcghostguardpro.koplugin/profile_manager.lua"
# Regression: Calibration must receive real raw events without installing the Protect wrapper.
cat > "$TMP/test_calibration_runtime.lua" <<'LUA'
package.preload["device"] = function()
    local input = {
        handleTouchEv = function() return { "koreader-result" } end,
        registerEventAdjustHook = function(self, fn) self._test_hook = fn end,
    }
    return {
        model = "KindleBasic4",
        getModel = function() return "KindleBasic4" end,
        screen = { getWidth = function() return 1072 end, getHeight = function() return 1448 end },
        input = input,
    }
end
local root = os.getenv("GG_TEST_ROOT")
local config = dofile(root .. "/defaults.lua")
local TouchObserver = dofile(root .. "/touch_observer.lua")
local ProfileManager = dofile(root .. "/profile_manager.lua")
local GhostGuard = dofile(root .. "/ghostguard.lua")
local Device = require("device")

local Storage = {}; Storage.__index = Storage
function Storage:new() return setmetatable({ files = {} }, self) end
function Storage:ensureLayout() return true end
function Storage:archiveStaleMarker() return false end
function Storage:readFile(p) return self.files[p] end
function Storage:writeAtomic(p,v) self.files[p]=v; return true end
function Storage:removeExact(p) self.files[p]=nil; return true end
function Storage:touch(p,v) self.files[p]=v or ""; return true end
function Storage:fileExists(p) return self.files[p] ~= nil end
function Storage:isSafeMode() return false end
function Storage:openSession()
    local s = {}
    for _, n in ipairs({"writeCalibration","writeCandidate","writeEvent","writeContact","writeAction","flush"}) do s[n]=function() end end
    s.close=function() end
    return s
end
function Storage:prepareCloudOutbox() return false end
function Storage:setSafeMode() return true end

local License = {}; License.__index = License
function License:new() return setmetatable({}, self) end
function License:check() return true, "OK" end
function License:statusText() return "OK" end
function License:syncOnline() return true end
function License:activationHelp() return "" end
local Cloud = {}; Cloud.__index = Cloud
function Cloud:new() return setmetatable({}, self) end
function Cloud:statusText() return "OK" end
function Cloud:start() return true end
function Cloud:isBusy() return false end

local g = GhostGuard:new(config, Storage, TouchObserver, ProfileManager, License, Cloud, root)
local original_handle = Device.input.handleTouchEv
assert(g:start(config.calibration_mode, "ci-calibration"))
assert(g.hook_installed == true, "calibration did not install raw-event hook")
assert(type(Device.input._test_hook) == "function", "raw hook callback missing")
assert(Device.input.handleTouchEv == original_handle, "calibration must not replace handleTouchEv")
assert(g.protect_wrapper_installed == false, "calibration installed protect wrapper")

local hook = Device.input._test_hook
local t = os.time()
local function ev(tp, code, value, offset) hook(Device.input, { type=tp, code=code, value=value, time=t + offset }) end
for i=1,40 do
    local base = i * 0.01
    ev(3,47,0,base)
    ev(3,57,i,base+0.001)
    ev(3,53,300+(i%5),base+0.002)
    ev(3,54,500,base+0.003)
    ev(0,0,0,base+0.004)
    ev(3,57,-1,base+0.005)
    ev(0,0,0,base+0.006)
end
local st = g.profiles:calibrationStatus()
assert(st.total_contacts == 40, "completed touches were not counted: " .. tostring(st.total_contacts))
g.profiles.calibration.started_wall = os.time() - 180
st = g.profiles:calibrationStatus()
assert(st.baseline_ready == true, "baseline did not become ready")
local inputst = g:inputLearningStatus()
assert(inputst.raw_events > 0 and inputst.contact_ends == 40, "observer stats did not move")
assert(g:stop("ci-stop"))
assert(g.profiles.pending and g.profiles.pending.total_contacts == 40, "finalized progress missing")
print("CALIBRATION_RUNTIME_FLOW_PASS")
LUA
GG_TEST_ROOT="$TMP/payload/dcghostguardpro.koplugin" luajit "$TMP/test_calibration_runtime.lua" | grep -q CALIBRATION_RUNTIME_FLOW_PASS
tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh launch.sh scriptlets assets
# Sync patched runtime/config back into the source tree for reproducibility.
cp "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua" "$SRC/payload/dcghostguardpro.koplugin/ghostguard.lua"
cp "$TMP/payload/dcghostguardpro.koplugin/defaults.lua" "$SRC/payload/dcghostguardpro.koplugin/defaults.lua"
printf '%s\n' "$PKG"
