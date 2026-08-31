-- DCPRO GhostGuard Goodix compatibility crash shield.
--
-- KindleBasic4 / Goodix panels can emit malformed MT protocol-B frames where a
-- slot appears before both coordinates are available. KOReader v2026.07.1 can
-- then keep a Contact with nil initial_tev/x/y and later crash in gesture math.
--
-- This layer is deliberately narrow:
--   * no EVIOCGRAB
--   * no /dev/uinput
--   * no event injection
--   * no profile/classifier threshold changes
--   * malformed-contact sanitation only
--   * KOReader parser exceptions are contained and reset instead of escaping
--
-- It patches the MTGuard5 class before ghostguard.lua captures the core methods.

local CrashShield = {}

local EV_SYN = 0
local SYN_REPORT = 0

local function now_us()
    return os.time() * 1000000
end

local function tev_has_xy(tev)
    return type(tev) == "table" and tev.x ~= nil and tev.y ~= nil
end

local function contact_is_sane(contact)
    if type(contact) ~= "table" then return false, "CONTACT_INVALID" end
    if not tev_has_xy(contact.current_tev) then return false, "CONTACT_CURRENT_MISSING_XY" end
    if not tev_has_xy(contact.initial_tev) then return false, "CONTACT_INITIAL_MISSING_XY" end
    if contact.initial_tev.timev == nil then return false, "CONTACT_INITIAL_MISSING_TIME" end
    if contact.current_tev.timev == nil then return false, "CONTACT_CURRENT_MISSING_TIME" end
    return true
end

local function log_action(guard, action, reason, tev, slot)
    if not guard or not guard.session then return end
    tev = type(tev) == "table" and tev or {}
    pcall(guard.session.writeAction, guard.session, {
        timestamp_us = now_us(),
        frame = -1,
        slot = tonumber(slot or tev.slot) or -1,
        tracking_id = tonumber(tev.id) or -1,
        score = 0,
        x = tev.x,
        y = tev.y,
    }, action, tostring(reason or "NONE"))
end

local function drop_contact(guard, detector, contact, reason)
    if type(contact) ~= "table" then return false end
    local slot = tonumber(contact.slot) or -1
    local tev = contact.current_tev
    local dropped = false
    if type(detector.dropContact) == "function" then
        local ok = pcall(detector.dropContact, detector, contact)
        dropped = ok
    elseif type(detector.active_contacts) == "table" and slot >= 0 then
        detector.active_contacts[slot] = nil
        if tonumber(detector.contact_count) and detector.contact_count > 0 then
            detector.contact_count = detector.contact_count - 1
        end
        dropped = true
    end
    if type(detector.previous_tap) == "table" and slot >= 0 then
        detector.previous_tap[slot] = nil
    end
    if dropped then
        guard.protect_stats.mt_guard_corrupt_contacts =
            (guard.protect_stats.mt_guard_corrupt_contacts or 0) + 1
        log_action(guard, "MT_GUARD_DROP_CORRUPT_CONTACT", reason, tev, slot)
    end
    return dropped
end

local function reset_gesture_state(guard, input, reason)
    input = input or (guard and guard.input)
    if not input then return false end
    local detector = input.gesture_detector
    if detector and type(detector.active_contacts) == "table" then
        local contacts = {}
        for _, contact in pairs(detector.active_contacts) do
            contacts[#contacts + 1] = contact
        end
        for _, contact in ipairs(contacts) do
            drop_contact(guard, detector, contact, "RESET_AFTER_TOUCH_PARSER_FAULT")
        end
        detector.previous_tap = {}
    end
    if type(input.newFrame) == "function" then
        pcall(input.newFrame, input)
    end
    if guard then
        guard.pending_frame_decision = nil
        guard.protect_stats.touch_shield_resets =
            (guard.protect_stats.touch_shield_resets or 0) + 1
        log_action(guard, "TOUCH_SHIELD_RESET_STATE", reason, nil, -1)
    end
    return true
end

function CrashShield.install(GhostGuard)
    if type(GhostGuard) ~= "table" then return false, "GhostGuard class missing" end
    if GhostGuard._dcpro_goodix_crashshield_v1 then return true, GhostGuard end

    local core_start = GhostGuard.start
    local core_record_fault = GhostGuard.recordRuntimeFault
    local core_apply_decision = GhostGuard.applyProtectionDecision

    if type(core_start) ~= "function" or type(core_record_fault) ~= "function" then
        return false, "required MTGuard5 core methods missing"
    end

    function GhostGuard:resetGestureState(reason)
        return reset_gesture_state(self, self.input, reason)
    end

    -- Always sanitize malformed Goodix frames while a GhostGuard input bridge is
    -- present. This remains active after Protect's circuit breaker falls back to
    -- Observe-Only, which is exactly where the previous MTGuard5 guard stopped.
    function GhostGuard:guardMalformedMtFrame(input, event)
        if tonumber(event and event.type) ~= EV_SYN or tonumber(event and event.code) ~= SYN_REPORT then
            return 0
        end
        if not input or type(input.MTSlots) ~= "table" then return 0 end

        local detector = input.gesture_detector
        if not detector or type(detector.getContact) ~= "function" then return 0 end

        -- First clean any stale/corrupt contact even when its slot did not emit
        -- an event in the current frame. This prevents a new buddy contact from
        -- copying a nil/half initial_tev from the stale contact.
        if type(detector.active_contacts) == "table" then
            local corrupt = {}
            for _, contact in pairs(detector.active_contacts) do
                local sane, reason = contact_is_sane(contact)
                if not sane then corrupt[#corrupt + 1] = { contact = contact, reason = reason } end
            end
            for _, item in ipairs(corrupt) do
                drop_contact(self, detector, item.contact, item.reason)
            end
        end

        local deferred = 0
        for i = #input.MTSlots, 1, -1 do
            local tev = input.MTSlots[i]
            local slot = tev and tonumber(tev.slot) or nil
            local contact = slot ~= nil and detector:getContact(slot) or nil

            -- If an established contact became incomplete in this very frame,
            -- drop it before GestureDetector math sees the nil coordinate. The
            -- persistent ev_slots table is untouched, so a later complete frame
            -- can establish a fresh contact normally.
            if contact and not tev_has_xy(tev) then
                drop_contact(self, detector, contact, "ACTIVE_FRAME_MISSING_XY")
                contact = nil
            end

            if not contact then
                local id = tev and tonumber(tev.id) or nil
                local x = tev and tev.x or nil
                local y = tev and tev.y or nil
                local complete_new_down = id ~= nil and id >= 0 and x ~= nil and y ~= nil
                if not complete_new_down then
                    local reason
                    if id == nil then
                        reason = "NEW_NO_TRACKING_ID"
                    elseif id < 0 then
                        reason = "ORPHAN_LIFT_NO_CONTACT"
                    elseif x == nil and y == nil then
                        reason = "NEW_MISSING_XY"
                    elseif x == nil then
                        reason = "NEW_MISSING_X"
                    else
                        reason = "NEW_MISSING_Y"
                    end
                    table.remove(input.MTSlots, i)
                    deferred = deferred + 1
                    self.protect_stats.mt_guard_deferred =
                        (self.protect_stats.mt_guard_deferred or 0) + 1
                    log_action(self, "MT_GUARD_DEFER_NEW_SLOT", reason, tev, slot)
                end
            end
        end
        return deferred
    end

    -- Runtime faults still fail open for GhostGuard blocking, but the touch
    -- crash shield itself must stay installed. The old implementation restored
    -- stock handleTouchEv here, so the *next* malformed Goodix burst could kill
    -- KOReader outside the xpcall safety boundary.
    function GhostGuard:recordRuntimeFault(stage, err)
        local detail = tostring(err or "unknown error")
        self.last_error = tostring(stage or "RUNTIME_FAULT") .. ": " .. detail
        self.protect_enabled = false
        self.pending_frame_decision = nil
        if self.observer then pcall(self.observer.setProtectEnabled, self.observer, false) end

        if self.session then
            pcall(self.session.writeAction, self.session,
                { timestamp_us = now_us(), frame = -1, slot = -1, score = 0 },
                "FAIL_OPEN_RUNTIME_FAULT", self.last_error)
            pcall(self.session.flush, self.session)
        end

        pcall(self.storage.writeAtomic, self.storage,
            self.config.data_dir .. "/RUNTIME_FAULT.txt",
            "DCPRO_GHOSTGUARD_RUNTIME_FAULT_V2\nUTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ") ..
            "\nSTAGE=" .. tostring(stage or "unknown") ..
            "\nRECOVERED_BY_TOUCH_SHIELD=" .. (stage == "KOReader_HANDLE_TOUCH" and "YES" or "NO") ..
            "\nDETAIL=" .. detail .. "\n")

        if stage == "KOReader_HANDLE_TOUCH" then
            self.protect_stats.touch_shield_catches =
                (self.protect_stats.touch_shield_catches or 0) + 1
            reset_gesture_state(self, self.input, detail)
        end

        -- Do NOT call restoreProtectWrapper() here. The wrapper is now a
        -- pass-through safety boundary after any runtime fault.
        if self.bridge and self.bridge.wrapper then
            self.protect_wrapper_installed = true
            self.wrapper_mode = "PASS_THROUGH_SAFE"
        end
        return false, self.last_error
    end

    -- Install the safety wrapper in Observe/Calibration too. It remains a pure
    -- pass-through unless Protect has a profile decision to suppress.
    function GhostGuard:start(mode, reason)
        if self.config then self.config.protect_wrapper_all_modes = true end
        local ok, result = core_start(self, mode, reason)
        if ok and self.protect_wrapper_installed then
            self.wrapper_mode = self.protect_enabled and "PROTECT+CRASH_SHIELD" or "PASS_THROUGH_SAFE"
        end
        return ok, result
    end

    if type(core_apply_decision) == "function" then
        function GhostGuard:applyProtectionDecision(input, decision)
            local result = core_apply_decision(self, input, decision)
            if self.protect_wrapper_installed and not self.protect_enabled then
                self.wrapper_mode = "PASS_THROUGH_SAFE"
            end
            return result
        end
    end

    GhostGuard._dcpro_goodix_crashshield_v1 = true
    GhostGuard._dcpro_goodix_original_recordRuntimeFault = core_record_fault
    return true, GhostGuard
end

return CrashShield
