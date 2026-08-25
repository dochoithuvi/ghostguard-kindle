local SystemService = {}
SystemService.__index = SystemService

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function parse(text, key)
    if type(text) ~= "string" then return nil end
    return text:match("\n?" .. key .. "=([^\r\n]+)")
end

local function mkdir_p(path)
    os.execute("mkdir -p " .. string.format("%q", path) .. " >/dev/null 2>&1")
end

local function write_atomic(path, text)
    local tmp = path .. ".tmp." .. tostring(os.time()) .. "." .. tostring(math.random(1000, 999999))
    local f = io.open(tmp, "wb")
    if not f then return false, "cannot open temporary service file" end
    local ok, err = f:write(text)
    f:close()
    if not ok then os.remove(tmp); return false, tostring(err) end
    local renamed, rename_err = os.rename(tmp, path)
    if not renamed then os.remove(tmp); return false, tostring(rename_err) end
    return true
end

local function bool01(value, default)
    if value == nil then return default and "1" or "0" end
    return tostring(value) == "0" and "0" or "1"
end

function SystemService:new(config)
    local dir = config.system_service_dir or ((config.data_dir or "/mnt/us/.dcpro_ghostguard") .. "/service")
    mkdir_p(dir)
    return setmetatable({
        config = config,
        dir = dir,
        config_path = dir .. "/config.env",
        status_path = dir .. "/service.status",
        resume_path = dir .. "/resume.request",
        controller_changed_path = dir .. "/CONTROLLER_CHANGED",
        koreader_state_path = dir .. "/koreader.state",
        consumed_seq_path = dir .. "/koreader.wake.seq",
    }, self)
end

function SystemService:available()
    return read_file(self.status_path) ~= nil or read_file(self.config_path) ~= nil
end

function SystemService:policy()
    local text = read_file(self.config_path) or ""
    return {
        enabled = bool01(parse(text, "ENABLED"), true),
        autostart = bool01(parse(text, "AUTOSTART"), true),
        resume_after_wake = bool01(parse(text, "RESUME_AFTER_WAKE"), true),
        pause_during_sleep = bool01(parse(text, "PAUSE_DURING_SLEEP"), true),
        desired_mode = parse(text, "DESIRED_MODE") or "AUTO",
    }
end

function SystemService:setDesired(enabled, mode)
    local p = self:policy()
    p.enabled = enabled and "1" or "0"
    if mode and mode ~= "" then p.desired_mode = tostring(mode) end
    local text = table.concat({
        "# DCPRO GhostGuard v0.8 persistent service policy",
        "ENABLED=" .. p.enabled,
        "AUTOSTART=" .. p.autostart,
        "RESUME_AFTER_WAKE=" .. p.resume_after_wake,
        "PAUSE_DURING_SLEEP=" .. p.pause_during_sleep,
        "DESIRED_MODE=" .. p.desired_mode,
        "UPDATED_UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "",
    }, "\n")
    return write_atomic(self.config_path, text)
end

function SystemService:markKOReader(state, mode, detail)
    local text = table.concat({
        "DCPRO_GHOSTGUARD_KOREADER_STATE_V1",
        "STATE=" .. tostring(state or "UNKNOWN"),
        "MODE=" .. tostring(mode or "NONE"),
        "DETAIL=" .. tostring(detail or "NONE"):gsub("[\r\n]", " "),
        "UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "",
    }, "\n")
    return write_atomic(self.koreader_state_path, text)
end

function SystemService:resumeRequest()
    local text = read_file(self.resume_path)
    if not text then return nil end
    return {
        seq = tonumber(parse(text, "WAKE_SEQ")) or 0,
        fingerprint_match = parse(text, "FINGERPRINT_MATCH") or "UNKNOWN",
        event = parse(text, "EVENT") or "UNKNOWN",
        controller = parse(text, "CONTROLLER") or "UNKNOWN",
        fingerprint = parse(text, "FINGERPRINT") or "NONE",
        desired_mode = parse(text, "DESIRED_MODE") or "AUTO",
        utc = parse(text, "UTC") or "UNKNOWN",
    }
end

function SystemService:controllerSafe()
    if read_file(self.controller_changed_path) then
        local req = self:resumeRequest()
        return false, req and ("controller fingerprint changed: " .. req.controller) or "controller fingerprint changed"
    end
    local req = self:resumeRequest()
    if req and req.fingerprint_match == "NO" then
        return false, "controller fingerprint mismatch after wake"
    end
    return true
end

function SystemService:consumeResumeRequest()
    local req = self:resumeRequest()
    if not req then return nil end
    local previous = tonumber((read_file(self.consumed_seq_path) or ""):match("(%d+)")) or 0
    if req.seq <= previous then return nil end
    write_atomic(self.consumed_seq_path, tostring(req.seq) .. "\n")
    return req
end

function SystemService:acknowledgeController()
    os.remove(self.controller_changed_path)
    local req = self:resumeRequest()
    if req and req.fingerprint_match == "NO" then
        local text = read_file(self.resume_path) or ""
        text = text:gsub("FINGERPRINT_MATCH=NO", "FINGERPRINT_MATCH=ACKNOWLEDGED", 1)
        write_atomic(self.resume_path, text)
    end
    return true
end

function SystemService:statusText()
    local status = read_file(self.status_path)
    if not status then return "System service: chưa chạy (KOReader vẫn fail-open)." end
    local power = parse(status, "POWER_STATE") or "unknown"
    local pid = parse(status, "PID") or "?"
    local controller = parse(status, "CONTROLLER") or "unknown"
    local event = parse(status, "EVENT") or "unknown"
    local fail_open = parse(status, "FAIL_OPEN") or "YES"
    local safe, detail = self:controllerSafe()
    local controller_state = safe and "OK" or ("CHANGED — " .. tostring(detail))
    return string.format(
        "System service v0.8: PID %s, power=%s\nController: %s (%s) — %s\nFail-open=%s; native grab/injection=OFF",
        pid, power, controller, event, controller_state, fail_open)
end

return SystemService
