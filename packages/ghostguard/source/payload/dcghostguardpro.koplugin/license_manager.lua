local LicenseManager = {}
LicenseManager.__index = LicenseManager

local REQUIRED = {
    "license_format", "serial", "customer", "issued_at", "expire",
    "features", "license_id", "key_id", "sig_alg", "sig",
}

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_serial(v)
    local s = tostring(v or ""):upper():gsub("[^A-Z0-9]", "")
    if s == "" then return nil end
    return s
end

local function valid_date(s)
    if not tostring(s):match("^%d%d%d%d%-%d%d%-%d%d$") then return false end
    local y, m, d = tonumber(s:sub(1, 4)), tonumber(s:sub(6, 7)), tonumber(s:sub(9, 10))
    if not y or y < 2020 or not m or m < 1 or m > 12 or not d or d < 1 or d > 31 then return false end
    local md = {31,28,31,30,31,30,31,31,30,31,30,31}
    if y % 400 == 0 or (y % 4 == 0 and y % 100 ~= 0) then md[2] = 29 end
    return d <= md[m]
end

local function date_num(s)
    return tonumber((s or ""):gsub("-", "")) or 0
end

local function parse_license(raw)
    local f, c = {}, {}
    raw = tostring(raw or ""):gsub("\r", "")
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" and not line:match("^%s*#") then
            local k, v = line:match("^([a-z_]+)=(.*)$")
            if not k then return nil, "MALFORMED_LICENSE_LINE" end
            c[k] = (c[k] or 0) + 1
            if c[k] > 1 then return nil, "DUPLICATE_FIELD_" .. k end
            f[k] = v
        end
    end
    for _, k in ipairs(REQUIRED) do
        if c[k] ~= 1 then return nil, "FIELD_" .. k .. "_MISSING" end
    end
    return f
end

local function feature_allowed(features)
    local n = "," .. tostring(features or ""):lower():gsub("%s", "") .. ","
    return n:find(",ghostguard,", 1, true) ~= nil or n:find(",ultimate,", 1, true) ~= nil
end

local function canonical(f)
    return table.concat({
        "license_format=" .. f.license_format,
        "serial=" .. f.serial,
        "customer=" .. f.customer,
        "issued_at=" .. f.issued_at,
        "expire=" .. f.expire,
        "features=" .. f.features,
        "license_id=" .. f.license_id,
        "key_id=" .. f.key_id,
        "sig_alg=" .. f.sig_alg,
        "",
    }, "\n")
end

local function load_keyring(plugin_dir)
    local chunk, err = loadfile(plugin_dir .. "keys/keyring.lua")
    if not chunk then return nil, "KEYRING_LOAD_FAILED:" .. tostring(err) end
    local ok, ring = pcall(chunk)
    if not ok or type(ring) ~= "table" then return nil, "KEYRING_INVALID" end
    return ring
end

function LicenseManager:new(config, storage, plugin_dir, device_id)
    local crypto_ok, crypto = pcall(dofile, plugin_dir .. "license_crypto.lua")
    local online_ok, Online = pcall(dofile, plugin_dir .. "online_license.lua")
    local o = setmetatable({
        config = config,
        crypto = crypto_ok and crypto or nil,
        crypto_error = crypto_ok and nil or tostring(crypto),
        storage = storage,
        plugin_dir = plugin_dir,
        device_id = device_id,
        license_path = plugin_dir .. "license.key",
        state_path = config.data_dir .. "/license_last_date",
        debug_path = config.data_dir .. "/license_debug.log",
        last_ok = false,
        last_detail = "NOT_CHECKED",
        last_checked_wall = 0,
        online = nil,
        online_error = online_ok and nil or tostring(Online),
    }, self)
    if online_ok and crypto_ok then
        o.online = Online:new(config, storage, plugin_dir, device_id, crypto)
    end
    return o
end

function LicenseManager:writeDebug(detail, fields, source)
    local text = table.concat({
        "DCPRO_GHOSTGUARD_LICENSE_DEBUG_V42",
        "TIME=" .. os.date("%Y-%m-%d %H:%M:%S"),
        "DEVICE_ID=" .. tostring(self.device_id),
        "SOURCE=" .. tostring(source or "UNKNOWN"),
        "LICENSE_PATH=" .. tostring(self.license_path),
        "FORMAT=" .. tostring(fields and fields.license_format or "UNKNOWN"),
        "KEY_ID=" .. tostring(fields and fields.key_id or "UNKNOWN"),
        "LICENSE_ID=" .. tostring(fields and fields.license_id or "UNKNOWN"),
        "RESULT=" .. tostring(detail or "UNKNOWN"),
        "",
    }, "\n")
    self.storage:writeAtomic(self.debug_path, text)
end

-- One monotonic calendar floor is shared by local and online licensing.
-- A normal NTP correction within the same day is harmless, but moving the
-- Kindle to an earlier calendar day cannot make an expired trial valid again.
function LicenseManager:clockGuard()
    local today = os.date("%Y-%m-%d")
    if not valid_date(today) then return false, "SYSTEM_DATE_INVALID", today end
    local last = trim(self.storage:readFile(self.state_path) or "")
    if last ~= "" and valid_date(last) and date_num(today) < date_num(last) then
        return false, "CLOCK_ROLLBACK_DETECTED;LAST=" .. last .. ";TODAY=" .. today, today
    end
    return true, "CLOCK_OK", today
end

function LicenseManager:rememberToday(today)
    today = today or os.date("%Y-%m-%d")
    if valid_date(today) then
        local last = trim(self.storage:readFile(self.state_path) or "")
        if last == "" or not valid_date(last) or date_num(today) > date_num(last) then
            self.storage:writeAtomic(self.state_path, today .. "\n")
        elseif date_num(today) == date_num(last) then
            -- Keep the state file present even if a previous write was partial.
            self.storage:writeAtomic(self.state_path, last .. "\n")
        end
    end
end

function LicenseManager:localCheck()
    if not self.storage:fileExists(self.license_path) then return false, "MISSING_PLUGIN_LICENSE_KEY" end
    local raw = self.storage:readFile(self.license_path)
    if not raw or raw == "" then return false, "EMPTY_PLUGIN_LICENSE_KEY" end
    local f, perr = parse_license(raw)
    if not f then return false, perr end

    f.serial = normalize_serial(f.serial) or ""
    f.customer = trim(f.customer)
    f.issued_at = trim(f.issued_at)
    f.expire = trim(f.expire):lower()
    f.features = trim(f.features):lower():gsub("%s", "")
    f.license_id = trim(f.license_id)
    f.key_id = trim(f.key_id)
    f.sig_alg = trim(f.sig_alg):upper()
    f.sig = trim(f.sig)

    if f.license_format ~= "4" then return false, "UNSUPPORTED_LICENSE_FORMAT", f end
    if f.sig_alg ~= "RSA-SHA256" then return false, "UNSUPPORTED_SIGNATURE_ALGORITHM", f end
    if f.customer == "" or f.customer:find("[\r\n]") then return false, "CUSTOMER_INVALID", f end
    if f.license_id == "" or not f.license_id:match("^[A-Za-z0-9_.-]+$") then return false, "LICENSE_ID_INVALID", f end
    if f.key_id == "" or not f.key_id:match("^[A-Za-z0-9_.-]+$") then return false, "KEY_ID_INVALID", f end

    local input = normalize_serial(self.device_id)
    if not input then return false, "SERIAL_UNAVAILABLE", f end
    if f.serial ~= input then return false, "SERIAL_MISMATCH", f end
    if not feature_allowed(f.features) then return false, "FEATURE_GHOSTGUARD_NOT_GRANTED", f end

    local clock_ok, clock_detail, today = self:clockGuard()
    if not clock_ok then return false, clock_detail, f end
    if not valid_date(f.issued_at) then return false, "ISSUED_AT_INVALID", f end
    if date_num(today) < date_num(f.issued_at) then return false, "CLOCK_BEFORE_ISSUE_DATE", f end
    if f.expire ~= "lifetime" then
        if not valid_date(f.expire) then return false, "EXPIRE_INVALID", f end
        if date_num(today) > date_num(f.expire) then return false, "LICENSE_EXPIRED", f end
    end

    local ring, rerr = load_keyring(self.plugin_dir)
    if not ring then return false, rerr, f end
    local filename = ring[f.key_id]
    if type(filename) ~= "string" or not filename:match("^[A-Za-z0-9_.-]+%.pem$") then return false, "UNKNOWN_KEY_ID", f end
    if not self.crypto then return false, "LICENSE_CRYPTO_LOAD_FAILED:" .. tostring(self.crypto_error), f end
    local call_ok, verified, verr = pcall(self.crypto.verify, self.plugin_dir .. "keys/" .. filename, canonical(f), f.sig)
    if not call_ok then return false, "LICENSE_CRYPTO_RUNTIME_FAILED:" .. tostring(verified), f end
    if not verified then return false, verr or "SIGNATURE_MISMATCH", f end

    self:rememberToday(today)
    return true, "V4_RSA_VALID;LICENSE_ID=" .. f.license_id .. ";EXPIRE=" .. f.expire, f
end

function LicenseManager:check(force)
    local now = os.time()
    -- Never reuse a cached successful answer after the wall clock moves back.
    if not force and self.last_checked_wall > 0 and now >= self.last_checked_wall and
       now - self.last_checked_wall < (self.config.license_recheck_seconds or 30) then
        return self.last_ok, self.last_detail
    end
    self.last_checked_wall = now

    local clock_ok, clock_detail, today = self:clockGuard()
    if not clock_ok then
        self.last_ok = false
        self.last_detail = clock_detail
        self:writeDebug(self.last_detail, nil, "CLOCK")
        return false, self.last_detail
    end

    local local_ok, local_detail, fields = self:localCheck()
    local online_cache, cache_detail
    if self.online then online_cache, cache_detail = self.online:readCache() end

    if online_cache then
        local entry = online_cache.entry
        local online_ok, online_detail = self.online:evaluateEntry(entry)
        -- A signed registry entry may explicitly revoke/expire a device and must
        -- continue to override an older local key.
        if entry and online_ok == false then
            self.last_ok = false
            self.last_detail = online_detail .. ";SOURCE=SIGNED_CACHE"
            self:writeDebug(self.last_detail, fields, "ONLINE")
            return false, self.last_detail
        end
        if entry and online_ok == true then
            local grace = self.config.online_license_grace_seconds or 604800
            if online_cache.age <= grace or local_ok then
                self:rememberToday(today)
                self.last_ok = true
                self.last_detail = online_detail .. ";SOURCE=" ..
                    (online_cache.age <= grace and "ONLINE_CACHE" or "LOCAL_PLUS_STALE_CACHE")
                self:writeDebug(self.last_detail, fields, "ONLINE")
                return true, self.last_detail
            end
        end
    end

    if local_ok then
        self:rememberToday(today)
        self.last_ok = true
        self.last_detail = local_detail .. ";SOURCE=LOCAL"
        self:writeDebug(self.last_detail, fields, "LOCAL")
        return true, self.last_detail
    end

    self.last_ok = false
    self.last_detail = (online_cache and online_cache.entry and "ONLINE_CACHE_STALE_NO_LOCAL")
        or cache_detail or local_detail or "NO_VALID_LICENSE"
    self:writeDebug(self.last_detail, fields, "NONE")
    return false, self.last_detail
end

function LicenseManager:syncOnline()
    if not self.online then return false, "ONLINE_MODULE_UNAVAILABLE:" .. tostring(self.online_error) end
    local clock_ok, clock_detail = self:clockGuard()
    if not clock_ok then
        self.last_ok = false
        self.last_detail = clock_detail
        self:writeDebug(self.last_detail, nil, "CLOCK")
        return false, clock_detail
    end
    local ok, detail = self.online:sync()
    if ok then
        self.last_checked_wall = 0
        local allowed, policy = self:check(true)
        return true, detail .. ";POLICY=" .. tostring(policy), allowed, policy
    end
    return false, detail
end

function LicenseManager:statusText()
    local ok, detail = self:check(false)
    return (ok and "HỢP LỆ" or "KHÔNG HỢP LỆ") .. " — " .. tostring(detail)
end

function LicenseManager:activationHelp()
    return "GhostGuard v4.1 hỗ trợ 2 cách kích hoạt:\n1) signed online registry; hoặc\n2) license.key RSA v4 tại:\n"
        .. self.license_path .. "\n\nSerial máy: " .. tostring(self.device_id)
        .. "\n\nSTOP/SAFE_MODE luôn hoạt động khi license lỗi.\nLog: " .. tostring(self.debug_path)
end

return LicenseManager
