-- DCPRO GhostGuard v1.0 Phase 1.2D Native Contact Trace
-- Diagnostic only: captures raw input events and kernel ABS capabilities.
-- Opens the existing touchscreen event device read-only/nonblocking.
-- Does not suppress, alter, or inject input.

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then os.exit(2) end

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
struct pollfd { int fd; short events; short revents; };
int open(const char *pathname, int flags, ...);
int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
int ioctl(int fd, unsigned long request, ...);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

local O_RDONLY, O_NONBLOCK = 0, 0x800
local POLLIN = 0x001
local EV_SYN, EV_ABS = 0, 3
local SYN_REPORT = 0

local device = arg[1]
local fingerprint_path = arg[2]
local trace_path = arg[3]
local marker_path = arg[4]
local seconds = tonumber(arg[5]) or 54
if not device or not fingerprint_path or not trace_path or not marker_path then os.exit(2) end
if seconds < 15 then seconds = 15 end
if seconds > 180 then seconds = 180 end

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

local function read_marker()
    local f = io.open(marker_path, "rb")
    if not f then return "NONE" end
    local text = f:read("*a") or ""
    f:close()
    return text:match("TARGET=([A-Z0-9_]+)") or "NONE"
end

local fp = read_kv(fingerprint_path)
local fd = ffi.C.open(device, O_RDONLY + O_NONBLOCK)
if fd < 0 then os.exit(3) end

local capabilities = {}
for code = 0, 63 do
    local info = ffi.new("struct input_absinfo[1]")
    if ffi.C.ioctl(fd, EVIOCGABS(code), info) >= 0 then
        capabilities[#capabilities + 1] = table.concat({
            "CAP", tostring(code),
            tostring(tonumber(info[0].minimum)),
            tostring(tonumber(info[0].maximum)),
            tostring(tonumber(info[0].fuzz)),
            tostring(tonumber(info[0].flat)),
            tostring(tonumber(info[0].resolution)),
        }, "|")
    end
end

local lines = {
    "DCPRO_GHOSTGUARD_NATIVE_CONTACT_TRACE_V1",
    "VERSION=1.0.0-PHASE1.2D",
    "DEVICE=" .. tostring(device),
    "CONTROLLER_FINGERPRINT=" .. tostring(fp.FINGERPRINT or "NONE"),
    "FINGERPRINT_EVENT=" .. tostring(fp.EVENT or "NONE"),
    "CAPTURE_SECONDS=" .. tostring(seconds),
    "MODE=RAW_READ_ONLY_TRACE",
    "ACTUAL_SUPPRESSION=OFF",
    "INPUT_GRAB=OFF",
    "EVENT_INJECTION=OFF",
    "FAIL_OPEN=YES",
    "",
    "[CAPABILITIES]",
}
for _, l in ipairs(capabilities) do lines[#lines + 1] = l end
lines[#lines + 1] = ""
lines[#lines + 1] = "[EVENTS]"

local stats = {}
local frames, raw_events = 0, 0
local MAX_EVENTS = 12000
local dropped = 0
local current_marker = "NONE"

local evbuf = ffi.new("struct input_event[1]")
local evsize = ffi.sizeof("struct input_event")
local pfd = ffi.new("struct pollfd[1]")
pfd[0].fd = fd
pfd[0].events = POLLIN

local deadline = os.time() + seconds
while os.time() < deadline do
    local marker = read_marker()
    if marker ~= current_marker then
        current_marker = marker
        lines[#lines + 1] = table.concat({
            "MARK", tostring(os.time()), tostring(current_marker)
        }, "|")
    end

    local prc = ffi.C.poll(pfd, 1, 200)
    if prc > 0 and bit.band(tonumber(pfd[0].revents), POLLIN) ~= 0 then
        while true do
            local n = ffi.C.read(fd, evbuf, evsize)
            if tonumber(n) ~= evsize then break end

            raw_events = raw_events + 1
            local ev = evbuf[0]
            local t, code, value = tonumber(ev.type), tonumber(ev.code), tonumber(ev.value)
            local sec, usec = tonumber(ev.time.tv_sec), tonumber(ev.time.tv_usec)

            local key = tostring(t) .. ":" .. tostring(code)
            local s = stats[key]
            if not s then
                s = {type=t, code=code, count=0, min=value, max=value, changes=0, last=value}
                stats[key] = s
            end
            s.count = s.count + 1
            if value < s.min then s.min = value end
            if value > s.max then s.max = value end
            if s.last ~= value then s.changes = s.changes + 1 end
            s.last = value

            if t == EV_SYN and code == SYN_REPORT then frames = frames + 1 end

            if raw_events <= MAX_EVENTS then
                lines[#lines + 1] = table.concat({
                    "EV", tostring(sec), tostring(usec),
                    tostring(t), tostring(code), tostring(value),
                    tostring(current_marker)
                }, "|")
            else
                dropped = dropped + 1
            end
        end
    end
end

ffi.C.close(fd)

lines[#lines + 1] = ""
lines[#lines + 1] = "[SUMMARY]"
lines[#lines + 1] = "RAW_EVENTS=" .. tostring(raw_events)
lines[#lines + 1] = "SYN_FRAMES=" .. tostring(frames)
lines[#lines + 1] = "DROPPED_AFTER_CAP=" .. tostring(dropped)

local keys = {}
for k in pairs(stats) do keys[#keys + 1] = k end
table.sort(keys, function(a,b)
    local at,ac = a:match("^(%d+):(%d+)$")
    local bt,bc = b:match("^(%d+):(%d+)$")
    at,ac,bt,bc = tonumber(at),tonumber(ac),tonumber(bt),tonumber(bc)
    return at == bt and ac < bc or at < bt
end)
for _, k in ipairs(keys) do
    local s = stats[k]
    lines[#lines + 1] = table.concat({
        "STAT", tostring(s.type), tostring(s.code), tostring(s.count),
        tostring(s.min), tostring(s.max), tostring(s.changes)
    }, "|")
end
lines[#lines + 1] = ""

local tmp = trace_path .. ".tmp." .. tostring(os.time())
local f = io.open(tmp, "wb")
if not f then os.exit(4) end
f:write(table.concat(lines, "\n"))
f:close()
os.remove(trace_path)
if not os.rename(tmp, trace_path) then
    os.remove(tmp)
    os.exit(5)
end
os.exit(0)
