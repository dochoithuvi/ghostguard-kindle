-- DCPRO GhostGuard runtime wrapper v0.9.
--
-- The protection engine remains in ghostguard_core.lua. v0.9 keeps a fail-open
-- system-service bridge around the existing KOReader engine. The external
-- service owns boot/sleep/wake/controller lifecycle only; it never grabs or
-- injects input. Actual suppression remains in the tested KOReader wrapper.
--
-- Build compatibility anchors kept intentionally for package validators; the
-- real implementations remain in ghostguard_core.lua:
-- local bridge_ok, bridge_err = self:ensureInputBridge()
-- CALIBRATION_INPUT:
-- Readiness already includes the minimum cumulative learning time
-- and self.profiles:isCalibrationReady() then

local source = debug.getinfo(1, "S").source or ""
local plugin_dir = source:sub(1, 1) == "@" and source:sub(2):match("(.*/)") or nil
if not plugin_dir then
    error("DCPRO GhostGuard: cannot resolve plugin directory")
end

local GhostGuard = dofile(plugin_dir .. "ghostguard_core.lua")
if type(GhostGuard) ~= "table" or type(GhostGuard.onRawEvent) ~= "function" then
    error("DCPRO GhostGuard: ghostguard_core.lua is invalid")
end

local SystemService = nil
do
    local ok, result = pcall(dofile, plugin_dir .. "system_service.lua")
    if ok and type(result) == "table" then SystemService = result end
end

local core_new = GhostGuard.new
local core_onRawEvent = GhostGuard.onRawEvent
local core_start = GhostGuard.start
local core_stop = GhostGuard.stop
local core_set_auto = GhostGuard.setAutoProtectEnabled
local core_complete_setup = GhostGuard.completeCustomerSetup
local core_status = GhostGuard.statusText
local core_set_safe = GhostGuard.setSafeMode

local function service_for(guard)
    return guard and guard.system_service or nil
end

local function controller_safe(guard)
    local service = service_for(guard)
    if not service then return true end
    local ok, safe, detail = pcall(service.controllerSafe, service)
    if not ok then return true end -- service faults must always fail open
    return safe ~= false, detail
end

local function mark_state(guard, state, detail)
    local service = service_for(guard)
    if not service then return end
    pcall(service.markKOReader, service, state, guard.mode or "NONE", detail)
end

local function resume_retry_delays(guard)
    local configured = guard.config and guard.config.system_service_resume_retry_delays
    if type(configured) == "table" and #configured > 0 then return configured end
    return { 2, 4, 8, 12 }
end

local function schedule_resume_retry(guard, mode, attempt, last_error)
    if guard._v080_resume_retry_scheduled then return end
    local delays = resume_retry_delays(guard)
    if attempt > #delays then
        mark_state(guard, "RESUME_RETRY_EXHAUSTED", last_error or "unknown")
        return
    end
    local ui_ok, UIManager = pcall(require, "ui/uimanager")
    if not ui_ok or not UIManager or type(UIManager.scheduleIn) ~= "function" then
        mark_state(guard, "RESUME_RETRY_UNAVAILABLE", last_error or "UIManager unavailable")
        return
    end
    local delay = tonumber(delays[attempt]) or 2
    guard._v080_resume_retry_scheduled = true
    UIManager:scheduleIn(delay, function()
        guard._v080_resume_retry_scheduled = false
        if guard.running or guard:isSafeMode() then return end
        local safe, detail = controller_safe(guard)
        if not safe then
            mark_state(guard, "CONTROLLER_CHANGED_FAIL_OPEN", detail)
            return
        end
        local ok, result = core_start(guard, mode, "resume-service-retry-" .. tostring(attempt))
        if ok then
            guard._v080_resume_retry_attempt = 0
            mark_state(guard, "ACTIVE", "resume retry succeeded")
            return
        end
        guard._v080_resume_retry_attempt = attempt
        mark_state(guard, "RESUME_RETRY", tostring(result))
        schedule_resume_retry(guard, mode, attempt + 1, tostring(result))
    end)
end

function GhostGuard:new(config, ...)
    local obj = core_new(self, config, ...)
    if SystemService and obj and not obj.system_service then
        local ok, service = pcall(SystemService.new, SystemService, config)
        if ok then
            obj.system_service = service
            pcall(service.consumeResumeRequest, service)
            pcall(service.markKOReader, service, "LOADED", obj.mode or "NONE", "runtime v0.9 loaded")
        end
    end
    return obj
end

function GhostGuard:setAutoProtectEnabled(enabled, internal_failsafe)
    local ok, result = core_set_auto(self, enabled, internal_failsafe)
    if ok and self.system_service then
        pcall(self.system_service.setDesired, self.system_service, enabled == true,
            enabled and self.config.protect_mode or "AUTO")
    end
    return ok, result
end

function GhostGuard:completeCustomerSetup()
    local ok, result = core_complete_setup(self)
    if ok and self.system_service then
        -- A freshly approved/relearned profile is the explicit acknowledgement
        -- path after a real controller change.
        pcall(self.system_service.acknowledgeController, self.system_service)
        pcall(self.system_service.setDesired, self.system_service, true, self.config.protect_mode)
        mark_state(self, "PROFILE_APPROVED", "Auto Protect enabled")
    end
    return ok, result
end

function GhostGuard:setSafeMode(enabled)
    local ok, result = core_set_safe(self, enabled)
    if ok and enabled and self.system_service then
        pcall(self.system_service.setDesired, self.system_service, false, "SAFE_MODE")
        mark_state(self, "SAFE_MODE", "user enabled SAFE_MODE")
    end
    return ok, result
end

function GhostGuard:start(mode, reason)
    local automatic_protect = mode == self.config.protect_mode
        and (tostring(reason or ""):find("auto", 1, true)
            or tostring(reason or ""):find("resume", 1, true)
            or tostring(reason or ""):find("service", 1, true))

    if mode == self.config.protect_mode then
        local safe, detail = controller_safe(self)
        if not safe then
            local message = "SYSTEM_SERVICE: controller fingerprint changed; fail-open; relearn/approve profile before Protect (" .. tostring(detail) .. ")"
            self.last_error = message
            mark_state(self, "CONTROLLER_CHANGED_FAIL_OPEN", message)
            return false, message
        end
    end

    local ok, result = core_start(self, mode, reason)
    if ok then
        self._v080_resume_retry_attempt = 0
        mark_state(self, "ACTIVE", tostring(reason or "start"))
        return ok, result
    end

    if automatic_protect and tostring(reason or ""):find("resume", 1, true) then
        self._v080_resume_retry_attempt = 1
        mark_state(self, "RESUME_RETRY_PENDING", tostring(result))
        schedule_resume_retry(self, mode, 1, tostring(result))
    end
    return ok, result
end

function GhostGuard:stop(reason)
    if tostring(reason or "") == "suspend-fail-open" then
        mark_state(self, "SUSPENDING", "Protect paused; desired state preserved")
    end
    local ok, result = core_stop(self, reason)
    if tostring(reason or "") == "suspend-fail-open" then
        mark_state(self, "SUSPENDED", "waiting for wake")
    elseif ok then
        mark_state(self, "STOPPED", tostring(reason or "stop"))
    end
    return ok, result
end

function GhostGuard:statusText(...)
    local base = core_status(self, ...)
    if not self.system_service then
        return tostring(base or "GhostGuard") .. "\nSystem service v0.9: unavailable; KOReader protection remains fail-open."
    end
    local ok, text = pcall(self.system_service.statusText, self.system_service)
    if not ok then text = "System service v0.9: status unavailable (fail-open)." end
    return tostring(base or "GhostGuard") .. "\n" .. tostring(text)
end

function GhostGuard:onRawEvent(event)
    if self.running and self.observer_enabled and self.observer then
        local wall_now = os.time()
        local call_ok, licensed, detail = pcall(self.licenseValid, self, false)

        -- Keep this timestamp only for diagnostics. LicenseManager owns the
        -- actual 30-second cache and deliberately refuses to reuse it when
        -- os.time() moves backwards.
        self.last_license_check_wall = wall_now

        if not call_ok then
            local err = "License watchdog error: " .. tostring(licensed)
            self.last_error = err
            if type(self.recordRuntimeFault) == "function" then
                pcall(self.recordRuntimeFault, self, "LICENSE_WATCHDOG", err)
            end
            pcall(self.stop, self, "license-watchdog-error")
            return
        end

        if not licensed then
            self.last_error = "License failsafe: " .. tostring(detail)
            if self.session then
                pcall(self.session.writeAction, self.session,
                    { timestamp_us = wall_now * 1000000, slot = -1, tracking_id = -1 },
                    "LICENSE_FAILSAFE_STOP", self.last_error)
                pcall(self.session.flush, self.session)
            end
            pcall(self.setAutoProtectEnabled, self, false, true)
            pcall(self.stop, self, "license-invalid")
            return
        end
    end

    return core_onRawEvent(self, event)
end

return GhostGuard
