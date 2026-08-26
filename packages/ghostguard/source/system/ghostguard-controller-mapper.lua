-- DCPRO GhostGuard v1.0 Phase 1.1 Controller Mapper
--
-- Purpose: learn the native input controller's actual ABS protocol/ranges
-- without grabbing or modifying input.
--
-- SAFETY:
--   * opens /dev/input/eventN O_RDONLY|O_NONBLOCK
--   * EVIOCGABS capability queries only
--   * NO EVIOCGRAB
--   * NO /dev/uinput
--   * NO write()/event injection
--   * produces an AXES_DETECTED profile at most; orientation stays UNVERIFIED

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then os.exit(2) end
local bit = require("bit")

ffi.cdef[[
typedef long ssize_t;
typedef unsigned long size_t;
typedef long time_t;
typedef long suseconds_t;
struct timeval { time_t tv_sec; suseconds_t tv_usec; };
struct input_event {
    struct timeval time;
    unsigned short type;
    unsigned short code;
    int value;
};
struct input_absinfo {
    int value;
    int minimum;
    int maximum;
    int fuzz;
    int flat;
    int resolution;
};
struct pollfd {
    int fd;
    short events;
    short revents;
};
int open(const char *pathname, int flags, ...);
int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
int ioctl(int fd, unsigned long request, ...);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

local EV_SYN, EV_ABS = 0, 3
local SYN_REPORT = 0
local ABS_X, ABS_Y = 0, 1
local ABS_MT_SLOT = 47
local ABS_MT_TOUCH_MAJOR = 48
local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
local ABS_MT_TRACKING_ID = 57

local O_RDONLY = 0
local O_NONBLOCK = 0x800
local POLLIN = 0x001

local device = arg[1]
local fingerprint_path = arg[2]
local profile_path = arg[3]
local raw_path = arg[4]
local duration_seconds = tonumber(arg[5]) or 90
if not device or not fingerprint_path or not profile_path or not raw_path then os.exit(2) end
if duration_seconds < 15 then duration_seconds = 15 end
if duration_seconds > 300 then duration_seconds = 300 end

-- Linux generic ioctl encoding.
local IOC_NRBITS, IOC_TYPEBITS, IOC_SIZEBITS = 8, 8, 14
local IOC_NRSHIFT = 0
local IOC_TYPESHIFT = IOC_NRSHIFT + IOC_NRBITS
local IOC_SIZESHIFT = IOC_TYPESHIFT + IOC_TYPEBITS
local IOC_DIRSHIFT = IOC_SIZESHIFT + IOC_SIZEBITS
local IOC_READ = 2
local EVDEV_TYPE_E = string.byte("E")

local function EVIOCGABS(code)
    return IOC_READ * 2^IOC_DIRSHIFT
        + EVDEV_TYPE_E * 2^IOC_TYPESHIFT
        + (0x40 + code) * 2^IOC_NRSHIFT
        + ffi.sizeof("struct input_absinfo") * 2^IOC_SIZESHIFT
end

local function read_kv(path)
    local out = {}
    local f = io.open(path, "rb")
    if not f then return out end
    for line in f:lines() do
        local k, v = line:match("^([A-Z0-9_]+)=(.*)$")
        if k then out[k] = v end
    end
    f:close()
    return out
end

local function atomic_write(path, text)
    local tmp = path .. ".tmp." .. tostring(os.time())
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    os.remove(path)
    local ok = os.rename(tmp, path)
    if not ok then os.remove(tmp) end
    return ok and true or false
end

local fingerprint = read_kv(fingerprint_path)
local fingerprint_hash = fingerprint.FINGERPRINT or "NONE"
local fingerprint_event = fingerprint.EVENT or "NONE"
local actual_event = device:match("([^/]+)$") or device

local fd = ffi.C.open(device, O_RDONLY + O_NONBLOCK)
if fd < 0 then os.exit(3) end

local capabilities = {}
for code = 0, 63 do
    local info = ffi.new("struct input_absinfo[1]")
    local rc = ffi.C.ioctl(fd, EVIOCGABS(code), info)
    if rc >= 0 then
        capabilities[code] = {
            minimum = tonumber(info[0].minimum),
            maximum = tonumber(info[0].maximum),
            fuzz = tonumber(info[0].fuzz),
            flat = tonumber(info[0].flat),
            resolution = tonumber(info[0].resolution),
        }
    end
end

local stats = {}
local raw_samples = {}
local RAW_SAMPLE_CAP = 512
local raw_events, abs_events, syn_frames = 0, 0, 0
local start_wall = os.time()

local function add_abs(code, value, ts)
    abs_events = abs_events + 1
    local s = stats[code]
    if not s then
        s = { count = 0, min = value, max = value, first = value, last = value, changes = 0 }
        stats[code] = s
    end
    s.count = s.count + 1
    if value < s.min then s.min = value end
    if value > s.max then s.max = value end
    if s.last ~= value then s.changes = s.changes + 1 end
    s.last = value

    if #raw_samples < RAW_SAMPLE_CAP then
        raw_samples[#raw_samples + 1] = table.concat({
            "ABS", tostring(ts), tostring(code), tostring(value)
        }, "|")
    end
end

local evbuf = ffi.new("struct input_event[1]")
local evsize = ffi.sizeof("struct input_event")
local pfd = ffi.new("struct pollfd[1]")
pfd[0].fd = fd
pfd[0].events = POLLIN

local deadline = os.time() + duration_seconds
while os.time() < deadline do
    local prc = ffi.C.poll(pfd, 1, 500)
    if prc > 0 and bit.band(tonumber(pfd[0].revents), POLLIN) ~= 0 then
        while true do
            local n = ffi.C.read(fd, evbuf, evsize)
            if tonumber(n) ~= evsize then break end
            raw_events = raw_events + 1
            local ev = evbuf[0]
            local t, code, value = tonumber(ev.type), tonumber(ev.code), tonumber(ev.value)
            local ts = tonumber(ev.time.tv_sec) * 1000000 + tonumber(ev.time.tv_usec)
            if t == EV_ABS then
                add_abs(code, value, ts)
            elseif t == EV_SYN and code == SYN_REPORT then
                syn_frames = syn_frames + 1
            end
        end
    end
end

ffi.C.close(fd)

local function observed(code)
    return stats[code] and stats[code].count > 0
end

local function cap(code)
    return capabilities[code] ~= nil
end

local function cap_range(code)
    local c = capabilities[code]
    if not c then return 0 end
    return math.max(0, (c.maximum or 0) - (c.minimum or 0))
end

local function observed_span(code)
    local s = stats[code]
    if not s then return 0 end
    return math.max(0, (s.max or 0) - (s.min or 0))
end

local protocol = "UNKNOWN"
local x_code, y_code = nil, nil
local axis_source = "NONE"

-- Conservative canonical pairing:
-- Prefer MT X/Y only when BOTH are kernel-supported and BOTH observed.
if cap(ABS_MT_POSITION_X) and cap(ABS_MT_POSITION_Y)
    and observed(ABS_MT_POSITION_X) and observed(ABS_MT_POSITION_Y) then
    x_code, y_code = ABS_MT_POSITION_X, ABS_MT_POSITION_Y
    axis_source = "ABS_MT_POSITION_XY"
    if cap(ABS_MT_SLOT) and observed(ABS_MT_SLOT) then
        protocol = "TYPE_B_MT"
    else
        protocol = "TYPE_A_MT"
    end
elseif cap(ABS_X) and cap(ABS_Y) and observed(ABS_X) and observed(ABS_Y) then
    x_code, y_code = ABS_X, ABS_Y
    axis_source = "ABS_XY"
    protocol = "SINGLE_TOUCH_OR_LEGACY_MT"
end

local confidence = 0.0
if x_code and y_code then
    confidence = confidence + 0.35
    confidence = confidence + 0.25
    if cap_range(x_code) > 100 and cap_range(y_code) > 100 then confidence = confidence + 0.15 end
    if observed_span(x_code) > 10 and observed_span(y_code) > 10 then confidence = confidence + 0.10 end
    if observed(ABS_MT_TRACKING_ID) or protocol == "SINGLE_TOUCH_OR_LEGACY_MT" then
        confidence = confidence + 0.10
    end
    if syn_frames >= 20 then confidence = confidence + 0.05 end
end
if confidence > 1.0 then confidence = 1.0 end

local fingerprint_match = fingerprint_hash ~= "NONE"
    and (fingerprint_event == "NONE" or fingerprint_event == actual_event)

local mapping_state = "UNSAFE"
local reason = "AXIS_PAIR_NOT_CONFIRMED"
if not fingerprint_match then
    mapping_state = "UNSAFE"
    reason = "FINGERPRINT_OR_EVENT_MISMATCH"
elseif x_code and y_code and confidence >= 0.75 then
    mapping_state = "AXES_DETECTED"
    reason = "ORIENTATION_CALIBRATION_REQUIRED"
elseif x_code and y_code then
    mapping_state = "LEARNING"
    reason = "INSUFFICIENT_CONFIDENCE"
end

local function v(code, field, default)
    if not code or not capabilities[code] then return default end
    local value = capabilities[code][field]
    if value == nil then return default end
    return value
end

local profile = table.concat({
    "DCPRO_GHOSTGUARD_NATIVE_MAPPING_V1",
    "VERSION=1.0.0-PHASE1.1",
    "UTC=" .. tostring(os.date("!%Y-%m-%dT%H:%M:%SZ")),
    "CONTROLLER_FINGERPRINT=" .. tostring(fingerprint_hash),
    "FINGERPRINT_EVENT=" .. tostring(fingerprint_event),
    "CAPTURE_EVENT=" .. tostring(actual_event),
    "FINGERPRINT_MATCH=" .. (fingerprint_match and "1" or "0"),
    "PROTOCOL=" .. protocol,
    "AXIS_SOURCE=" .. axis_source,
    "RAW_X_CODE=" .. tostring(x_code or -1),
    "RAW_Y_CODE=" .. tostring(y_code or -1),
    "RAW_X_MIN=" .. tostring(v(x_code, "minimum", 0)),
    "RAW_X_MAX=" .. tostring(v(x_code, "maximum", 0)),
    "RAW_Y_MIN=" .. tostring(v(y_code, "minimum", 0)),
    "RAW_Y_MAX=" .. tostring(v(y_code, "maximum", 0)),
    "RAW_X_OBS_MIN=" .. tostring(x_code and stats[x_code] and stats[x_code].min or 0),
    "RAW_X_OBS_MAX=" .. tostring(x_code and stats[x_code] and stats[x_code].max or 0),
    "RAW_Y_OBS_MIN=" .. tostring(y_code and stats[y_code] and stats[y_code].min or 0),
    "RAW_Y_OBS_MAX=" .. tostring(y_code and stats[y_code] and stats[y_code].max or 0),
    "MT_SLOT_CODE=" .. tostring(cap(ABS_MT_SLOT) and ABS_MT_SLOT or -1),
    "MT_TRACKING_ID_CODE=" .. tostring(cap(ABS_MT_TRACKING_ID) and ABS_MT_TRACKING_ID or -1),
    "TOUCH_MAJOR_CODE=" .. tostring(cap(ABS_MT_TOUCH_MAJOR) and ABS_MT_TOUCH_MAJOR or -1),
    "SWAP_XY=UNKNOWN",
    "INVERT_X=UNKNOWN",
    "INVERT_Y=UNKNOWN",
    "ROTATION=UNKNOWN",
    "ORIENTATION_STATE=UNVERIFIED",
    string.format("MAPPING_CONFIDENCE=%.3f", confidence),
    "MAPPING_STATE=" .. mapping_state,
    "MAPPING_REASON=" .. reason,
    "RAW_EVENTS=" .. tostring(raw_events),
    "ABS_EVENTS=" .. tostring(abs_events),
    "SYN_FRAMES=" .. tostring(syn_frames),
    "CAPTURE_SECONDS=" .. tostring(duration_seconds),
    "ACTUAL_SUPPRESSION=OFF",
    "INPUT_GRAB=OFF",
    "EVENT_INJECTION=OFF",
    "FAIL_OPEN=YES",
    "",
}, "\n")

if not atomic_write(profile_path, profile) then os.exit(4) end

local lines = {
    "DCPRO_GHOSTGUARD_CONTROLLER_MAPPER_RAW_V1",
    "VERSION=1.0.0-PHASE1.1",
    "CONTROLLER_FINGERPRINT=" .. tostring(fingerprint_hash),
    "EVENT=" .. tostring(actual_event),
    "CAPTURE_START_WALL=" .. tostring(start_wall),
    "CAPTURE_END_WALL=" .. tostring(os.time()),
    "",
    "[CAPABILITIES]",
}
for code = 0, 63 do
    local c = capabilities[code]
    if c then
        lines[#lines + 1] = table.concat({
            "CAP", tostring(code), tostring(c.minimum), tostring(c.maximum),
            tostring(c.fuzz), tostring(c.flat), tostring(c.resolution)
        }, "|")
    end
end

lines[#lines + 1] = ""
lines[#lines + 1] = "[OBSERVED_STATS]"
for code = 0, 63 do
    local s = stats[code]
    if s then
        lines[#lines + 1] = table.concat({
            "STAT", tostring(code), tostring(s.count), tostring(s.min),
            tostring(s.max), tostring(s.changes)
        }, "|")
    end
end

lines[#lines + 1] = ""
lines[#lines + 1] = "[RAW_SAMPLE_FIRST_512_ABS]"
for _, line in ipairs(raw_samples) do lines[#lines + 1] = line end
lines[#lines + 1] = ""

if not atomic_write(raw_path, table.concat(lines, "\n")) then os.exit(5) end
os.exit(0)
