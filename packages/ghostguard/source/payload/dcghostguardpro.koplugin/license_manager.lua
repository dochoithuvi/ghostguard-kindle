local LicenseManager = {}
LicenseManager.__index = LicenseManager

local REQUIRED = {
    "license_format", "serial", "customer", "issued_at", "expire", "features",
    "license_id", "key_id", "sig_alg", "sig",
}

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_serial(value)
    local serial = tostring(value or ""):upper():gsub("[^A-Z0-9]", "")
    if serial == "" then return nil end
    return serial
end

local function valid_date(s)
    if not tostring(s):match("^%d%d%d%d%-%d%d%-%d%d$") then return false end
    local y,m,d = tonumber(s:sub(1,4)), tonumber(s:sub(6,7)), tonumber(s:sub(9,10))
    if not y or y < 2020 or not m or m < 1 or m > 12 or not d or d < 1 or d > 31 then return false end
    local mdays = {31,28,31,30,31,30,31,31,30,31,30,31}
    if (y % 400 == 0) or (y % 4 == 0 and y % 100 ~= 0) then mdays[2] = 29 end
    return d <= mdays[m]
end

local function date_num(s) return tonumber((s or ""):gsub("-", "")) or 0 end

local function parse_license(raw)
    local fields, counts = {}, {}
    raw = tostring(raw or ""):gsub("\r", "")
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" and not line:match("^%s*#") then
            local k,v = line:match("^([a-z_]+)=(.*)$")
            if not k then return nil, "MALFORMED_LICENSE_LINE" end
            counts[k] = (counts[k] or 0) + 1
            if counts[k] > 1 then return nil, "DUPLICATE_FIELD_" .. k end
            fields[k] = v
        end
    end
    for _,k in ipairs(REQUIRED) do
        if counts[k] ~= 1 then return nil, "FIELD_" .. k .. "_MISSING" end
    end
    return fields
end

local function feature_allowed(features)
    local n = "," .. tostring(features or ""):lower():gsub("%s", "") .. ","
    return n:find(",ghostguard,", 1, true) ~= nil or n:find(",ultimate,", 1, true) ~= nil
end

local function canonical(fields)
    return table.concat({
        "license_format=" .. fields.license_format,
        "serial=" .. fields.serial,
        "customer=" .. fields.customer,
        "issued_at=" .. fields.issued_at,
        "expire=" .. fields.expire,
        "features=" .. fields.features,
        "license_id=" .. fields.license_id,
        "key_id=" .. fields.key_id,
        "sig_alg=" .. fields.sig_alg,
        "",
    }, "\n")
end

local function load_keyring(plugin_dir)
    local path = plugin_dir .. "keys/keyring.lua"
    local chunk, err = loadfile(path)
    if not chunk then return nil, "KEYRING_LOAD_FAILED:" .. tostring(err) end
    local ok, ring = pcall(chunk)
    if not ok or type(ring) ~= "table" then return nil, "KEYRING_INVALID" end
    return ring
end

function LicenseManager:new(config, storage, plugin_dir, device_id)
    local crypto_ok, crypto = pcall(dofile, plugin_dir .. "license_crypto.lua")
    return setmetatable({
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
    }, self)
end

function LicenseManager:writeDebug(detail, fields)
    local text = table.concat({
        "DCPRO_GHOSTGUARD_LICENSE_DEBUG_V4",
        "TIME=" .. os.date("%Y-%m-%d %H:%M:%S"),
        "DEVICE_ID=" .. tostring(self.device_id),
        "LICENSE_PATH=" .. tostring(self.license_path),
        "FORMAT=" .. tostring(fields and fields.license_format or "UNKNOWN"),
        "KEY_ID=" .. tostring(fields and fields.key_id or "UNKNOWN"),
        "LICENSE_ID=" .. tostring(fields and fields.license_id or "UNKNOWN"),
        "RESULT=" .. tostring(detail or "UNKNOWN"),
        "",
    }, "\n")
    self.storage:writeAtomic(self.debug_path, text)
end

function LicenseManager:deny(detail, fields)
    self.last_ok, self.last_detail = false, detail
    self:writeDebug(detail, fields)
    return false, detail
end

function LicenseManager:check(force)
    local now = os.time()
    if not force and self.last_checked_wall > 0
        and now - self.last_checked_wall < (self.config.license_recheck_seconds or 30) then
        return self.last_ok, self.last_detail
    end
    self.last_checked_wall = now

    if not self.storage:fileExists(self.license_path) then
        return self:deny("MISSING_PLUGIN_LICENSE_KEY")
    end
    local raw = self.storage:readFile(self.license_path)
    if not raw or raw == "" then return self:deny("EMPTY_PLUGIN_LICENSE_KEY") end
    local f, perr = parse_license(raw)
    if not f then return self:deny(perr) end

    f.serial = normalize_serial(f.serial) or ""
    f.customer = trim(f.customer)
    f.issued_at = trim(f.issued_at)
    f.expire = trim(f.expire):lower()
    f.features = trim(f.features):lower():gsub("%s", "")
    f.license_id = trim(f.license_id)
    f.key_id = trim(f.key_id)
    f.sig_alg = trim(f.sig_alg):upper()
    f.sig = trim(f.sig)

    if f.license_format ~= "4" then return self:deny("UNSUPPORTED_LICENSE_FORMAT", f) end
    if f.sig_alg ~= "RSA-SHA256" then return self:deny("UNSUPPORTED_SIGNATURE_ALGORITHM", f) end
    if f.customer == "" or f.customer:find("[\r\n]") then return self:deny("CUSTOMER_INVALID", f) end
    if f.license_id == "" or not f.license_id:match("^[A-Za-z0-9_.-]+$") then return self:deny("LICENSE_ID_INVALID", f) end
    if f.key_id == "" or not f.key_id:match("^[A-Za-z0-9_.-]+$") then return self:deny("KEY_ID_INVALID", f) end

    local input_serial = normalize_serial(self.device_id)
    if not input_serial then return self:deny("SERIAL_UNAVAILABLE", f) end
    if f.serial ~= input_serial then return self:deny("SERIAL_MISMATCH", f) end
    if not feature_allowed(f.features) then return self:deny("FEATURE_GHOSTGUARD_NOT_GRANTED", f) end

    local today = os.date("%Y-%m-%d")
    if not valid_date(today) then return self:deny("SYSTEM_DATE_INVALID", f) end
    if not valid_date(f.issued_at) then return self:deny("ISSUED_AT_INVALID", f) end
    if date_num(today) < date_num(f.issued_at) then return self:deny("CLOCK_BEFORE_ISSUE_DATE", f) end

    local last = trim(self.storage:readFile(self.state_path) or "")
    if last ~= "" and valid_date(last) and date_num(today) < date_num(last) then
        return self:deny("CLOCK_ROLLBACK_DETECTED", f)
    end

    if f.expire ~= "lifetime" then
        if not valid_date(f.expire) then return self:deny("EXPIRE_INVALID", f) end
        if date_num(today) > date_num(f.expire) then return self:deny("LICENSE_EXPIRED", f) end
    end

    local ring, rerr = load_keyring(self.plugin_dir)
    if not ring then return self:deny(rerr, f) end
    local filename = ring[f.key_id]
    if type(filename) ~= "string" or not filename:match("^[A-Za-z0-9_.-]+%.pem$") then
        return self:deny("UNKNOWN_KEY_ID", f)
    end

    if not self.crypto then return self:deny("LICENSE_CRYPTO_LOAD_FAILED:" .. tostring(self.crypto_error), f) end
    local call_ok, verified, verr = pcall(self.crypto.verify, self.plugin_dir .. "keys/" .. filename, canonical(f), f.sig)
    if not call_ok then return self:deny("LICENSE_CRYPTO_RUNTIME_FAILED:" .. tostring(verified), f) end
    if not verified then return self:deny(verr or "SIGNATURE_MISMATCH", f) end

    -- Advance anti-rollback state only after the RSA signature and all policy checks pass.
    self.storage:writeAtomic(self.state_path, today .. "\n")
    self.last_ok = true
    self.last_detail = "V4_RSA_VALID;LICENSE_ID=" .. f.license_id .. ";EXPIRE=" .. f.expire
    self:writeDebug(self.last_detail, f)
    return true, self.last_detail
end

function LicenseManager:statusText()
    local ok, detail = self:check(false)
    return (ok and "HỢP LỆ" or "KHÔNG HỢP LỆ") .. " — " .. tostring(detail)
end

function LicenseManager:activationHelp()
    return "GhostGuard v4 cần license.key RSA hợp lệ tại:\n" .. self.license_path
        .. "\n\nSerial máy: " .. tostring(self.device_id)
        .. "\n\nLicense v3 không dùng được trên nhánh public v4."
        .. "\nLog kiểm tra: " .. tostring(self.debug_path)
end

return LicenseManager
