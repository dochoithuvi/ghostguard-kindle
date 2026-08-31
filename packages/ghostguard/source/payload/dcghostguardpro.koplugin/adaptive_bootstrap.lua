local Adaptive = {}
Adaptive.__index = Adaptive

local function clamp(v, lo, hi)
    v = tonumber(v) or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function bool01(v)
    return v == true and 1 or 0
end

local function parse_number(v)
    if v == nil or v == "" or v == "nil" then return nil end
    return tonumber(v)
end

local function split_pipe(line)
    local out = {}
    for part in (tostring(line or "") .. "|"):gmatch("(.-)|") do
        out[#out + 1] = part
    end
    return out
end

local function read(storage, path)
    local ok, value = pcall(storage.readFile, storage, path)
    return ok and value or nil
end

local function write(storage, path, text)
    local ok, value = pcall(storage.writeAtomic, storage, path, text)
    return ok and value ~= false
end

local function remove(storage, path)
    pcall(storage.removeExact, storage, path)
end

local function copy_cluster(cluster)
    return {
        count = tonumber(cluster.count) or 0,
        x_min = cluster.x_min, x_max = cluster.x_max,
        y_min = cluster.y_min, y_max = cluster.y_max,
        missing_x = tonumber(cluster.missing_x) or 0,
        missing_y = tonumber(cluster.missing_y) or 0,
        low_major = tonumber(cluster.low_major) or 0,
        short = tonumber(cluster.short) or 0,
        incomplete = tonumber(cluster.incomplete) or 0,
        base_score_sum = tonumber(cluster.base_score_sum) or 0,
        confidence = tonumber(cluster.confidence) or 0,
        first_seen_wall = tonumber(cluster.first_seen_wall) or 0,
        last_seen_wall = tonumber(cluster.last_seen_wall) or 0,
        session_hits = tonumber(cluster.session_hits) or 0,
        last_session = tonumber(cluster.last_session) or 0,
        source_native = tonumber(cluster.source_native) or 0,
        source_koreader = tonumber(cluster.source_koreader) or 0,
    }
end

local function center(minv, maxv)
    minv, maxv = tonumber(minv), tonumber(maxv)
    if minv == nil or maxv == nil then return nil end
    return (minv + maxv) / 2
end

local function ratio(n, d)
    return (tonumber(n) or 0) / math.max(1, tonumber(d) or 0)
end

local function append_line(path, text)
    local f = io.open(path, "ab")
    if not f then return false end
    f:write(tostring(text or ""), "\n")
    f:flush()
    f:close()
    return true
end

function Adaptive:new(guard, config)
    local base = config.data_dir or "/mnt/us/.dcpro_ghostguard"
    local o = setmetatable({
        guard = guard,
        config = config,
        storage = guard.storage,
        path = base .. "/ADAPTIVE_REGIONS_V2.profile",
        legacy_path = base .. "/ADAPTIVE_PROFILE_V1.txt",
        native_spool = base .. "/service/native-shadow-candidates.log",
        native_pause = base .. "/service/native-shadow.pause",
        clusters = {},
        session_seq = 0,
        total_samples = 0,
        total_rejected = 0,
        promotions = 0,
        native_imported = 0,
        accepted_since_save = 0,
        last_save_wall = os.time(),
        observer_original_evaluate = nil,
        observer_patched = nil,
        active = false,
        last_error = nil,
        external_status_path = config.adaptive_external_status_path
            or "/mnt/us/GhostGuard_Reports/ContinuousLearning_Status.txt",
        external_changes_path = config.adaptive_external_changes_path
            or "/mnt/us/GhostGuard_Reports/ContinuousLearning_Changes.log",
        external_profile_snapshot_path = config.adaptive_external_profile_snapshot_path
            or "/mnt/us/GhostGuard_Reports/ActiveProfile_AutoLearned.txt",
        last_external_report_wall = 0,
        last_promotion_utc = "NONE",
        last_promotion_detail = "NONE",
    }, Adaptive)
    o:load()
    return o
end

function Adaptive:confidence(cluster)
    local count = math.max(1, tonumber(cluster.count) or 0)
    local missing_ratio = ((tonumber(cluster.missing_x) or 0) + (tonumber(cluster.missing_y) or 0)) / count
    local low_ratio = (tonumber(cluster.low_major) or 0) / count
    local short_ratio = (tonumber(cluster.short) or 0) / count
    local incomplete_ratio = (tonumber(cluster.incomplete) or 0) / count
    local avg_score = (tonumber(cluster.base_score_sum) or 0) / count
    local score_ratio = math.min(1, avg_score / 10)
    return clamp(0.30 + math.min(0.30, count * 0.03)
        + missing_ratio * 0.10 + incomplete_ratio * 0.12
        + low_ratio * 0.10 + short_ratio * 0.08
        + score_ratio * 0.10, 0, 0.99)
end

function Adaptive:serialize()
    local lines = {
        "DCPRO_GHOSTGUARD_ADAPTIVE_REGIONS_V2",
        "VERSION=2",
        "TOTAL_SAMPLES=" .. tostring(self.total_samples),
        "TOTAL_REJECTED=" .. tostring(self.total_rejected),
        "PROMOTIONS=" .. tostring(self.promotions),
        "NATIVE_IMPORTED=" .. tostring(self.native_imported),
        "SESSION_SEQ=" .. tostring(self.session_seq),
        "LAST_PROMOTION_UTC=" .. tostring(self.last_promotion_utc or "NONE"),
        "LAST_PROMOTION_DETAIL=" .. tostring(self.last_promotion_detail or "NONE"),
        "UPDATED_UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "CLUSTER_COUNT=" .. tostring(#self.clusters),
    }
    for i, c in ipairs(self.clusters) do
        c.confidence = self:confidence(c)
        lines[#lines + 1] = table.concat({
            "CLUSTER", i,
            c.x_min or "", c.x_max or "", c.y_min or "", c.y_max or "",
            c.count or 0, c.missing_x or 0, c.missing_y or 0,
            c.low_major or 0, c.short or 0, c.incomplete or 0,
            c.base_score_sum or 0, string.format("%.3f", c.confidence or 0),
            c.first_seen_wall or 0, c.last_seen_wall or 0,
            c.session_hits or 0, c.last_session or 0,
            c.source_native or 0, c.source_koreader or 0,
        }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

function Adaptive:load()
    local text = read(self.storage, self.path)
    if type(text) ~= "string" or not text:match("^DCPRO_GHOSTGUARD_ADAPTIVE_REGIONS_V2") then return end
    self.clusters = {}
    for line in text:gmatch("[^\r\n]+") do
        local key, value = line:match("^([A-Z_]+)=(.*)$")
        if key == "TOTAL_SAMPLES" then self.total_samples = tonumber(value) or 0
        elseif key == "TOTAL_REJECTED" then self.total_rejected = tonumber(value) or 0
        elseif key == "PROMOTIONS" then self.promotions = tonumber(value) or 0
        elseif key == "NATIVE_IMPORTED" then self.native_imported = tonumber(value) or 0
        elseif key == "SESSION_SEQ" then self.session_seq = tonumber(value) or 0
        elseif key == "LAST_PROMOTION_UTC" then self.last_promotion_utc = value
        elseif key == "LAST_PROMOTION_DETAIL" then self.last_promotion_detail = value
        elseif line:match("^CLUSTER|") then
            local p = split_pipe(line)
            self.clusters[#self.clusters + 1] = {
                x_min = parse_number(p[3]), x_max = parse_number(p[4]),
                y_min = parse_number(p[5]), y_max = parse_number(p[6]),
                count = tonumber(p[7]) or 0,
                missing_x = tonumber(p[8]) or 0,
                missing_y = tonumber(p[9]) or 0,
                low_major = tonumber(p[10]) or 0,
                short = tonumber(p[11]) or 0,
                incomplete = tonumber(p[12]) or 0,
                base_score_sum = tonumber(p[13]) or 0,
                confidence = tonumber(p[14]) or 0,
                first_seen_wall = tonumber(p[15]) or 0,
                last_seen_wall = tonumber(p[16]) or 0,
                session_hits = tonumber(p[17]) or 0,
                last_session = tonumber(p[18]) or 0,
                source_native = tonumber(p[19]) or 0,
                source_koreader = tonumber(p[20]) or 0,
            }
        end
    end
end

function Adaptive:appendChange(kind, detail)
    return append_line(self.external_changes_path, table.concat({
        os.date("!%Y-%m-%dT%H:%M:%SZ"), tostring(kind or "EVENT"), tostring(detail or "")
    }, " | "))
end

function Adaptive:approvedClusterCount()
    local approved = self.guard.profiles and self.guard.profiles.approved
    return approved and #(approved.clusters or {}) or 0
end

function Adaptive:fastTrackEligible(cluster)
    if self.config.adaptive_fast_promotion_enabled == false then return false end
    local count = tonumber(cluster.count) or 0
    local min_count = tonumber(self.config.adaptive_fast_promotion_min_cluster) or 3
    if count < min_count then return false end
    local conf = tonumber(cluster.confidence) or self:confidence(cluster)
    if conf < (tonumber(self.config.adaptive_fast_promotion_min_confidence) or 0.80) then return false end
    local avg_score = (tonumber(cluster.base_score_sum) or 0) / math.max(1, count)
    if avg_score < (tonumber(self.config.adaptive_fast_promotion_min_base_score) or 9) then return false end

    -- Fast path is for malformed electrical/lifecycle signatures only.
    -- Coordinate repetition by itself can never trigger it.
    local missing = (tonumber(cluster.missing_x) or 0) + (tonumber(cluster.missing_y) or 0)
    return (tonumber(cluster.source_koreader) or 0) >= min_count
        and ratio(cluster.incomplete, count) >= 0.67
        and ratio(cluster.short, count) >= 0.67
        and ratio(missing, count) >= 0.67
end

function Adaptive:writeProfileSnapshot()
    local profiles = self.guard.profiles
    local approved = profiles and profiles.approved
    if not approved or type(profiles.serialize) ~= "function" then return false end
    local header = table.concat({
        "DCPRO_GHOSTGUARD_ACTIVE_PROFILE_SNAPSHOT",
        "UPDATED_UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "SOURCE=APPROVED_PROFILE_PLUS_CONTINUOUS_LEARNING",
        "AUTO_PROMOTED_REGIONS=" .. tostring(self.promotions),
        "LAST_PROMOTION_UTC=" .. tostring(self.last_promotion_utc or "NONE"),
        "LAST_PROMOTION_DETAIL=" .. tostring(self.last_promotion_detail or "NONE"),
        "",
    }, "\n")
    local ok, payload = pcall(profiles.serialize, profiles, approved, "APPROVED")
    if not ok then return false end
    return write(self.storage, self.external_profile_snapshot_path, header .. tostring(payload or ""))
end

function Adaptive:writeExternalStatus(force)
    local now = os.time()
    local interval = math.max(5, tonumber(self.config.adaptive_external_report_seconds) or 10)
    if not force and now - (tonumber(self.last_external_report_wall) or 0) < interval then return true end

    local lines = {
        "DCPRO_GHOSTGUARD_CONTINUOUS_LEARNING_V3",
        "UPDATED_UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "ACTIVE=" .. (self.active and "YES" or "NO"),
        "AUTO_PROFILE_UPDATE=ON",
        "FAST_TRACK=" .. (self.config.adaptive_fast_promotion_enabled == false and "OFF" or "ON"),
        "TOTAL_STRONG_SAMPLES=" .. tostring(self.total_samples),
        "TOTAL_REJECTED=" .. tostring(self.total_rejected),
        "WATCHED_NEW_REGIONS=" .. tostring(#self.clusters),
        "PROMOTED_REGIONS=" .. tostring(self.promotions),
        "APPROVED_PROFILE_REGIONS=" .. tostring(self:approvedClusterCount()),
        "LAST_PROMOTION_UTC=" .. tostring(self.last_promotion_utc or "NONE"),
        "LAST_PROMOTION_DETAIL=" .. tostring(self.last_promotion_detail or "NONE"),
        "STATUS_FILE=" .. tostring(self.external_status_path),
        "CHANGES_FILE=" .. tostring(self.external_changes_path),
        "PROFILE_SNAPSHOT_FILE=" .. tostring(self.external_profile_snapshot_path),
        "",
        "[CANDIDATE_REGIONS]",
    }
    if #self.clusters == 0 then
        lines[#lines + 1] = "NONE"
    else
        for i, c in ipairs(self.clusters) do
            c.confidence = self:confidence(c)
            local count = tonumber(c.count) or 0
            local avg_score = (tonumber(c.base_score_sum) or 0) / math.max(1, count)
            lines[#lines + 1] = string.format(
                "REGION_%d count=%d conf=%.3f avg_score=%.2f x=%s..%s y=%s..%s missing_x=%d missing_y=%d incomplete=%d short=%d sessions=%d fast_ready=%s",
                i, count, tonumber(c.confidence) or 0, avg_score,
                tostring(c.x_min or ""), tostring(c.x_max or ""),
                tostring(c.y_min or ""), tostring(c.y_max or ""),
                tonumber(c.missing_x) or 0, tonumber(c.missing_y) or 0,
                tonumber(c.incomplete) or 0, tonumber(c.short) or 0,
                tonumber(c.session_hits) or 0, self:fastTrackEligible(c) and "YES" or "NO")
        end
    end
    if self.last_error then lines[#lines + 1] = "LAST_ERROR=" .. tostring(self.last_error) end
    local ok = write(self.storage, self.external_status_path, table.concat(lines, "\n") .. "\n")
    if ok then self.last_external_report_wall = now end
    return ok
end

function Adaptive:save(force)
    if not force then
        local n = math.max(1, tonumber(self.config.adaptive_checkpoint_samples) or 8)
        local seconds = math.max(30, tonumber(self.config.adaptive_checkpoint_seconds) or 120)
        if self.accepted_since_save < n and os.time() - self.last_save_wall < seconds then
            return true
        end
    end
    local ok = write(self.storage, self.path, self:serialize())
    if ok then
        self.accepted_since_save = 0
        self.last_save_wall = os.time()
    else
        self.last_error = "adaptive checkpoint failed"
    end
    return ok
end

function Adaptive:findCluster(sample)
    local radius = tonumber(self.config.adaptive_cluster_radius_px)
        or tonumber(self.config.calibration_cluster_radius_px) or 96
    local best, best_distance = nil, nil
    for _, cluster in ipairs(self.clusters) do
        local cx = center(cluster.x_min, cluster.x_max)
        local cy = center(cluster.y_min, cluster.y_max)
        local compatible, distance = true, 0
        if sample.x ~= nil and cx ~= nil then
            local dx = math.abs(sample.x - cx)
            if dx > radius then compatible = false end
            distance = distance + dx
        elseif sample.x ~= nil or cx ~= nil then
            compatible = false
        end
        if compatible and sample.y ~= nil and cy ~= nil then
            local dy = math.abs(sample.y - cy)
            if dy > radius then compatible = false end
            distance = distance + dy
        elseif compatible and sample.y ~= nil and cy == nil then
            -- A missing-Y candidate may match by X only. A candidate with a
            -- known Y must not merge into an unrelated Y-less region unless X
            -- already matched tightly.
            distance = distance + radius / 2
        end
        if compatible and (best_distance == nil or distance < best_distance) then
            best, best_distance = cluster, distance
        end
    end
    return best
end

function Adaptive:updateCluster(cluster, sample, source)
    local now = os.time()
    cluster.count = (tonumber(cluster.count) or 0) + 1
    if sample.x == nil then cluster.missing_x = (tonumber(cluster.missing_x) or 0) + 1
    else
        cluster.x_min = cluster.x_min == nil and sample.x or math.min(cluster.x_min, sample.x)
        cluster.x_max = cluster.x_max == nil and sample.x or math.max(cluster.x_max, sample.x)
    end
    if sample.y == nil then cluster.missing_y = (tonumber(cluster.missing_y) or 0) + 1
    else
        cluster.y_min = cluster.y_min == nil and sample.y or math.min(cluster.y_min, sample.y)
        cluster.y_max = cluster.y_max == nil and sample.y or math.max(cluster.y_max, sample.y)
    end
    if sample.low_major then cluster.low_major = (tonumber(cluster.low_major) or 0) + 1 end
    if sample.short then cluster.short = (tonumber(cluster.short) or 0) + 1 end
    if sample.incomplete then cluster.incomplete = (tonumber(cluster.incomplete) or 0) + 1 end
    cluster.base_score_sum = (tonumber(cluster.base_score_sum) or 0) + (tonumber(sample.base_score) or 0)
    if (tonumber(cluster.first_seen_wall) or 0) <= 0 then cluster.first_seen_wall = now end
    cluster.last_seen_wall = now
    if tonumber(cluster.last_session) ~= self.session_seq then
        cluster.session_hits = (tonumber(cluster.session_hits) or 0) + 1
        cluster.last_session = self.session_seq
    end
    if source == "NATIVE_SHADOW" then cluster.source_native = (tonumber(cluster.source_native) or 0) + 1
    else cluster.source_koreader = (tonumber(cluster.source_koreader) or 0) + 1 end
    cluster.confidence = self:confidence(cluster)
end

function Adaptive:isStrongSample(sample)
    if type(sample) ~= "table" then return false end
    if sample.learnable == false then return false end
    if sample.x == nil and sample.y == nil then return false end
    local score = tonumber(sample.base_score) or 0
    if score < (tonumber(self.config.adaptive_min_base_score) or 7) then return false end
    -- Never learn by coordinate alone. New regions need a strong electrical or
    -- lifecycle signature. This is intentionally stricter than first calibration.
    return sample.incomplete == true
        or (sample.low_major == true and sample.short == true)
        or (sample.extreme_edge == true and sample.short == true)
end

function Adaptive:approvedMatch(sample)
    local profiles = self.guard.profiles
    if not profiles or type(profiles.match) ~= "function" then return nil end
    local ok, result = pcall(profiles.match, profiles, sample.x, sample.y)
    return ok and result or nil
end

function Adaptive:approvedRoom()
    local approved = self.guard.profiles and self.guard.profiles.approved
    if not approved then return false end
    local max_clusters = tonumber(self.config.adaptive_max_clusters) or 32
    return #(approved.clusters or {}) < max_clusters
end

function Adaptive:promoteReady()
    local profiles = self.guard.profiles
    local approved = profiles and profiles.approved
    if not approved or approved.ready ~= true then return 0 end

    local min_count = tonumber(self.config.adaptive_promotion_min_cluster) or 6
    local min_conf = tonumber(self.config.adaptive_promotion_min_confidence) or 0.72
    local min_age = tonumber(self.config.adaptive_promotion_min_age_seconds) or 30
    local max_clusters = tonumber(self.config.adaptive_max_clusters) or 32

    -- Work on a staged copy. The live approved profile is swapped only after
    -- the complete profile has been written atomically.
    local staged = { clusters = {} }
    for key, value in pairs(approved) do
        if key ~= "clusters" and type(value) ~= "table" then staged[key] = value end
    end
    for _, cluster in ipairs(approved.clusters or {}) do
        staged.clusters[#staged.clusters + 1] = copy_cluster(cluster)
    end

    local promoted, keep, promoted_details = 0, {}, {}
    for _, cluster in ipairs(self.clusters) do
        cluster.confidence = self:confidence(cluster)
        local age = math.max(0,
            (tonumber(cluster.last_seen_wall) or 0) - (tonumber(cluster.first_seen_wall) or 0))
        local repeat_ok = (tonumber(cluster.session_hits) or 0) >= 2
            or age >= min_age
            or (tonumber(cluster.count) or 0) >= math.max(min_count + 4, 10)
        local cx, cy = center(cluster.x_min, cluster.x_max), center(cluster.y_min, cluster.y_max)
        local already = nil
        if type(profiles.match) == "function" then
            local ok, match = pcall(profiles.match, profiles, cx, cy)
            if ok then already = match end
        end

        local fast_ok = self:fastTrackEligible(cluster)
        local normal_ok = (tonumber(cluster.count) or 0) >= min_count
            and (tonumber(cluster.confidence) or 0) >= min_conf and repeat_ok

        if not already and #staged.clusters < max_clusters and (normal_ok or fast_ok) then
            local copied = copy_cluster(cluster)
            copied._promotion_mode = fast_ok and "FAST_STRONG" or "NORMAL"
            copied.confidence = self:confidence(copied)
            staged.clusters[#staged.clusters + 1] = copied
            staged.profile_kind = "GHOST_CLUSTER"
            staged.ready = true
            staged.suspect_contacts = (tonumber(staged.suspect_contacts) or 0)
                + (tonumber(copied.count) or 0)
            promoted = promoted + 1
            promoted_details[#promoted_details + 1] = string.format(
                "mode=%s count=%d conf=%.3f x=%s..%s y=%s..%s missing_x=%d missing_y=%d",
                tostring(copied._promotion_mode or "NORMAL"), tonumber(copied.count) or 0,
                tonumber(copied.confidence) or 0, tostring(copied.x_min or ""),
                tostring(copied.x_max or ""), tostring(copied.y_min or ""),
                tostring(copied.y_max or ""), tonumber(copied.missing_x) or 0,
                tonumber(copied.missing_y) or 0)
            copied._promotion_mode = nil
        else
            keep[#keep + 1] = cluster
        end
    end

    if promoted == 0 then return 0 end
    table.sort(staged.clusters, function(a, b)
        local ca, cb = tonumber(a.confidence) or 0, tonumber(b.confidence) or 0
        if ca == cb then return (tonumber(a.count) or 0) > (tonumber(b.count) or 0) end
        return ca > cb
    end)

    local payload = profiles:serialize(staged, "APPROVED")
    local ok, err = self.storage:writeAtomic(profiles.approved_path, payload)
    if not ok then
        self.last_error = "adaptive promotion save failed: " .. tostring(err)
        self:appendChange("PROMOTION_FAILED", self.last_error)
        self:writeExternalStatus(true)
        return 0
    end

    profiles.approved = staged
    self.clusters = keep
    self.promotions = self.promotions + promoted
    self.last_promotion_utc = os.date("!%Y-%m-%dT%H:%M:%SZ")
    self.last_promotion_detail = table.concat(promoted_details, " ; ")
    self.last_error = nil
    self:appendChange("PROFILE_UPDATED", "regions=" .. tostring(promoted) .. " | " .. self.last_promotion_detail)
    if self.guard.session then
        pcall(self.guard.session.writeAction, self.guard.session,
            { timestamp_us = os.time() * 1000000, frame = -1, slot = -1, score = 0 },
            "ADAPTIVE_PROFILE_PROMOTE", "regions=" .. tostring(promoted))
        pcall(self.guard.session.flush, self.guard.session)
    end
    self:save(true)
    self:writeProfileSnapshot()
    self:writeExternalStatus(true)
    return promoted
end

function Adaptive:pruneCandidates()
    local max_candidates = tonumber(self.config.adaptive_max_candidate_clusters) or 32
    if #self.clusters <= max_candidates then return end
    table.sort(self.clusters, function(a, b)
        local sa = (tonumber(a.confidence) or self:confidence(a)) + math.min(0.20, (tonumber(a.count) or 0) * 0.01)
        local sb = (tonumber(b.confidence) or self:confidence(b)) + math.min(0.20, (tonumber(b.count) or 0) * 0.01)
        return sa > sb
    end)
    while #self.clusters > max_candidates do table.remove(self.clusters) end
end

function Adaptive:observeSample(sample, decision, source)
    if not self.active and source ~= "NATIVE_SHADOW" then return false, "inactive" end
    if not self:isStrongSample(sample) then
        self.total_rejected = self.total_rejected + 1
        return false, "weak"
    end
    if self:approvedMatch(sample) then return false, "already-covered" end

    local cluster = self:findCluster(sample)
    local created_new_cluster = false
    if not cluster then
        created_new_cluster = true
        cluster = {
            count = 0,
            x_min = sample.x, x_max = sample.x,
            y_min = sample.y, y_max = sample.y,
            missing_x = 0, missing_y = 0,
            low_major = 0, short = 0, incomplete = 0,
            base_score_sum = 0, confidence = 0,
            first_seen_wall = os.time(), last_seen_wall = os.time(),
            session_hits = 0, last_session = 0,
            source_native = 0, source_koreader = 0,
        }
        self.clusters[#self.clusters + 1] = cluster
    end
    self:updateCluster(cluster, sample, source or "KOREADER")
    if created_new_cluster then
        self:appendChange("NEW_REGION_WATCH",
            "x=" .. tostring(sample.x or "") .. ";y=" .. tostring(sample.y or "")
            .. ";score=" .. tostring(sample.base_score or 0)
            .. ";incomplete=" .. tostring(sample.incomplete == true)
            .. ";short=" .. tostring(sample.short == true))
    end
    self.total_samples = self.total_samples + 1
    self.accepted_since_save = self.accepted_since_save + 1
    self:pruneCandidates()
    local promoted = self:promoteReady()
    self:save(false)
    self:writeExternalStatus(false)

    if self.guard.session and source ~= "NATIVE_SHADOW" then
        pcall(self.guard.session.writeCandidate, self.guard.session,
            sample.timestamp_us or os.time() * 1000000,
            sample.frame or -1, sample.slot or -1, "ADAPTIVE_SAMPLE", -1,
            sample.x, sample.y,
            "score=" .. tostring(sample.base_score) .. ";promoted=" .. tostring(promoted)
                .. ";decision=" .. tostring(decision and decision.score or 0))
    end
    return true, promoted
end

function Adaptive:importNativeCandidates()
    local processing = self.native_spool .. ".import"
    os.remove(processing)
    local renamed = os.rename(self.native_spool, processing)
    if not renamed then return 0 end
    local f = io.open(processing, "rb")
    if not f then return 0 end
    local imported = 0
    for line in f:lines() do
        if line:match("^CANDIDATE|") then
            local p = split_pipe(line)
            local sample = {
                timestamp_us = (tonumber(p[2]) or os.time()) * 1000000,
                frame = -1, slot = tonumber(p[3]) or -1,
                x = parse_number(p[4]), y = parse_number(p[5]),
                base_score = tonumber(p[6]) or 0,
                incomplete = p[7] == "1",
                low_major = p[8] == "1",
                short = p[9] == "1",
                extreme_edge = p[10] == "1",
                near_edge = p[11] == "1",
                learnable = true,
            }
            local accepted = self:observeSample(sample, nil, "NATIVE_SHADOW")
            if accepted then imported = imported + 1 end
        end
    end
    f:close()
    os.remove(processing)
    self.native_imported = self.native_imported + imported
    if imported > 0 then self:save(true) end
    return imported
end

function Adaptive:patchObserver()
    local observer = self.guard.observer
    if not observer or observer == self.observer_patched then return false end
    local original = observer.evaluateProtect
    if type(original) ~= "function" then return false end
    self.observer_original_evaluate = original
    self.observer_patched = observer
    observer.evaluateProtect = function(obs, sample)
        local decision = original(obs, sample)
        local ok, err = pcall(self.observeSample, self, sample, decision, "KOREADER")
        if not ok then self.last_error = "adaptive sample error: " .. tostring(err) end
        return decision
    end
    return true
end

function Adaptive:beginSession()
    if self.active then return true end
    if self.config.adaptive_profiles_enabled == false
        or self.config.adaptive_learning_during_protect == false then return false end
    self.active = true
    self.session_seq = self.session_seq + 1
    self.storage:touch(self.native_pause,
        "PAUSE=KOREADER_PROTECT\nUTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    if self.config.adaptive_import_native_shadow == true then
        self:importNativeCandidates()
    end
    self:patchObserver()
    self:appendChange("SESSION_BEGIN", "seq=" .. tostring(self.session_seq))
    self:save(false)
    self:writeProfileSnapshot()
    self:writeExternalStatus(true)
    return true
end

function Adaptive:endSession()
    if not self.active and not self.observer_patched then return true end
    self.active = false
    remove(self.storage, self.native_pause)
    self:save(true)
    if self.observer_patched and type(self.observer_original_evaluate) == "function" then
        self.observer_patched.evaluateProtect = self.observer_original_evaluate
    end
    self.observer_patched = nil
    self.observer_original_evaluate = nil
    self:appendChange("SESSION_END", "seq=" .. tostring(self.session_seq))
    self:writeExternalStatus(true)
    return true
end

function Adaptive:reset()
    self.clusters = {}
    self.total_samples, self.total_rejected = 0, 0
    self.promotions, self.native_imported = 0, 0
    self.accepted_since_save = 0
    remove(self.storage, self.path)
    remove(self.storage, self.legacy_path)
    remove(self.storage, self.native_pause)
    remove(self.storage, self.external_status_path)
    remove(self.storage, self.external_changes_path)
    remove(self.storage, self.external_profile_snapshot_path)
    self.last_promotion_utc = "NONE"
    self.last_promotion_detail = "NONE"
    self:writeExternalStatus(true)
    return true
end

function Adaptive:statusText()
    local enabled = self.config.adaptive_profiles_enabled ~= false
        and self.config.adaptive_learning_during_protect ~= false
    local text = string.format(
        "Học liên tục: %s | mẫu mạnh=%d | vùng mới=%d | đã nhập profile=%d",
        enabled and "BẬT" or "TẮT", self.total_samples, #self.clusters, self.promotions)
    if self.last_error then text = text .. " | CẢNH BÁO=" .. tostring(self.last_error) end
    return text
end

function Adaptive:install()
    local guard = self.guard
    if guard._dcpro_adaptive_instance then return true end
    guard._dcpro_adaptive_instance = self

    local original_start = guard.start
    local original_stop = guard.stop
    local original_status = guard.statusText
    local original_reset = guard.resetProfile
    local original_raw = guard.onRawEvent

    guard.adaptive = self

    guard.start = function(g, mode, reason)
        local ok, result = original_start(g, mode, reason)
        if ok and mode == g.config.protect_mode and g.profiles:hasApproved() then
            local adaptive_ok, adaptive_err = pcall(self.beginSession, self)
            if not adaptive_ok then self.last_error = "adaptive begin error: " .. tostring(adaptive_err) end
        end
        return ok, result
    end

    guard.stop = function(g, reason)
        local ok, result = original_stop(g, reason)
        if self.active or self.observer_patched then pcall(self.endSession, self) end
        return ok, result
    end

    guard.statusText = function(g, ...)
        local base = tostring(original_status(g, ...) or "GhostGuard")
        -- Strip any stale adaptive lines left by an older stacked wrapper.
        base = base:gsub("\nHọc liên tục:[^\n]*", "")
        return base .. "\n" .. self:statusText()
    end

    guard.onRawEvent = function(g, event)
        if not self.active and type(g.isProtecting) == "function" and g:isProtecting()
            and g.profiles and g.profiles:hasApproved() then
            local adaptive_ok, adaptive_err = pcall(self.beginSession, self)
            if not adaptive_ok then self.last_error = "adaptive lazy begin error: " .. tostring(adaptive_err) end
        end
        return original_raw(g, event)
    end

    guard.resetProfile = function(g, ...)
        local ok, result = original_reset(g, ...)
        if ok then self:reset() end
        return ok, result
    end

    self:writeProfileSnapshot()
    self:writeExternalStatus(true)
    return true
end

return function(guard, config)
    if guard and guard._dcpro_adaptive_instance then
        return true, guard._dcpro_adaptive_instance
    end
    local ok, adaptive = pcall(Adaptive.new, Adaptive, guard, config)
    if not ok then return false, adaptive end
    local call_ok, install_result = pcall(adaptive.install, adaptive)
    if not call_ok then return false, install_result end
    if install_result ~= true then return false, install_result end
    return true, adaptive
end
