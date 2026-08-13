local ProfileManager = {}
ProfileManager.__index = ProfileManager

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function sanitize(value)
    value = tostring(value or "unknown")
    value = value:gsub("[^%w%._%-]", "_")
    if value == "" then return "unknown" end
    return value
end

local function center(minv, maxv)
    if minv == nil or maxv == nil then return nil end
    return (minv + maxv) / 2
end

local function parse_number(value)
    if value == nil or value == "" or value == "nil" then return nil end
    return tonumber(value)
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
        base_score_sum = tonumber(cluster.base_score_sum)
            or ((tonumber(cluster.count) or 0) * 5),
        confidence = tonumber(cluster.confidence) or nil,
    }
end

function ProfileManager:new(config, storage, options)
    options = options or {}
    local device_id = sanitize(options.device_id)
    local base = config.profile_dir .. "/" .. device_id
    local obj = setmetatable({
        config = config,
        storage = storage,
        device_id = device_id,
        model = tostring(options.model or "unknown"),
        screen_width = tonumber(options.screen_width) or 0,
        screen_height = tonumber(options.screen_height) or 0,
        pending_path = base .. ".pending.profile",
        approved_path = base .. ".approved.profile",
        calibration = nil,
        approved = nil,
        pending = nil,
    }, self)
    obj.pending = obj:loadFile(obj.pending_path)
    obj.approved = obj:loadFile(obj.approved_path)
    return obj
end

function ProfileManager:startCalibration()
    -- Customer learning is cumulative across normal reading sessions. A clean
    -- KOReader exit finalizes a pending profile; the next session continues
    -- from those clusters instead of discarding the customer's progress.
    local seed = self.pending
    local clusters = {}
    if seed and not self.approved then
        for _, cluster in ipairs(seed.clusters or {}) do
            clusters[#clusters + 1] = copy_cluster(cluster)
        end
    end
    self.calibration = {
        started_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        total_contacts = seed and (tonumber(seed.total_contacts) or 0) or 0,
        suspect_contacts = seed and (tonumber(seed.suspect_contacts) or 0) or 0,
        clusters = clusters,
    }
    return true
end

function ProfileManager:calibrationStatus()
    local source = self.calibration or self.pending
    local selected, strongest = 0, 0
    if source then
        for _, cluster in ipairs(source.clusters or {}) do
            local count = tonumber(cluster.count) or 0
            if count >= self.config.calibration_keep_cluster_samples then
                selected = selected + 1
            end
            if count > strongest then strongest = count end
        end
    end
    local suspects = source and (tonumber(source.suspect_contacts) or 0) or 0
    local ready = suspects >= self.config.calibration_min_suspect_samples
        and strongest >= self.config.calibration_min_cluster_samples
    return {
        total_contacts = source and (tonumber(source.total_contacts) or 0) or 0,
        suspect_contacts = suspects,
        strongest_cluster = strongest,
        cluster_count = selected,
        ready = ready,
    }
end

function ProfileManager:isCalibrationReady()
    return self:calibrationStatus().ready == true
end

function ProfileManager:progressText()
    local status = self:calibrationStatus()
    local need_suspects = math.max(0, self.config.calibration_min_suspect_samples - status.suspect_contacts)
    local need_cluster = math.max(0, self.config.calibration_min_cluster_samples - status.strongest_cluster)
    if status.ready then
        return "ĐÃ ĐỦ DỮ LIỆU — chọn Hoàn tất thiết lập bảo vệ"
    end
    return string.format(
        "Đang học cách dùng máy: mẫu nghi ghost=%d/%d, cụm mạnh nhất=%d/%d, còn cần=%d mẫu/%d cụm",
        status.suspect_contacts, self.config.calibration_min_suspect_samples,
        status.strongest_cluster, self.config.calibration_min_cluster_samples,
        need_suspects, need_cluster)
end

function ProfileManager:isCalibrating()
    return self.calibration ~= nil
end

function ProfileManager:cancelCalibration()
    self.calibration = nil
    return true
end

function ProfileManager:findCluster(sample)
    local best, best_distance = nil, nil
    for _, cluster in ipairs(self.calibration.clusters) do
        local cx = center(cluster.x_min, cluster.x_max)
        local cy = center(cluster.y_min, cluster.y_max)
        local compatible = true
        local distance = 0
        if sample.x ~= nil and cx ~= nil then
            local dx = math.abs(sample.x - cx)
            if dx > self.config.calibration_cluster_radius_px then compatible = false end
            distance = distance + dx
        elseif sample.x ~= nil or cx ~= nil then
            compatible = false
        end
        if compatible and sample.y ~= nil and cy ~= nil then
            local dy = math.abs(sample.y - cy)
            if dy > self.config.calibration_cluster_radius_px then compatible = false end
            distance = distance + dy
        end
        -- Missing Y is a known KT5 ghost signature. Match by X only, but do
        -- not let an X-less sample merge with an arbitrary cluster.
        if compatible and (best_distance == nil or distance < best_distance) then
            best, best_distance = cluster, distance
        end
    end
    return best
end

function ProfileManager:addContact(sample)
    if not self.calibration then return false, "calibration not active" end
    self.calibration.total_contacts = self.calibration.total_contacts + 1
    if not sample or not sample.learnable then return false, "not learnable" end
    if sample.x == nil and sample.y == nil then return false, "no coordinates" end

    self.calibration.suspect_contacts = self.calibration.suspect_contacts + 1
    local cluster = self:findCluster(sample)
    if not cluster then
        cluster = {
            count = 0,
            x_min = sample.x,
            x_max = sample.x,
            y_min = sample.y,
            y_max = sample.y,
            missing_x = 0,
            missing_y = 0,
            low_major = 0,
            short = 0,
            incomplete = 0,
            base_score_sum = 0,
        }
        self.calibration.clusters[#self.calibration.clusters + 1] = cluster
    end

    cluster.count = cluster.count + 1
    if sample.x == nil then
        cluster.missing_x = cluster.missing_x + 1
    else
        cluster.x_min = cluster.x_min == nil and sample.x or math.min(cluster.x_min, sample.x)
        cluster.x_max = cluster.x_max == nil and sample.x or math.max(cluster.x_max, sample.x)
    end
    if sample.y == nil then
        cluster.missing_y = cluster.missing_y + 1
    else
        cluster.y_min = cluster.y_min == nil and sample.y or math.min(cluster.y_min, sample.y)
        cluster.y_max = cluster.y_max == nil and sample.y or math.max(cluster.y_max, sample.y)
    end
    if sample.low_major then cluster.low_major = cluster.low_major + 1 end
    if sample.short then cluster.short = cluster.short + 1 end
    if sample.incomplete then cluster.incomplete = cluster.incomplete + 1 end
    cluster.base_score_sum = cluster.base_score_sum + (tonumber(sample.base_score) or 0)
    return true, cluster
end

function ProfileManager:confidence(cluster)
    local count = math.max(1, cluster.count or 0)
    local missing_ratio = ((cluster.missing_x or 0) + (cluster.missing_y or 0)) / count
    local low_ratio = (cluster.low_major or 0) / count
    local short_ratio = (cluster.short or 0) / count
    local score_ratio = math.min(1, (cluster.base_score_sum or 0) / (count * 10))
    return clamp(0.28 + math.min(0.32, count * 0.025)
        + missing_ratio * 0.14 + low_ratio * 0.10
        + short_ratio * 0.10 + score_ratio * 0.08, 0, 0.99)
end

function ProfileManager:serialize(profile, status)
    local lines = {
        "DCPRO_GHOST_PROFILE_V1",
        "PROFILE_VERSION=1",
        "PLUGIN_VERSION=" .. tostring(self.config.version),
        "STATUS=" .. tostring(status or profile.status or "PENDING"),
        "DEVICE_ID=" .. tostring(self.device_id),
        "MODEL=" .. tostring(self.model),
        "SCREEN_WIDTH=" .. tostring(self.screen_width),
        "SCREEN_HEIGHT=" .. tostring(self.screen_height),
        "CREATED_UTC=" .. tostring(profile.created_utc or os.date("!%Y-%m-%dT%H:%M:%SZ")),
        "TOTAL_CONTACTS=" .. tostring(profile.total_contacts or 0),
        "SUSPECT_CONTACTS=" .. tostring(profile.suspect_contacts or 0),
        "READY=" .. ((profile.ready == true) and "YES" or "NO"),
        "CLUSTER_COUNT=" .. tostring(#(profile.clusters or {})),
    }
    for index, cluster in ipairs(profile.clusters or {}) do
        lines[#lines + 1] = table.concat({
            "CLUSTER", index,
            cluster.x_min or "", cluster.x_max or "",
            cluster.y_min or "", cluster.y_max or "",
            cluster.count or 0,
            cluster.missing_x or 0, cluster.missing_y or 0,
            cluster.low_major or 0, cluster.short or 0,
            cluster.incomplete or 0,
            string.format("%.3f", cluster.confidence or self:confidence(cluster)),
            cluster.base_score_sum or 0,
        }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

function ProfileManager:loadFile(path)
    local content = self.storage:readFile(path)
    if not content or not content:match("^DCPRO_GHOST_PROFILE_V1") then return nil end
    local profile = { clusters = {} }
    for line in content:gmatch("[^\r\n]+") do
        local key, value = line:match("^([A-Z_]+)=(.*)$")
        if key then
            if key == "STATUS" then profile.status = value
            elseif key == "DEVICE_ID" then profile.device_id = value
            elseif key == "MODEL" then profile.model = value
            elseif key == "SCREEN_WIDTH" then profile.screen_width = tonumber(value) or 0
            elseif key == "SCREEN_HEIGHT" then profile.screen_height = tonumber(value) or 0
            elseif key == "CREATED_UTC" then profile.created_utc = value
            elseif key == "TOTAL_CONTACTS" then profile.total_contacts = tonumber(value) or 0
            elseif key == "SUSPECT_CONTACTS" then profile.suspect_contacts = tonumber(value) or 0
            elseif key == "READY" then profile.ready = value == "YES" end
        elseif line:match("^CLUSTER|") then
            local parts = {}
            for part in (line .. "|"):gmatch("(.-)|") do parts[#parts + 1] = part end
            profile.clusters[#profile.clusters + 1] = {
                x_min = parse_number(parts[3]), x_max = parse_number(parts[4]),
                y_min = parse_number(parts[5]), y_max = parse_number(parts[6]),
                count = tonumber(parts[7]) or 0,
                missing_x = tonumber(parts[8]) or 0,
                missing_y = tonumber(parts[9]) or 0,
                low_major = tonumber(parts[10]) or 0,
                short = tonumber(parts[11]) or 0,
                incomplete = tonumber(parts[12]) or 0,
                confidence = tonumber(parts[13]) or 0,
                base_score_sum = tonumber(parts[14]) or ((tonumber(parts[7]) or 0) * 5),
            }
        end
    end
    return profile
end

function ProfileManager:finalize()
    if not self.calibration then return false, "calibration not active" end
    local selected = {}
    for _, cluster in ipairs(self.calibration.clusters) do
        if cluster.count >= self.config.calibration_keep_cluster_samples then
            cluster.confidence = self:confidence(cluster)
            selected[#selected + 1] = cluster
        end
    end
    table.sort(selected, function(a, b) return (a.count or 0) > (b.count or 0) end)
    while #selected > self.config.calibration_max_clusters do table.remove(selected) end

    local strongest = selected[1] and selected[1].count or 0
    local ready = self.calibration.suspect_contacts >= self.config.calibration_min_suspect_samples
        and strongest >= self.config.calibration_min_cluster_samples
    local profile = {
        status = "PENDING",
        created_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        total_contacts = self.calibration.total_contacts,
        suspect_contacts = self.calibration.suspect_contacts,
        clusters = selected,
        ready = ready,
    }
    local ok, err = self.storage:writeAtomic(self.pending_path, self:serialize(profile, "PENDING"))
    self.calibration = nil
    if not ok then return false, err end
    self.pending = profile
    return true, profile
end

function ProfileManager:hasPendingReady()
    return self.pending and self.pending.ready == true and #(self.pending.clusters or {}) > 0
end

function ProfileManager:hasApproved()
    return self.approved and self.approved.ready == true and #(self.approved.clusters or {}) > 0
end

function ProfileManager:approvePending()
    if not self:hasPendingReady() then return false, "Profile chưa đủ mẫu tin cậy" end
    local approved = self.pending
    approved.status = "APPROVED"
    local ok, err = self.storage:writeAtomic(self.approved_path, self:serialize(approved, "APPROVED"))
    if not ok then return false, err end
    self.approved = approved
    self.pending = nil
    self.storage:removeExact(self.pending_path)
    return true, self.approved_path
end

function ProfileManager:reset()
    self.storage:removeExact(self.pending_path)
    self.storage:removeExact(self.approved_path)
    if self.config.customer_profile_ready_marker then
        self.storage:removeExact(self.config.customer_profile_ready_marker)
    end
    self.pending, self.approved, self.calibration = nil, nil, nil
    return true
end

function ProfileManager:match(x, y)
    if not self:hasApproved() then return nil end
    x, y = tonumber(x), tonumber(y)
    for index, cluster in ipairs(self.approved.clusters) do
        local x_match = false
        local y_match = false
        if x ~= nil and cluster.x_min ~= nil and cluster.x_max ~= nil then
            x_match = x >= cluster.x_min - self.config.calibration_profile_padding_x
                and x <= cluster.x_max + self.config.calibration_profile_padding_x
        elseif x == nil and (cluster.missing_x or 0) > 0 then
            x_match = true
        end
        if y ~= nil and cluster.y_min ~= nil and cluster.y_max ~= nil then
            y_match = y >= cluster.y_min - self.config.calibration_profile_padding_y
                and y <= cluster.y_max + self.config.calibration_profile_padding_y
        elseif y == nil and (cluster.missing_y or 0) > 0 then
            y_match = true
        elseif cluster.y_min == nil and cluster.y_max == nil then
            y_match = true
        end
        if x_match and y_match then
            return {
                index = index,
                confidence = cluster.confidence or 0,
                count = cluster.count or 0,
            }
        end
    end
    return nil
end

function ProfileManager:summaryText()
    if self.calibration then
        return self:progressText()
    end
    local profile = self.approved or self.pending
    if not profile then return "Chưa có profile. GhostGuard sẽ tự học khi khách sử dụng KOReader." end
    local lines = {
        "Profile: " .. (self.approved and "ĐÃ DUYỆT" or "CHỜ DUYỆT"),
        "Thiết bị: " .. self.device_id .. " / " .. self.model,
        "Mẫu nghi ghost: " .. tostring(profile.suspect_contacts or 0),
        "Tổng contact: " .. tostring(profile.total_contacts or 0),
        "Số vùng: " .. tostring(#(profile.clusters or {})),
        "Đủ tin cậy: " .. (profile.ready and "CÓ" or "CHƯA"),
    }
    for index, cluster in ipairs(profile.clusters or {}) do
        lines[#lines + 1] = string.format(
            "Vùng %d: x=%s..%s, y=%s..%s, n=%d, tin cậy=%.2f",
            index, tostring(cluster.x_min), tostring(cluster.x_max),
            tostring(cluster.y_min), tostring(cluster.y_max),
            cluster.count or 0, cluster.confidence or 0)
    end
    return table.concat(lines, "\n")
end

return ProfileManager
