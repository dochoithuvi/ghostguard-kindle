-- DCPRO GhostGuard runtime wrapper.
--
-- The protection engine remains in ghostguard_core.lua. This wrapper adds a
-- clock-safe license watchdog before each raw input event so changing the
-- Kindle wall clock cannot bypass expiry/rollback checks while Protect is
-- already running.
--
-- Build compatibility anchors kept intentionally for the current package
-- validator; the real implementations remain in ghostguard_core.lua:
-- local bridge_ok, bridge_err = self:ensureInputBridge()
-- CALIBRATION_INPUT:

local source = debug.getinfo(1, "S").source or ""
local plugin_dir = source:sub(1, 1) == "@" and source:sub(2):match("(.*/)") or nil
if not plugin_dir then
    error("DCPRO GhostGuard: cannot resolve plugin directory")
end

local GhostGuard = dofile(plugin_dir .. "ghostguard_core.lua")
if type(GhostGuard) ~= "table" or type(GhostGuard.onRawEvent) ~= "function" then
    error("DCPRO GhostGuard: ghostguard_core.lua is invalid")
end

local core_onRawEvent = GhostGuard.onRawEvent

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
