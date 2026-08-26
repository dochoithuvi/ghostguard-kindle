-- DCPRO GhostGuard v1.0 Phase 1.2 Guided Orientation Calibration
-- Read-only calibration. Requires a Phase 1.1 native-mapping.profile.
--
-- SAFETY:
--   NO EVIOCGRAB
--   NO uinput
--   NO injection
--   NO suppression
--
-- Guided targets are presented by the shell wrapper via fbink. This reader
-- captures one completed contact per target and derives orientation only when
-- all five samples are spatially coherent.

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
struct pollfd { int fd; short events; short revents; };
int open(const char *pathname, int flags, ...);
int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

local EV_SYN, EV_ABS = 0, 3
local SYN_REPORT = 0
local ABS_MT_SLOT = 47
local ABS_MT_TRACKING_ID = 57
local O_RDONLY, O_NONBLOCK = 0, 0x800
local POLLIN = 0x001

local device = arg[1]
local mapping_path = arg[2]
local output_path = arg[3]
local command_path = arg[4]
local ack_path = arg[5]
if not device or not mapping_path or not output_path or not command_path or not ack_path then os.exit(2) end

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

local map = read_kv(mapping_path)
local x_code = tonumber(map.RAW_X_CODE or "-1")
local y_code = tonumber(map.RAW_Y_CODE or "-1")
local xmin, xmax = tonumber(map.RAW_X_MIN or "0"), tonumber(map.RAW_X_MAX or "0")
local ymin, ymax = tonumber(map.RAW_Y_MIN or "0"), tonumber(map.RAW_Y_MAX or "0")
if x_code < 0 or y_code < 0 or xmax <= xmin or ymax <= ymin then os.exit(3) end

local fd = ffi.C.open(device, O_RDONLY + O_NONBLOCK)
if fd < 0 then os.exit(4) end

local current_slot = 0
local slots = {}
local function slot(i)
    if not slots[i] then slots[i] = {active=false, x=nil, y=nil, changed=false, transition=nil} end
    return slots[i]
end

local samples = {}
local target_names = {"CENTER","TOP_LEFT","TOP_RIGHT","BOTTOM_LEFT","BOTTOM_RIGHT"}
local target_index = 1
local waiting = false

local function read_command()
    local f = io.open(command_path, "rb")
    if not f then return nil end
    local text = f:read("*a") or ""
    f:close()
    return text:match("TARGET=([A-Z_]+)")
end

local function write_ack(name, status, x, y)
    atomic_write(ack_path, table.concat({
        "TARGET=" .. tostring(name),
        "STATUS=" .. tostring(status),
        "X=" .. tostring(x or ""),
        "Y=" .. tostring(y or ""),
        "",
    }, "\n"))
end

local function normalize(v, minv, maxv)
    return (v - minv) / (maxv - minv)
end

local function classify_orientation()
    local s = {}
    for _, name in ipairs(target_names) do s[name] = samples[name] end
    for _, name in ipairs(target_names) do
        if not s[name] or s[name].x == nil or s[name].y == nil then
            return nil, "MISSING_SAMPLE_" .. name
        end
    end

    local function nx(p) return normalize(p.x, xmin, xmax) end
    local function ny(p) return normalize(p.y, ymin, ymax) end

    local tl,tr,bl,br,c = s.TOP_LEFT,s.TOP_RIGHT,s.BOTTOM_LEFT,s.BOTTOM_RIGHT,s.CENTER

    local x_horiz = math.abs(nx(tr)-nx(tl)) + math.abs(nx(br)-nx(bl))
    local x_vert  = math.abs(nx(bl)-nx(tl)) + math.abs(nx(br)-nx(tr))
    local y_horiz = math.abs(ny(tr)-ny(tl)) + math.abs(ny(br)-ny(bl))
    local y_vert  = math.abs(ny(bl)-ny(tl)) + math.abs(ny(br)-ny(tr))

    local swap_xy
    if x_horiz > x_vert * 1.8 and y_vert > y_horiz * 1.8 then
        swap_xy = 0
    elseif x_vert > x_horiz * 1.8 and y_horiz > y_vert * 1.8 then
        swap_xy = 1
    else
        return nil, "AXIS_SEPARATION_AMBIGUOUS"
    end

    local left_avg, right_avg, top_avg, bottom_avg
    if swap_xy == 0 then
        left_avg  = (nx(tl)+nx(bl))/2
        right_avg = (nx(tr)+nx(br))/2
        top_avg   = (ny(tl)+ny(tr))/2
        bottom_avg= (ny(bl)+ny(br))/2
    else
        left_avg  = (ny(tl)+ny(bl))/2
        right_avg = (ny(tr)+ny(br))/2
        top_avg   = (nx(tl)+nx(tr))/2
        bottom_avg= (nx(bl)+nx(br))/2
    end

    local invert_x = left_avg > right_avg and 1 or 0
    local invert_y = top_avg > bottom_avg and 1 or 0

    local horizontal_sep = math.abs(right_avg-left_avg)
    local vertical_sep = math.abs(bottom_avg-top_avg)
    if horizontal_sep < 0.35 or vertical_sep < 0.35 then
        return nil, "CORNER_SPAN_TOO_SMALL"
    end

    local cx = swap_xy == 0 and nx(c) or ny(c)
    local cy = swap_xy == 0 and ny(c) or nx(c)
    if invert_x == 1 then cx = 1-cx end
    if invert_y == 1 then cy = 1-cy end
    if cx < 0.20 or cx > 0.80 or cy < 0.20 or cy > 0.80 then
        return nil, "CENTER_SAMPLE_NOT_CENTRAL"
    end

    local rotation
    if swap_xy == 0 and invert_x == 0 and invert_y == 0 then rotation = 0
    elseif swap_xy == 1 and invert_x == 0 and invert_y == 1 then rotation = 90
    elseif swap_xy == 0 and invert_x == 1 and invert_y == 1 then rotation = 180
    elseif swap_xy == 1 and invert_x == 1 and invert_y == 0 then rotation = 270
    else rotation = "MIRRORED_OR_NONSTANDARD" end

    local confidence = math.min(1.0, 0.55 + 0.20*math.min(1,horizontal_sep) + 0.20*math.min(1,vertical_sep))
    return {
        swap_xy=swap_xy, invert_x=invert_x, invert_y=invert_y,
        rotation=rotation, confidence=confidence,
        horizontal_sep=horizontal_sep, vertical_sep=vertical_sep,
        center_x=cx, center_y=cy,
    }
end

write_ack(target_names[target_index], "WAITING", nil, nil)

local evbuf = ffi.new("struct input_event[1]")
local evsize = ffi.sizeof("struct input_event")
local pfd = ffi.new("struct pollfd[1]")
pfd[0].fd = fd
pfd[0].events = POLLIN

local deadline = os.time() + 180
while target_index <= #target_names and os.time() < deadline do
    local cmd = read_command()
    local expected = target_names[target_index]
    if cmd == expected then waiting = true end

    local prc = ffi.C.poll(pfd, 1, 250)
    if prc > 0 and bit.band(tonumber(pfd[0].revents), POLLIN) ~= 0 then
        while true do
            local n = ffi.C.read(fd, evbuf, evsize)
            if tonumber(n) ~= evsize then break end
            local ev = evbuf[0]
            local t, code, value = tonumber(ev.type), tonumber(ev.code), tonumber(ev.value)
            if t == EV_ABS then
                if code == ABS_MT_SLOT then
                    current_slot = value
                    slot(current_slot)
                else
                    local s = slot(current_slot)
                    if code == ABS_MT_TRACKING_ID then
                        s.changed = true
                        if value >= 0 then
                            s.active=true; s.x=nil; s.y=nil; s.transition="START"
                        else
                            s.active=false; s.transition="END"
                        end
                    elseif code == x_code then
                        s.x=value; s.changed=true
                    elseif code == y_code then
                        s.y=value; s.changed=true
                    end
                end
            elseif t == EV_SYN and code == SYN_REPORT then
                for _, s in pairs(slots) do
                    if waiting and s.changed and s.transition == "END" then
                        if s.x ~= nil and s.y ~= nil then
                            samples[expected] = {x=s.x,y=s.y}
                            write_ack(expected, "CAPTURED", s.x, s.y)
                            target_index = target_index + 1
                            waiting = false
                            if target_index <= #target_names then
                                write_ack(target_names[target_index], "WAITING", nil, nil)
                            end
                        else
                            write_ack(expected, "INCOMPLETE", s.x, s.y)
                        end
                        s.changed=false; s.transition=nil
                    elseif s.changed then
                        s.changed=false
                        if s.transition ~= "END" then s.transition=nil end
                    end
                end
            end
        end
    end
end

ffi.C.close(fd)

local result, reason = classify_orientation()
local lines = {
    "DCPRO_GHOSTGUARD_NATIVE_ORIENTATION_V1",
    "VERSION=1.0.0-PHASE1.2",
    "CONTROLLER_FINGERPRINT=" .. tostring(map.CONTROLLER_FINGERPRINT or "NONE"),
    "RAW_X_CODE=" .. tostring(x_code),
    "RAW_Y_CODE=" .. tostring(y_code),
}
for _, name in ipairs(target_names) do
    local s = samples[name]
    lines[#lines+1] = name .. "_X=" .. tostring(s and s.x or "")
    lines[#lines+1] = name .. "_Y=" .. tostring(s and s.y or "")
end

if result then
    lines[#lines+1] = "SWAP_XY=" .. tostring(result.swap_xy)
    lines[#lines+1] = "INVERT_X=" .. tostring(result.invert_x)
    lines[#lines+1] = "INVERT_Y=" .. tostring(result.invert_y)
    lines[#lines+1] = "ROTATION=" .. tostring(result.rotation)
    lines[#lines+1] = "ORIENTATION_STATE=VERIFIED"
    lines[#lines+1] = string.format("ORIENTATION_CONFIDENCE=%.3f", result.confidence)
    lines[#lines+1] = string.format("HORIZONTAL_SEPARATION=%.3f", result.horizontal_sep)
    lines[#lines+1] = string.format("VERTICAL_SEPARATION=%.3f", result.vertical_sep)
    lines[#lines+1] = "MAPPING_STATE=READY_FOR_SHADOW_VALIDATION"
    lines[#lines+1] = "MAPPING_REASON=GUIDED_FIVE_POINT_CALIBRATION_PASS"
else
    lines[#lines+1] = "SWAP_XY=UNKNOWN"
    lines[#lines+1] = "INVERT_X=UNKNOWN"
    lines[#lines+1] = "INVERT_Y=UNKNOWN"
    lines[#lines+1] = "ROTATION=UNKNOWN"
    lines[#lines+1] = "ORIENTATION_STATE=UNSAFE"
    lines[#lines+1] = "ORIENTATION_CONFIDENCE=0.000"
    lines[#lines+1] = "MAPPING_STATE=UNSAFE"
    lines[#lines+1] = "MAPPING_REASON=" .. tostring(reason or "UNKNOWN")
end
lines[#lines+1] = "ACTUAL_SUPPRESSION=OFF"
lines[#lines+1] = "INPUT_GRAB=OFF"
lines[#lines+1] = "EVENT_INJECTION=OFF"
lines[#lines+1] = "FAIL_OPEN=YES"
lines[#lines+1] = ""

if not atomic_write(output_path, table.concat(lines, "\n")) then os.exit(5) end
os.exit(result and 0 or 6)
