local CloudManager = {}
CloudManager.__index = CloudManager

local function safe_shell_token(value)
    local token = tostring(value or "")
    if token == "" or token:find("[^A-Za-z0-9_./-]") then
        return nil
    end
    return token
end

function CloudManager:new(config, storage, plugin_dir)
    return setmetatable({
        config = config,
        storage = storage,
        plugin_dir = plugin_dir,
        last_start_wall = 0,
        last_error = nil,
    }, self)
end

function CloudManager:workerPath()
    return self.plugin_dir .. "bin/cloud_upload.sh"
end

function CloudManager:bundledConfigPath()
    return self.plugin_dir .. "config/dochoithuvi_drive_token.conf"
end

function CloudManager:configPath()
    if self.storage:fileExists(self.config.cloud_token_file) then
        return self.config.cloud_token_file
    end
    local bundled = self:bundledConfigPath()
    if self.storage:fileExists(bundled) then
        return bundled
    end
    return nil
end

function CloudManager:isBusy()
    return self.storage:dirExists(self.config.cloud_lock_dir)
end

function CloudManager:start()
    local worker = self:workerPath()
    if not self.storage:fileExists(worker) then
        self.last_error = "CLOUD_WORKER_MISSING"
        return false, self.last_error
    end
    if self:isBusy() then return false, "Cloud worker đang chạy" end
    local config_path = self:configPath()
    if not config_path then
        self.last_error = "Thiếu cấu hình Cloud: " .. tostring(self.config.cloud_token_file)
        return false, self.last_error
    end

    local safe_worker = safe_shell_token(worker)
    local safe_config = safe_shell_token(config_path)
    if not safe_worker or not safe_config then
        self.last_error = "CLOUD_PATH_UNSAFE"
        return false, self.last_error
    end

    -- Avoid shell single-quote construction on Kindle. Both paths are validated
    -- to contain only a conservative filesystem-safe character set.
    local command = "DCPRO_TOKEN_FILE=" .. safe_config
        .. " /bin/sh " .. safe_worker .. " >/dev/null 2>&1 </dev/null &"
    local ok, why, code = os.execute(command)
    if ok == nil or ok == false or (type(ok) == "number" and ok ~= 0) then
        self.last_error = "Không thể chạy cloud worker: " .. tostring(why) .. "/" .. tostring(code)
        return false, self.last_error
    end
    self.last_start_wall = os.time()
    self.last_error = nil
    return true, "Đã khởi chạy upload nền. GhostGuard không tự bật Wi-Fi."
end

function CloudManager:statusText()
    local raw = self.storage:readFile(self.config.cloud_status_file)
    if raw and raw ~= "" then return raw end
    if self:isBusy() then return "DCPRO_GHOSTGUARD_CLOUD_V2\nSTATUS=RUNNING\nDETAIL=upload worker is active" end
    return "DCPRO_GHOSTGUARD_CLOUD_V2\nSTATUS=CHƯA_CHẠY\nDETAIL=Chưa có kết quả upload"
end

return CloudManager
