local lfs = require("libs/libkoreader-lfs")

local Storage = {}
Storage.__index = Storage

local Session = {}
Session.__index = Session

local function mkdir_p(path)
    if not path or path == "" then return false, "empty path" end
    local current = path:sub(1, 1) == "/" and "/" or ""
    for part in path:gmatch("[^/]+") do
        if current == "/" then current = current .. part
        elseif current == "" then current = part
        else current = current .. "/" .. part end
        local mode = lfs.attributes(current, "mode")
        if not mode then
            local ok, err = lfs.mkdir(current)
            if not ok and lfs.attributes(current, "mode") ~= "directory" then
                return false, err or ("cannot create " .. current)
            end
        elseif mode ~= "directory" then
            return false, current .. " is not a directory"
        end
    end
    return true
end

local function csv(value)
    if value == nil then return "" end
    local s = tostring(value)
    if s:find('[,\"\r\n]') then s = '"' .. s:gsub('"', '""') .. '"' end
    return s
end

local function write_line(handle, values, count)
    local parts = {}
    local n = count or values.n or #values
    for i = 1, n do parts[i] = csv(values[i]) end
    handle:write(table.concat(parts, ","), "\n")
end

local function copy_file(source, target)
    local input, err = io.open(source, "rb")
    if not input then return false, err end
    local output, out_err = io.open(target, "wb")
    if not output then input:close(); return false, out_err end
    while true do
        local block = input:read(65536)
        if not block then break end
        output:write(block)
    end
    output:flush()
    input:close()
    output:close()
    return true
end

function Storage:new(config)
    return setmetatable({ config = config }, self)
end

function Storage:ensureLayout()
    for _, path in ipairs({
        self.config.data_dir,
        self.config.report_dir,
        self.config.profile_dir,
        self.config.cloud_outbox_dir,
        "/mnt/us/koreader/dcpro",
    }) do
        local ok, err = mkdir_p(path)
        if not ok then return false, err end
    end
    if not self:fileExists(self.config.cloud_target_file) then
        self:writeAtomic(self.config.cloud_target_file,
            "DCPRO_GHOSTGUARD_CLOUD_TARGET_V1\n" ..
            "DRIVE_ROOT_FOLDER_ID=" .. tostring(self.config.drive_root_folder_id or "") .. "\n" ..
            "DRIVE_ROOT_FOLDER_URL=" .. tostring(self.config.drive_root_folder_url or "") .. "\n" ..
            "TRANSPORT=OUTBOX_REQUIRES_AUTHENTICATED_BRIDGE\n")
    end
    return true
end

function Storage:fileExists(path)
    return lfs.attributes(path, "mode") == "file"
end

function Storage:dirExists(path)
    return lfs.attributes(path, "mode") == "directory"
end

function Storage:readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

function Storage:writeAtomic(path, data)
    local parent = path:match("^(.*)/[^/]+$")
    if parent then
        local ok, err = mkdir_p(parent)
        if not ok then return false, err end
    end
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then return false, err end
    f:write(data or "")
    f:flush()
    f:close()
    local ok, rename_err = os.rename(tmp, path)
    if not ok then os.remove(tmp); return false, rename_err end
    return true
end

function Storage:touch(path, data)
    return self:writeAtomic(path, data or "")
end

function Storage:removeExact(path)
    return os.remove(path)
end

function Storage:copyFile(source, target)
    local parent = target:match("^(.*)/[^/]+$")
    if parent then
        local ok, err = mkdir_p(parent)
        if not ok then return false, err end
    end
    return copy_file(source, target)
end

function Storage:isSafeMode()
    for _, path in ipairs(self.config.safe_mode_paths) do
        if self:fileExists(path) then return true, path end
    end
    return false
end

function Storage:setSafeMode(enabled)
    if enabled then
        return self:touch(self.config.safe_mode_paths[1],
            "DCPRO_GHOSTGUARD_SAFE_MODE=1\nCREATED=" .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    end
    local removed_any = false
    for _, path in ipairs(self.config.safe_mode_paths) do
        if self:fileExists(path) then os.remove(path); removed_any = true end
    end
    return true, removed_any and "removed" or "already clear"
end

function Storage:archiveStaleMarker()
    local marker = self:readFile(self.config.run_marker)
    if not marker then return false end
    local archive = string.format("%s/STALE_%s.txt", self.config.report_dir, os.date("%Y%m%d_%H%M%S"))
    self:writeAtomic(archive,
        "DCPRO GhostGuard stale session marker\nDetected: " ..
        os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n\n" .. marker)
    os.remove(self.config.run_marker)
    return true, archive
end

function Storage:openSession(session_id, metadata)
    metadata = metadata or {}
    metadata.storage = self
    local ok, err = self:ensureLayout()
    if not ok then return nil, err end
    local base = self.config.report_dir .. "/" .. session_id
    local events, e1 = io.open(base .. "_EVENTS.csv", "wb")
    if not events then return nil, e1 end
    local contacts, e2 = io.open(base .. "_CONTACTS.csv", "wb")
    if not contacts then events:close(); return nil, e2 end
    local candidates, e3 = io.open(base .. "_CANDIDATES.csv", "wb")
    if not candidates then events:close(); contacts:close(); return nil, e3 end
    local actions, e4 = io.open(base .. "_ACTIONS.csv", "wb")
    if not actions then events:close(); contacts:close(); candidates:close(); return nil, e4 end
    local calibration, e5 = io.open(base .. "_CALIBRATION.csv", "wb")
    if not calibration then
        events:close(); contacts:close(); candidates:close(); actions:close(); return nil, e5
    end

    write_line(events, {"timestamp_us", "type", "code", "value"}, 4)
    write_line(contacts, {"timestamp_us", "frame", "slot", "state", "tracking_id", "x", "y", "lifetime_us", "touch_major", "path_px", "base_score", "profile_score"}, 12)
    write_line(candidates, {"timestamp_us", "frame", "slot", "flag", "tracking_id", "x", "y", "detail"}, 8)
    write_line(actions, {"timestamp_us", "frame", "action", "slot", "score", "x", "y", "duration_us", "touch_major", "path_px", "detail"}, 11)
    write_line(calibration, {"timestamp_us", "frame", "slot", "accepted", "base_score", "x", "y", "duration_us", "touch_major", "path_px", "detail"}, 11)

    return setmetatable({
        base = base,
        events = events,
        contacts = contacts,
        candidates = candidates,
        actions = actions,
        calibration = calibration,
        metadata = metadata,
        closed = false,
        summary_path = base .. "_SUMMARY.txt",
    }, Session)
end

function Session:writeEvent(ts, ev_type, code, value)
    if not self.closed then write_line(self.events, {ts, ev_type, code, value}, 4) end
end

function Session:writeContact(ts, frame, slot, state, tracking_id, x, y, lifetime_us, touch_major, path_px, base_score, profile_score)
    if not self.closed then
        write_line(self.contacts, {ts, frame, slot, state, tracking_id, x, y, lifetime_us, touch_major, path_px, base_score, profile_score}, 12)
    end
end

function Session:writeCandidate(ts, frame, slot, flag, tracking_id, x, y, detail)
    if not self.closed then
        write_line(self.candidates, {ts, frame, slot, flag, tracking_id, x, y, detail}, 8)
    end
end

function Session:writeAction(decision, action, detail)
    if self.closed then return end
    write_line(self.actions, {
        decision and decision.timestamp_us or os.time() * 1000000,
        decision and decision.frame or -1,
        action or "UNKNOWN",
        decision and decision.slot or -1,
        decision and decision.score or 0,
        decision and decision.x or nil,
        decision and decision.y or nil,
        decision and decision.duration_us or nil,
        decision and decision.touch_major or nil,
        decision and decision.path_px or nil,
        detail or (decision and decision.reason) or "",
    }, 11)
end

function Session:writeCalibration(sample, accepted, detail)
    if self.closed then return end
    write_line(self.calibration, {
        sample and sample.timestamp_us or os.time() * 1000000,
        sample and sample.frame or -1,
        sample and sample.slot or -1,
        accepted and "YES" or "NO",
        sample and sample.base_score or 0,
        sample and sample.x or nil,
        sample and sample.y or nil,
        sample and sample.duration_us or nil,
        sample and sample.touch_major or nil,
        sample and sample.path_px or nil,
        detail or (sample and sample.reason) or "",
    }, 11)
end

function Session:flush()
    if self.closed then return end
    for _, handle in ipairs({self.events, self.contacts, self.candidates, self.actions, self.calibration}) do handle:flush() end
end

function Session:paths()
    return {
        self.base .. "_EVENTS.csv",
        self.base .. "_CONTACTS.csv",
        self.base .. "_CANDIDATES.csv",
        self.base .. "_ACTIONS.csv",
        self.base .. "_CALIBRATION.csv",
        self.summary_path,
    }
end

function Session:close(summary)
    if self.closed then return true end
    self:flush()
    for _, handle in ipairs({self.events, self.contacts, self.candidates, self.actions, self.calibration}) do handle:close() end
    self.closed = true
    local lines = {
        "DCPRO GhostGuard session report",
        "VERSION=" .. tostring(self.metadata.version or "unknown"),
        "MODE=" .. tostring(self.metadata.mode or "OBSERVE_ONLY"),
        "SESSION=" .. tostring(self.metadata.session_id or "unknown"),
        "START_UTC=" .. tostring(self.metadata.start_utc or "unknown"),
        "STOP_UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    for key, value in pairs(summary or {}) do
        lines[#lines + 1] = tostring(key):upper() .. "=" .. tostring(value)
    end
    return self.metadata.storage:writeAtomic(self.summary_path, table.concat(lines, "\n") .. "\n")
end


function Storage:copyRuntimeDiagnostics(folder)
    local copied = 0
    local candidates = {
        { "/mnt/us/koreader/crash.log", "KOReader_crash.log", 2097152 },
        { "/mnt/us/koreader/koreader.log", "KOReader_koreader.log", 1048576 },
        { "/mnt/us/koreader/reader.log", "KOReader_reader.log", 1048576 },
        { "/mnt/us/extensions/koreader/crash.log", "KOReader_extensions_crash.log", 2097152 },
        { self.config.data_dir .. "/RUNTIME_FAULT.txt", "GhostGuard_RUNTIME_FAULT.txt", 262144 },
        { self.config.cloud_status_file, "GhostGuard_CLOUD_STATUS.txt", 262144 },
    }
    for _, item in ipairs(candidates) do
        local source, name, max_size = item[1], item[2], item[3]
        local attr = lfs.attributes(source)
        if attr and attr.mode == "file" and (tonumber(attr.size) or 0) <= max_size then
            local ok = self:copyFile(source, folder .. "/" .. name)
            if ok then copied = copied + 1 end
        end
    end
    return copied
end

function Storage:prepareStaleOutbox(stale_report, options)
    if not stale_report or not self:fileExists(stale_report) then return false, "missing stale report" end
    options = options or {}
    local session_id = "STALE_" .. os.date("%Y%m%d_%H%M%S")
    local folder = self.config.cloud_outbox_dir .. "/" .. tostring(options.device_id or "unknown") .. "_" .. session_id
    local ok, err = mkdir_p(folder)
    if not ok then return false, err end
    local name = stale_report:match("([^/]+)$") or "STALE_SESSION.txt"
    local copied = self:copyFile(stale_report, folder .. "/" .. name) and 1 or 0
    copied = copied + self:copyRuntimeDiagnostics(folder)
    if copied == 0 then lfs.rmdir(folder); return false, "no stale diagnostics copied" end
    local manifest_ok, manifest_err = self:writeAtomic(folder .. "/UPLOAD_MANIFEST.txt",
        "DCPRO_GHOSTGUARD_UPLOAD_V2\n" ..
        "DEVICE_ID=" .. tostring(options.device_id or "unknown") .. "\n" ..
        "MODEL=" .. tostring(options.model or "unknown") .. "\n" ..
        "SESSION=" .. session_id .. "\n" ..
        "DATE=" .. os.date("!%Y-%m-%d") .. "\n" ..
        "FILES_COPIED=" .. tostring(copied) .. "\n" ..
        "TYPE=STALE_CRASH_DIAGNOSTICS\nSTATUS=PENDING_AUTHENTICATED_UPLOAD\n")
    if not manifest_ok then return false, manifest_err end
    return true, folder
end

function Storage:prepareCloudOutbox(session, options)
    if not session then return false, "missing session" end
    options = options or {}
    local folder = self.config.cloud_outbox_dir .. "/" .. tostring(options.device_id or "unknown") ..
        "_" .. tostring(session.metadata.session_id or os.date("%Y%m%d_%H%M%S"))
    local ok, err = mkdir_p(folder)
    if not ok then return false, err end

    local copied = 0
    for _, source in ipairs(session:paths()) do
        if self:fileExists(source) then
            local name = source:match("([^/]+)$")
            local copied_ok = self:copyFile(source, folder .. "/" .. name)
            if copied_ok then copied = copied + 1 end
        end
    end
    if options.profile_path and self:fileExists(options.profile_path) then
        if self:copyFile(options.profile_path, folder .. "/ACTIVE_PROFILE.profile") then copied = copied + 1 end
    end
    copied = copied + self:copyRuntimeDiagnostics(folder)
    if copied == 0 then
        lfs.rmdir(folder)
        return false, "cloud outbox refused: no report or diagnostic files copied"
    end
    local manifest_ok, manifest_err = self:writeAtomic(folder .. "/UPLOAD_MANIFEST.txt",
        "DCPRO_GHOSTGUARD_UPLOAD_V2\n" ..
        "DEVICE_ID=" .. tostring(options.device_id or "unknown") .. "\n" ..
        "MODEL=" .. tostring(options.model or "unknown") .. "\n" ..
        "SESSION=" .. tostring(session.metadata.session_id or "unknown") .. "\n" ..
        "DATE=" .. os.date("!%Y-%m-%d") .. "\n" ..
        "DRIVE_ROOT_FOLDER_ID=" .. tostring(self.config.drive_root_folder_id or "") .. "\n" ..
        "FILES_COPIED=" .. tostring(copied) .. "\n" ..
        "STATUS=PENDING_AUTHENTICATED_UPLOAD\n")
    if not manifest_ok then return false, manifest_err end
    return true, folder
end

return Storage
