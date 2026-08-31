-- Minimal regression simulation for goodix_crashshield.lua.
-- Runs without KOReader by mocking only the MTGuard5 methods/state the shield uses.

local shield_path = arg[1] or "packages/ghostguard/source/payload/dcghostguardpro.koplugin/goodix_crashshield.lua"
local CrashShield = assert(dofile(shield_path))

local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error((label or "assert_eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local GhostGuard = {}
GhostGuard.__index = GhostGuard

function GhostGuard:start(mode, _reason)
    assert_eq(self.config.protect_wrapper_all_modes, true, "shield forces wrapper in all modes")
    self.protect_enabled = mode == "PROTECT_PROFILE"
    self.protect_wrapper_installed = true
    return true, "mock-session"
end

function GhostGuard:recordRuntimeFault(_stage, _err)
    error("original recordRuntimeFault must not be called by shield test")
end

function GhostGuard:applyProtectionDecision(_input, _decision)
    self.protect_enabled = false
    return true
end

local installed, detail = CrashShield.install(GhostGuard)
assert(installed, tostring(detail))

local actions = {}
local session = {
    writeAction = function(_self, _event, action, reason)
        actions[#actions + 1] = action .. ":" .. tostring(reason)
    end,
    flush = function() end,
}
local storage = {
    writeAtomic = function(_self, _path, _content) return true end,
}
local observer = {
    setProtectEnabled = function(_self, enabled) assert_eq(enabled, false, "fault disables blocking") end,
}

local detector = {
    active_contacts = {},
    previous_tap = {},
    contact_count = 0,
}
function detector:getContact(slot) return self.active_contacts[slot] end
function detector:dropContact(contact)
    self.active_contacts[contact.slot] = nil
    if self.contact_count > 0 then self.contact_count = self.contact_count - 1 end
end

local new_frame_calls = 0
local input = {
    MTSlots = {},
    gesture_detector = detector,
    newFrame = function(self)
        new_frame_calls = new_frame_calls + 1
        self.MTSlots = {}
    end,
}

local guard = setmetatable({
    config = { data_dir = "/tmp", protect_wrapper_all_modes = false },
    protect_enabled = false,
    protect_wrapper_installed = false,
    protect_stats = {},
    session = session,
    storage = storage,
    observer = observer,
    input = input,
    bridge = { wrapper = function() end },
    wrapper_mode = "NONE",
}, GhostGuard)

-- 1) A NEW Goodix slot missing Y must be deferred even in Observe-Only.
input.MTSlots = { { slot = 1, id = 77, x = 100, y = nil } }
local deferred = guard:guardMalformedMtFrame(input, { type = 0, code = 0 })
assert_eq(deferred, 1, "missing-y frame deferred")
assert_eq(#input.MTSlots, 0, "missing-y frame removed before GestureDetector")
assert_eq(guard.protect_stats.mt_guard_deferred, 1, "defer stat")

-- 2) A stale established contact with nil initial_tev must be dropped before a
-- new buddy slot can snapshot it and crash KOReader two-finger gesture math.
detector.active_contacts[0] = {
    slot = 0,
    current_tev = { slot = 0, id = 55, x = 10, y = 20, timev = 1 },
    initial_tev = nil,
}
detector.contact_count = 1
input.MTSlots = { { slot = 1, id = 88, x = 30, y = 40 } }
deferred = guard:guardMalformedMtFrame(input, { type = 0, code = 0 })
assert_eq(deferred, 0, "healthy new buddy admitted")
assert_eq(detector.active_contacts[0], nil, "corrupt buddy contact dropped")
assert_eq(guard.protect_stats.mt_guard_corrupt_contacts, 1, "corrupt contact stat")

-- 3) If stock KOReader still throws, blocking fails open but the wrapper stays
-- installed and GestureDetector state is cleared for the next input frame.
detector.active_contacts[2] = {
    slot = 2,
    current_tev = { slot = 2, id = 99, x = 50, y = 60, timev = 2 },
    initial_tev = { slot = 2, id = 99, x = 50, y = 60, timev = 2 },
}
detector.contact_count = 1
input.MTSlots = { { slot = 2, id = 99, x = 50, y = 60 } }
guard.protect_enabled = true
local wrapper_before = guard.bridge.wrapper
local fault_ok = guard:recordRuntimeFault("KOReader_HANDLE_TOUCH", "gesturedetector.lua: y nil")
assert_eq(fault_ok, false, "touch parser fault reported as recovered fail-open")
assert_eq(guard.protect_enabled, false, "blocking disabled after parser fault")
assert_eq(guard.bridge.wrapper, wrapper_before, "crash shield wrapper retained")
assert_eq(guard.protect_wrapper_installed, true, "wrapper still installed")
assert_eq(guard.wrapper_mode, "PASS_THROUGH_SAFE", "wrapper enters safe pass-through")
assert_eq(detector.active_contacts[2], nil, "gesture contacts reset")
assert_eq(new_frame_calls, 1, "input frame reset")
assert_eq(guard.protect_stats.touch_shield_catches, 1, "catch stat")

-- 4) Observe/Calibration also get the pass-through crash boundary.
guard.config.protect_wrapper_all_modes = false
guard.protect_wrapper_installed = false
local start_ok = guard:start("OBSERVE_ONLY", "unit-test")
assert(start_ok)
assert_eq(guard.config.protect_wrapper_all_modes, true, "all-mode shield enabled")
assert_eq(guard.wrapper_mode, "PASS_THROUGH_SAFE", "observe wrapper mode")

print("Goodix crash shield regression simulation: PASS")
