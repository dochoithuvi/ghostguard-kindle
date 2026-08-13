local TouchObserver = {}
TouchObserver.__index = TouchObserver

local EV_SYN = 0
local EV_KEY = 1
local EV_ABS = 3
local SYN_REPORT = 0
local ABS_MT_SLOT = 47
local ABS_MT_TOUCH_MAJOR = 48
local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
local ABS_MT_TRACKING_ID = 57
local BTN_TOUCH = 330

local function event_time_us(event)
    local t = event and event.time
    if type(t) == "number" then
        if t > 1000000000000 then return math.floor(t) end
        return math.floor(t * 1000000)
    end
    if t ~= nil then
        local ok, value = pcall(function()
            local sec = tonumber(t.sec or t.tv_sec or 0) or 0
            local usec = tonumber(t.usec or t.tv_usec or 0) or 0
            return sec * 1000000 + usec
        end)
        if ok and value and value > 0 then return value end
    end
    return os.time() * 1000000
end

local function slot_state()
    return {
        active = false,
        tracking_id = -1,
        x = nil, y = nil,
        start_x = nil, start_y = nil,
        previous_x = nil, previous_y = nil,
        last_position_us = nil,
        start_us = nil,
        changed = false,
        transition = nil,
        lifetime_us = nil,
        touch_major = nil,
        min_touch_major = nil,
        max_touch_major = nil,
        path_px = 0,
        flags = {},
    }
end

local function append_reason(reasons, condition, text)
    if condition then reasons[#reasons + 1] = text end
end

function TouchObserver:new(session, config, options)
    options = options or {}
    return setmetatable({
        session = session,
        config = config,
        mode = options.mode or config.default_mode,
        profile_manager = options.profile_manager,
        protect_enabled = options.protect_enabled == true,
        calibration_enabled = options.calibration_enabled == true,
        screen_width = tonumber(options.screen_width) or 0,
        screen_height = tonumber(options.screen_height) or 0,
        current_slot = 0,
        slots = {},
        frame = 0,
        start_times = {},
        recent_suspects = {},
        stats = {
            raw_events = 0, frames = 0, starts = 0, moves = 0, ends = 0,
            candidates = 0, protect_candidates = 0,
            calibration_samples = 0, calibration_rejected = 0,
        },
    }, self)
end

function TouchObserver:setProtectEnabled(enabled)
    self.protect_enabled = enabled == true
    if not self.protect_enabled then self.recent_suspects = {} end
end

function TouchObserver:getSlot(index)
    if not self.slots[index] then self.slots[index] = slot_state() end
    return self.slots[index]
end

function TouchObserver:addFlag(slot, flag, detail)
    slot.flags[#slot.flags + 1] = { flag = flag, detail = detail or "" }
end

function TouchObserver:trimStarts(now_us)
    local keep = {}
    local cutoff = now_us - self.config.burst_window_us
    for _, ts in ipairs(self.start_times) do if ts >= cutoff then keep[#keep + 1] = ts end end
    self.start_times = keep
end

function TouchObserver:trimProtectSuspects(now_us)
    local keep = {}
    local cutoff = now_us - self.config.protect_burst_window_us
    for _, item in ipairs(self.recent_suspects) do if item.ts >= cutoff then keep[#keep + 1] = item end end
    self.recent_suspects = keep
end

function TouchObserver:baseSignals(slot, ts, slot_index)
    local duration = tonumber(slot.lifetime_us) or math.max(0, ts - (slot.start_us or ts))
    local major = tonumber(slot.min_touch_major or slot.touch_major)
    local x, y = tonumber(slot.x), tonumber(slot.y)
    local incomplete = x == nil or y == nil
    local path_px = tonumber(slot.path_px) or 0
    local still = path_px <= self.config.weak_max_path_px
    local short = duration <= self.config.weak_short_lifetime_us
    local incomplete_short = incomplete and duration <= self.config.weak_incomplete_lifetime_us
    local low_major = major ~= nil and major <= self.config.weak_low_touch_major

    local edge_distance = nil
    if x ~= nil and self.screen_width > 0 then
        edge_distance = math.min(x, math.abs(self.screen_width - x))
    end
    local extreme_edge = edge_distance ~= nil and edge_distance <= self.config.weak_extreme_edge_px
    local near_edge = edge_distance ~= nil and edge_distance <= self.config.weak_near_edge_px

    local score = 0
    local reasons = {}
    if incomplete then score = score + 4 end
    if low_major then score = score + 2 end
    if short then score = score + 2 end
    if still then score = score + 1 end
    if incomplete_short and still then score = score + 2 end
    if extreme_edge then score = score + 3 elseif near_edge then score = score + 1 end

    append_reason(reasons, incomplete, "INCOMPLETE_POSITION")
    append_reason(reasons, low_major, "LOW_TOUCH_MAJOR=" .. tostring(major))
    append_reason(reasons, short, "SHORT_US=" .. tostring(duration))
    append_reason(reasons, still, "LOW_PATH=" .. tostring(path_px))
    append_reason(reasons, incomplete_short and still, "INCOMPLETE_SHORT_US=" .. tostring(duration))
    append_reason(reasons, extreme_edge, "EXTREME_EDGE=" .. tostring(edge_distance))
    append_reason(reasons, not extreme_edge and near_edge, "NEAR_EDGE=" .. tostring(edge_distance))

    -- Coordinates must never be the only reason to learn. Require a weak
    -- electrical/lifecycle signal plus a low-motion contact.
    local abnormal_signal = incomplete or low_major or extreme_edge
    local learnable = score >= self.config.calibration_min_base_score
        and still and abnormal_signal

    return {
        timestamp_us = ts,
        frame = self.frame,
        slot = slot_index,
        x = x, y = y,
        duration_us = duration,
        touch_major = major,
        path_px = path_px,
        incomplete = incomplete,
        low_major = low_major,
        short = short,
        still = still,
        extreme_edge = extreme_edge,
        near_edge = near_edge,
        base_score = score,
        learnable = learnable,
        reason = table.concat(reasons, ";"),
    }
end

function TouchObserver:calibrate(sample)
    if not self.calibration_enabled or not self.profile_manager then return end
    local accepted, detail = self.profile_manager:addContact(sample)
    self.session:writeCalibration(sample, accepted, accepted and "LEARNED" or tostring(detail))
    if accepted then
        self.stats.calibration_samples = self.stats.calibration_samples + 1
        self.session:writeCandidate(sample.timestamp_us, sample.frame, sample.slot,
            "CALIBRATION_SAMPLE", -1, sample.x, sample.y,
            "base_score=" .. tostring(sample.base_score) .. ";" .. sample.reason)
    else
        self.stats.calibration_rejected = self.stats.calibration_rejected + 1
    end
end

function TouchObserver:evaluateProtect(sample)
    if not self.protect_enabled or not self.profile_manager then return nil end
    local match = self.profile_manager:match(sample.x, sample.y)
    local score = sample.base_score
    local reasons = { sample.reason }

    if match then
        local bonus = 2 + math.floor((tonumber(match.confidence) or 0) * 3)
        score = score + bonus
        reasons[#reasons + 1] = "PROFILE_CLUSTER=" .. tostring(match.index)
            .. ";confidence=" .. tostring(match.confidence)
            .. ";samples=" .. tostring(match.count)
    end

    -- Protect never blocks by coordinate alone. A contact must still have a
    -- minimum non-location abnormality score.
    if sample.base_score < self.config.protect_min_base_score then return nil end
    if score >= self.config.protect_suspect_score then
        self.recent_suspects[#self.recent_suspects + 1] = {
            ts = sample.timestamp_us, x = sample.x, y = sample.y,
            slot = sample.slot, score = score,
        }
    end
    self:trimProtectSuspects(sample.timestamp_us)

    local burst_count = #self.recent_suspects
    if burst_count >= 2 then score = score + 2; reasons[#reasons + 1] = "SUSPECT_PAIR=" .. burst_count end
    if burst_count >= self.config.protect_burst_count then
        score = score + 2; reasons[#reasons + 1] = "SUSPECT_BURST=" .. burst_count
    end

    -- Outside a learned cluster, only extreme/incomplete burst patterns may
    -- pass the threshold. This preserves ordinary taps in unlearned regions.
    if not match and not (sample.incomplete or sample.extreme_edge) then return nil end
    if score < self.config.protect_drop_score then return nil end

    self.stats.protect_candidates = self.stats.protect_candidates + 1
    return {
        drop = true,
        timestamp_us = sample.timestamp_us,
        frame = sample.frame,
        slot = sample.slot,
        score = score,
        x = sample.x, y = sample.y,
        duration_us = sample.duration_us,
        touch_major = sample.touch_major,
        path_px = sample.path_px,
        reason = table.concat(reasons, ";"),
        quarantine_seconds = burst_count >= self.config.protect_burst_count
            and self.config.protect_quarantine_seconds or 0,
    }
end

function TouchObserver:observe(event)
    if not event then return nil end
    local ev_type = tonumber(event.type)
    local code = tonumber(event.code)
    local value = tonumber(event.value)
    if ev_type == nil or code == nil or value == nil then return nil end

    local ts = event_time_us(event)
    self.stats.raw_events = self.stats.raw_events + 1
    if ev_type == EV_ABS or (ev_type == EV_KEY and code == BTN_TOUCH)
        or (ev_type == EV_SYN and code == SYN_REPORT) then
        self.session:writeEvent(ts, ev_type, code, value)
    end

    if ev_type == EV_ABS then
        if code == ABS_MT_SLOT then
            self.current_slot = value
            self:getSlot(value)
            return nil
        end

        local slot = self:getSlot(self.current_slot)
        if code == ABS_MT_TRACKING_ID then
            slot.changed = true
            if value >= 0 then
                local tracking_replaced = slot.active == true
                slot.active = true
                slot.tracking_id = value
                slot.x, slot.y = nil, nil
                slot.start_x, slot.start_y = nil, nil
                slot.previous_x, slot.previous_y = nil, nil
                slot.last_position_us = nil
                slot.start_us = ts
                slot.lifetime_us = nil
                slot.touch_major = nil
                slot.min_touch_major = nil
                slot.max_touch_major = nil
                slot.path_px = 0
                slot.flags = {}
                if tracking_replaced then self:addFlag(slot, "TRACKING_REPLACED", "new tracking id while active") end
                slot.transition = "START"
                self.stats.starts = self.stats.starts + 1
                self.start_times[#self.start_times + 1] = ts
                self:trimStarts(ts)
                if #self.start_times >= self.config.burst_start_count then
                    self:addFlag(slot, "BURST_START", tostring(#self.start_times) .. " starts in observation window")
                end
            else
                if not slot.active then
                    self:addFlag(slot, "ORPHAN_END", "tracking end on inactive slot")
                    slot.lifetime_us = 0
                else
                    slot.lifetime_us = math.max(0, ts - (slot.start_us or ts))
                    if slot.lifetime_us <= self.config.zero_life_us then
                        self:addFlag(slot, "ZERO_LIFE", "contact lifetime_us=" .. tostring(slot.lifetime_us))
                    end
                end
                slot.active = false
                slot.transition = "END"
                self.stats.ends = self.stats.ends + 1
            end
        elseif code == ABS_MT_POSITION_X or code == ABS_MT_POSITION_Y then
            slot.changed = true
            local old_x, old_y = slot.x, slot.y
            if code == ABS_MT_POSITION_X then slot.x = value else slot.y = value end
            if slot.start_x == nil and slot.x ~= nil then slot.start_x = slot.x end
            if slot.start_y == nil and slot.y ~= nil then slot.start_y = slot.y end
            if slot.active and old_x ~= nil and old_y ~= nil and slot.x ~= nil and slot.y ~= nil then
                local distance = math.abs(slot.x - old_x) + math.abs(slot.y - old_y)
                slot.path_px = slot.path_px + distance
                if slot.last_position_us then
                    local dt = ts - slot.last_position_us
                    if dt >= 0 and dt <= self.config.teleport_window_us
                        and distance >= self.config.teleport_distance then
                        self:addFlag(slot, "TELEPORT", "manhattan=" .. distance .. ";dt_us=" .. dt)
                    end
                end
            end
            slot.previous_x, slot.previous_y = old_x, old_y
            slot.last_position_us = ts
            if not slot.transition then slot.transition = "MOVE" end
        elseif code == ABS_MT_TOUCH_MAJOR then
            slot.changed = true
            slot.touch_major = value
            if slot.min_touch_major == nil or value < slot.min_touch_major then slot.min_touch_major = value end
            if slot.max_touch_major == nil or value > slot.max_touch_major then slot.max_touch_major = value end
        end
    elseif ev_type == EV_SYN and code == SYN_REPORT then
        self.frame = self.frame + 1
        self.stats.frames = self.frame
        local frame_decision = nil
        for slot_index, slot in pairs(self.slots) do
            if slot.changed then
                local state = slot.transition or (slot.active and "MOVE" or "IDLE")
                if state == "MOVE" then self.stats.moves = self.stats.moves + 1 end

                local sample, decision = nil, nil
                if state == "END" then
                    sample = self:baseSignals(slot, ts, slot_index)
                    if self.calibration_enabled then self:calibrate(sample) end
                    if self.protect_enabled then decision = self:evaluateProtect(sample) end
                end

                self.session:writeContact(ts, self.frame, slot_index, state,
                    slot.tracking_id, slot.x, slot.y, slot.lifetime_us,
                    slot.min_touch_major or slot.touch_major, slot.path_px,
                    sample and sample.base_score or nil,
                    decision and decision.score or nil)

                for _, item in ipairs(slot.flags) do
                    self.stats.candidates = self.stats.candidates + 1
                    self.session:writeCandidate(ts, self.frame, slot_index, item.flag,
                        slot.tracking_id, slot.x, slot.y, item.detail)
                end
                if decision then
                    self.stats.candidates = self.stats.candidates + 1
                    self.session:writeCandidate(ts, self.frame, slot_index, "PROTECT_SCORE",
                        slot.tracking_id, slot.x, slot.y,
                        "score=" .. tostring(decision.score) .. ";" .. decision.reason)
                    if not frame_decision or decision.score > frame_decision.score then frame_decision = decision end
                end

                if state == "END" then self.slots[slot_index] = slot_state()
                else
                    slot.changed = false
                    slot.transition = nil
                    slot.lifetime_us = nil
                    slot.flags = {}
                end
            end
        end
        if self.frame % self.config.flush_every_frames == 0 then self.session:flush() end
        return frame_decision
    end
    return nil
end

function TouchObserver:getStats()
    return self.stats
end

return TouchObserver
