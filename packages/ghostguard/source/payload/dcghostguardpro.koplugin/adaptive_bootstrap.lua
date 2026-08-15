local Adaptive = {}
Adaptive.__index = Adaptive

local function clamp(v, lo, hi)
    v = tonumber(v) or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function read(storage, path)
    local ok, value = pcall(storage.readFile, storage, path)
    return ok and value or nil
end

local function write(storage, path, text)
    local ok, value = pcall(storage.writeAtomic, storage, path, text)
    return ok and value ~= false
end

local function parse(text, key)
    if type(text) ~= "string" then return nil end
    return text:match("\n?" .. key .. "=([^\r\n]+)")
end

function Adaptive:new(guard, config)
    local o = setmetatable({
        guard = guard,
        config = config,
        storage = guard.storage,
        path = (config.data_dir or "/mnt/us/.dcpro_ghostguard") .. "/ADAPTIVE_PROFILE_V1.txt",
        level = 0,
        candidate_level = 0,
        candidate_confidence = 0,
        sessions = 0,
        suspect_samples = 0,
        strongest_cluster = 0,
        base_drop_score = tonumber(config.protect_drop_score) or 8,
        base_burst_count = tonumber(config.protect_burst_count) or 3,
    }, Adaptive)
    o:load()
    return o
end

function Adaptive:load()
    local text = read(self.storage, self.path)
    if not text then return end
    self.level = tonumber(parse(text, "LEVEL")) or 0
    self.candidate_level = tonumber(parse(text, "CANDIDATE_LEVEL")) or 0
    self.candidate_confidence = tonumber(parse(text, "CANDIDATE_CONFIDENCE")) or 0
    self.sessions = tonumber(parse(text, "SESSIONS")) or 0
    self.suspect_samples = tonumber(parse(text, "SUSPECT_SAMPLES")) or 0
    self.strongest_cluster = tonumber(parse(text, "STRONGEST_CLUSTER")) or 0
end

function Adaptive:save()
    local text = table.concat({
        "DCPRO_GHOSTGUARD_ADAPTIVE_PROFILE_V1",
        "LEVEL=" .. tostring(self.level),
        "CANDIDATE_LEVEL=" .. tostring(self.candidate_level),
        "CANDIDATE_CONFIDENCE=" .. string.format("%.3f", self.candidate_confidence),
        "SESSIONS=" .. tostring(self.sessions),
        "SUSPECT_SAMPLES=" .. tostring(self.suspect_samples),
        "STRONGEST_CLUSTER=" .. tostring(self.strongest_cluster),
        "UPDATED_UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "\n",
    }, "\n")
    return write(self.storage, self.path, text)
end

function Adaptive:beginSession()
    if self.level <= 0 then self.level = 1 end
    self.candidate_level = 0
    self.candidate_confidence = 0
    if self.guard.profiles and type(self.guard.profiles.startCalibration) == "function" then
        pcall(self.guard.profiles.startCalibration, self.guard.profiles)
    end
    self:applyLevel()
end

function Adaptive:applyLevel()
    local c = self.guard.config
    if self.level >= 2 then
        c.protect_drop_score = math.max(6, self.base_drop_score - 1)
        c.protect_burst_count = math.max(2, self.base_burst_count - 1)
        c.protect_suspect_score = math.max(4, (tonumber(c.protect_suspect_score) or 5) - 1)
    else
        c.protect_drop_score = self.base_drop_score
        c.protect_burst_count = self.base_burst_count
        c.protect_suspect_score = tonumber(c.protect_suspect_score) or 5
    end
end

function Adaptive:observeSession()
    self.sessions = self.sessions + 1
    local status = nil
    if self.guard.profiles and type(self.guard.profiles.calibrationStatus) == "function" then
        local ok, result = pcall(self.guard.profiles.calibrationStatus, self.guard.profiles)
        if ok then status = result end
    end
    if status then
        local suspects = tonumber(status.suspect_contacts) or 0
        local strongest = tonumber(status.strongest_cluster) or 0
        if suspects > 0 and self.guard.profiles and type(self.guard.profiles.finalize) == "function" then
            pcall(self.guard.profiles.finalize, self.guard.profiles)
        end
        self.suspect_samples = self.suspect_samples + suspects
        self.strongest_cluster = math.max(self.strongest_cluster, strongest)
        if self.level == 1 and suspects >= 8 and strongest >= 3 then
            self.candidate_level = 2
            self.candidate_confidence = clamp(0.50 + math.min(0.25, suspects / 40)
                + math.min(0.20, strongest / 20), 0, 0.95)
        elseif self.level == 2 and suspects == 0 then
            self.candidate_level = 1
            self.candidate_confidence = 0.70
        end
    end
    self:save()
end

function Adaptive:suggestionText()
    if self.candidate_level > self.level then
        return string.format("Đề xuất: LEVEL %d (%.0f%%)", self.candidate_level, self.candidate_confidence * 100)
    end
    if self.candidate_level > 0 and self.candidate_level < self.level then
        return string.format("Đề xuất: LEVEL %d (%.0f%%)", self.candidate_level, self.candidate_confidence * 100)
    end
    return nil
end

function Adaptive:statusText()
    local level = math.max(0, self.level)
    local state = level == 0 and "NORMAL" or (level == 1 and "MILD / ADAPTIVE" or "SEVERE")
    local suggestion = self:suggestionText()
    local suffix = suggestion and ("\n" .. suggestion) or ""
    return string.format("Adaptive: LEVEL %d — %s%s", level, state, suffix)
end

function Adaptive:acceptCandidate()
    if self.candidate_level <= 0 then return false, "Chưa có profile đề xuất" end
    self.level = self.candidate_level
    self.candidate_level = 0
    self.candidate_confidence = 0
    self:save()
    self:applyLevel()
    return true, self:statusText()
end

function Adaptive:install()
    local guard = self.guard
    local original_start = guard.start
    local original_stop = guard.stop
    local original_status = guard.statusText
    local original_progress = guard.customerProgressText

    guard.adaptive = self

    guard.start = function(g, mode, reason)
        local ok, result = original_start(g, mode, reason)
        if ok and mode == g.config.protect_mode and g.profiles:hasApproved() then
            self:beginSession()
            if g.observer then
                -- Protection stays active while the observer learns new anomaly patterns.
                g.observer.calibration_enabled = true
            end
        end
        return ok, result
    end

    guard.stop = function(g, reason)
        self:observeSession()
        if g.observer then g.observer.calibration_enabled = false end
        return original_stop(g, reason)
    end

    guard.statusText = function(g, ...)
        local base = original_status(g, ...)
        return tostring(base or "GhostGuard") .. "\n" .. self:statusText()
    end

    guard.customerProgressText = function(g, ...)
        local base = original_progress(g, ...)
        local suggestion = self:suggestionText()
        return suggestion and (tostring(base or "") .. "\n\n" .. suggestion) or base
    end

    return true
end

return function(guard, config)
    local ok, adaptive = pcall(Adaptive.new, Adaptive, guard, config)
    if not ok then return false, adaptive end
    local installed, err = pcall(adaptive.install, adaptive)
    if not installed then return false, err end
    return true, adaptive
end
