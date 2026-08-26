-- DCPRO GhostGuard v1.0 Phase 1.3 R2 - Mapped Shadow Runtime Ownership
--
-- READ-ONLY diagnostic observer.
-- Adds a per-process session ID, ownership lock, fingerprint binding and
-- session-consistent status/decision telemetry.
--
-- SAFETY:
--   ACTUAL_SUPPRESSION=OFF
--   INPUT_GRAB=OFF
--   EVENT_INJECTION=OFF
--   FAIL_OPEN=YES

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then os.exit(2) end

ffi.cdef[[
typedef long ssize_t;
typedef unsigned long size_t;
typedef long time_t;
typedef long suseconds_t;
typedef int pid_t;
struct timeval { time_t tv_sec; suseconds_t tv_usec; };
struct input_event {
    struct timeval time;
    unsigned short type;
    unsigned short code;
    int value;
};
int open(const char *pathname, int flags, ...);
int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
int getpid(void);
int kill(pid_t pid, int sig);
int mkdir(const char *pathname, unsigned int mode);
int rmdir(const char *pathname);
]]

local BUILD_ID = "MAPPED_SHADOW_V2_R2"
local VERSION = "1.0.0-PHASE1.3-R2"
local EV_ABS, EV_SYN = 3, 0
local SYN_REPORT = 0
local ABS_MT_SLOT = 47
local ABS_MT_TOUCH_MAJOR = 48
local ABS_MT_TRACKING_ID = 57
local O_RDONLY = 0

local device = arg[1]
local legacy_spool = arg[2]
local status_path = arg[3]
local pause_path = arg[4]
local approved_profile = arg[5]
if not device or not legacy_spool or not status_path then os.exit(2) end

local service_dir = status_path:match("^(.*)/native%-shadow%.status$")
    or status_path:match("^(.*)/[^/]+$")
    or "."
local map_path = service_dir .. "/native-mapping.profile"
local ori_path = service_dir .. "/native-orientation.profile"
local fp_path = service_dir .. "/controller.fingerprint"
local owner_path = service_dir .. "/native-shadow.owner"
local owner_lock = service_dir .. "/native-shadow.owner.lock"
local decisions_path = service_dir .. "/native-shadow-mapped-decisions.log"

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

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function exists(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local function atomic_write(path, text)
    local tmp = path .. ".tmp." .. tostring(ffi.C.getpid()) .. "." .. tostring(os.time())
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    os.remove(path)
    local ok = os.rename(tmp, path)
    if not ok then os.remove(tmp) end
    return ok and true or false
end

local function pid_alive(pid)
    pid = tonumber(pid)
    if not pid or pid <= 1 then return false end
    return ffi.C.kill(pid, 0) == 0
end

local function pid_is_shadow(pid)
    if not pid_alive(pid) then return false end
    local cmd = read_file("/proc/" .. tostring(pid) .. "/cmdline")
    if not cmd then return false end
    cmd = cmd:gsub("%z", " ")
    return cmd:find("ghostguard%-native%-shadow%.lua") ~= nil
end

local function release_owner()
    local owner = read_kv(owner_path)
    local mypid = tostring(ffi.C.getpid())
    if owner.PID == mypid and owner.BUILD_ID == BUILD_ID then
        os.remove(owner_path)
    end
    ffi.C.rmdir(owner_lock)
end

local function acquire_owner(session_id, fingerprint)
    local rc = ffi.C.mkdir(owner_lock, tonumber("0700", 8))
    if rc ~= 0 then
        local old = read_kv(owner_path)
        if old.PID and pid_is_shadow(old.PID) then
            return false, "LIVE_OWNER_PID_" .. tostring(old.PID)
        end
        -- Stale lock/owner: clean once, then retry atomically.
        os.remove(owner_path)
        ffi.C.rmdir(owner_lock)
        rc = ffi.C.mkdir(owner_lock, tonumber("0700", 8))
        if rc ~= 0 then return false, "OWNER_LOCK_BUSY" end
    end

    local text = table.concat({
        "DCPRO_GHOSTGUARD_NATIVE_SHADOW_OWNER_V1",
        "VERSION=" .. VERSION,
        "BUILD_ID=" .. BUILD_ID,
        "SESSION_ID=" .. session_id,
        "PID=" .. tostring(ffi.C.getpid()),
        "CONTROLLER_FINGERPRINT=" .. tostring(fingerprint),
        "START_WALL=" .. tostring(os.time()),
        "ACTUAL_SUPPRESSION=OFF",
        "INPUT_GRAB=OFF",
        "EVENT_INJECTION=OFF",
        "FAIL_OPEN=YES",
        "",
    }, "\n")

    if not atomic_write(owner_path, text) then
        ffi.C.rmdir(owner_lock)
        return false, "OWNER_FILE_WRITE_FAILED"
    end
    return true
end

local map = read_kv(map_path)
local ori = read_kv(ori_path)
local fp = read_kv(fp_path)

local map_fp = map.CONTROLLER_FINGERPRINT or "NONE"
local ori_fp = ori.CONTROLLER_FINGERPRINT or "NONE"
local live_fp = fp.FINGERPRINT or "NONE"

local x_code = tonumber(map.RAW_X_CODE or "-1")
local y_code = tonumber(map.RAW_Y_CODE or "-1")
local xmin, xmax = tonumber(map.RAW_X_MIN or "0"), tonumber(map.RAW_X_MAX or "0")
local ymin, ymax = tonumber(map.RAW_Y_MIN or "0"), tonumber(map.RAW_Y_MAX or "0")
local swap = tonumber(ori.SWAP_XY or "-1")
local invx = tonumber(ori.INVERT_X or "-1")
local invy = tonumber(ori.INVERT_Y or "-1")

local mapping_valid =
    map.MAPPING_STATE == "AXES_DETECTED"
    and ori.MAPPING_STATE == "READY_FOR_SHADOW_VALIDATION"
    and ori.ORIENTATION_STATE == "VERIFIED"
    and map_fp ~= "NONE"
    and map_fp == ori_fp
    and map_fp == live_fp
    and x_code >= 0 and y_code >= 0
    and xmax > xmin and ymax > ymin
    and (swap == 0 or swap == 1)
    and (invx == 0 or invx == 1)
    and (invy == 0 or invy == 1)

local pid = tonumber(ffi.C.getpid())
math.randomseed((os.time() % 2147483647) + (pid or 0) * 1103515245)
local session_id = string.format(
    "%X-%X-%06X",
    os.time(),
    pid or 0,
    math.random(0, 0xFFFFFF)
)

if not mapping_valid then
    atomic_write(status_path, table.concat({
        "DCPRO_GHOSTGUARD_NATIVE_MAPPED_SHADOW_R2",
        "VERSION=" .. VERSION,
        "BUILD_ID=" .. BUILD_ID,
        "SESSION_ID=" .. session_id,
        "PID=" .. tostring(pid),
        "STATUS=MAPPING_INVALID",
        "MODE=READ_ONLY_MAPPED_SHADOW",
        "ACTUAL_SUPPRESSION=OFF",
        "INPUT_GRAB=OFF",
        "EVENT_INJECTION=OFF",
        "FAIL_OPEN=YES",
        "UPDATED_WALL=" .. tostring(os.time()),
        "",
    }, "\n"))
    os.exit(7)
end

local owner_ok, owner_err = acquire_owner(session_id, live_fp)
if not owner_ok then
    -- Do not overwrite the live owner's status. Leave a side diagnostic instead.
    atomic_write(service_dir .. "/native-shadow-owner-conflict.status", table.concat({
        "DCPRO_GHOSTGUARD_NATIVE_SHADOW_OWNER_CONFLICT_V1",
        "VERSION=" .. VERSION,
        "BUILD_ID=" .. BUILD_ID,
        "SESSION_ID=" .. session_id,
        "PID=" .. tostring(pid),
        "STATUS=OWNER_CONFLICT",
        "DETAIL=" .. tostring(owner_err),
        "ACTUAL_SUPPRESSION=OFF",
        "FAIL_OPEN=YES",
        "",
    }, "\n"))
    os.exit(9)
end

local function cleanup()
    release_owner()
end

local function transform(x, y)
    if x == nil or y == nil then return nil, nil end
    local nx = (x - xmin) / (xmax - xmin)
    local ny = (y - ymin) / (ymax - ymin)
    if swap == 1 then nx, ny = ny, nx end
    if invx == 1 then nx = 1 - nx end
    if invy == 1 then ny = 1 - ny end
    nx = math.max(0, math.min(1, nx))
    ny = math.max(0, math.min(1, ny))
    return nx, ny
end

local raw_events = 0
local frames = 0
local completed_contacts = 0
local complete_contacts = 0
local incomplete_contacts = 0
local would_suppress = 0
local would_suppress_complete = 0
local would_suppress_incomplete = 0
local pass_complete = 0
local pass_incomplete = 0
local decision_lines = 0
local start_wall = os.time()

local function rotate(path)
    local f = io.open(path, "rb")
    if not f then return end
    local size = f:seek("end") or 0
    f:close()
    if size <= 262144 then return end
    os.remove(path .. ".1")
    os.rename(path, path .. ".1")
end

local function append_decision(kind, slot_index, sample, reason)
    if exists(pause_path) then return end
    rotate(decisions_path)
    local f = io.open(decisions_path, "ab")
    if not f then return end
    f:write(table.concat({
        tostring(kind),
        session_id,
        tostring(os.time()),
        tostring(slot_index or -1),
        sample.x == nil and "" or tostring(sample.x),
        sample.y == nil and "" or tostring(sample.y),
        sample.nx == nil and "" or string.format("%.5f", sample.nx),
        sample.ny == nil and "" or string.format("%.5f", sample.ny),
        tostring(sample.score or 0),
        tostring(sample.duration_us or 0),
        tostring(sample.min_major or ""),
        tostring(sample.path or 0),
        sample.incomplete and "1" or "0",
        sample.low_major and "1" or "0",
        sample.short and "1" or "0",
        sample.edge and "1" or "0",
        tostring(reason or "NONE"),
        BUILD_ID,
    }, "|") .. "\n")
    f:close()
    decision_lines = decision_lines + 1
end

local function write_status(detail)
    local owner = read_kv(owner_path)
    if owner.SESSION_ID ~= session_id or owner.PID ~= tostring(pid) then
        -- Lost ownership: fail open and exit without fighting another writer.
        cleanup()
        os.exit(10)
    end

    atomic_write(status_path, table.concat({
        "DCPRO_GHOSTGUARD_NATIVE_MAPPED_SHADOW_R2",
        "VERSION=" .. VERSION,
        "BUILD_ID=" .. BUILD_ID,
        "SESSION_ID=" .. session_id,
        "PID=" .. tostring(pid),
        "STATUS=RUNNING",
        "MODE=READ_ONLY_MAPPED_SHADOW",
        "DECISION_POLICY=MAPPED_STRONG_EVIDENCE_V2_R2",
        "CONTROLLER_FINGERPRINT=" .. live_fp,
        "RAW_X_CODE=" .. tostring(x_code),
        "RAW_Y_CODE=" .. tostring(y_code),
        "SWAP_XY=" .. tostring(swap),
        "INVERT_X=" .. tostring(invx),
        "INVERT_Y=" .. tostring(invy),
        "ACTUAL_SUPPRESSION=OFF",
        "INPUT_GRAB=OFF",
        "EVENT_INJECTION=OFF",
        "FAIL_OPEN=YES",
        "RAW_EVENTS=" .. tostring(raw_events),
        "FRAMES=" .. tostring(frames),
        "COMPLETED_CONTACTS=" .. tostring(completed_contacts),
        "COMPLETE_CONTACTS=" .. tostring(complete_contacts),
        "INCOMPLETE_CONTACTS=" .. tostring(incomplete_contacts),
        "WOULD_SUPPRESS=" .. tostring(would_suppress),
        "WOULD_SUPPRESS_COMPLETE=" .. tostring(would_suppress_complete),
        "WOULD_SUPPRESS_INCOMPLETE=" .. tostring(would_suppress_incomplete),
        "PASS_COMPLETE=" .. tostring(pass_complete),
        "PASS_INCOMPLETE=" .. tostring(pass_incomplete),
        "DECISION_LINES=" .. tostring(decision_lines),
        "DECISION_LOG=" .. decisions_path,
        "START_WALL=" .. tostring(start_wall),
        "UPDATED_WALL=" .. tostring(os.time()),
        "DETAIL=" .. tostring(detail or "NONE"),
        "",
    }, "\n"))
end

local function new_slot()
    return {
        active = false,
        x = nil, y = nil,
        start_us = nil,
        touch_major = nil,
        min_major = nil,
        path = 0,
        changed = false,
        transition = nil,
        lifetime_us = nil,
    }
end

local slots = {}
local current_slot = 0
local function get_slot(i)
    if not slots[i] then slots[i] = new_slot() end
    return slots[i]
end

local function event_us(ev)
    return tonumber(ev.time.tv_sec) * 1000000 + tonumber(ev.time.tv_usec)
end

local function score_slot(s, ts)
    local duration = tonumber(s.lifetime_us) or math.max(0, ts - (s.start_us or ts))
    local x, y = tonumber(s.x), tonumber(s.y)
    local nx, ny = transform(x, y)
    local incomplete = x == nil or y == nil
    local major = tonumber(s.min_major or s.touch_major)
    local low_major = major ~= nil and major <= 25
    local short = duration <= 120000
    local very_short = duration <= 60000
    local still = (tonumber(s.path) or 0) <= 60

    local edge = false
    if nx ~= nil and ny ~= nil then
        edge = math.min(nx, 1 - nx, ny, 1 - ny) <= 0.025
    end

    local score = 0
    if incomplete then score = score + 4 end
    if low_major then score = score + 2 end
    if short then score = score + 2 end
    if very_short then score = score + 1 end
    if still then score = score + 1 end
    if edge then score = score + 3 end

    -- Conservative R2 policy:
    -- incomplete coordinates alone never trigger.
    local strong = still and score >= 7 and (
        (low_major and short)
        or (edge and short)
    )

    return {
        x = x, y = y, nx = nx, ny = ny,
        score = score, duration_us = duration,
        min_major = major, path = s.path or 0,
        incomplete = incomplete,
        low_major = low_major,
        short = short,
        edge = edge,
        strong = strong,
    }
end

local fd = ffi.C.open(device, O_RDONLY)
if fd < 0 then
    atomic_write(status_path, table.concat({
        "DCPRO_GHOSTGUARD_NATIVE_MAPPED_SHADOW_R2",
        "VERSION=" .. VERSION,
        "BUILD_ID=" .. BUILD_ID,
        "SESSION_ID=" .. session_id,
        "PID=" .. tostring(pid),
        "STATUS=OPEN_FAILED",
        "MODE=READ_ONLY_MAPPED_SHADOW",
        "ACTUAL_SUPPRESSION=OFF",
        "FAIL_OPEN=YES",
        "",
    }, "\n"))
    cleanup()
    os.exit(3)
end

write_status("mapped shadow R2 active")

local evbuf = ffi.new("struct input_event[1]")
local evsize = ffi.sizeof("struct input_event")

while true do
    local n = ffi.C.read(fd, evbuf, evsize)
    if n == 0 then
        write_status("device EOF")
        break
    elseif n < 0 then
        write_status("read failed errno=" .. tostring(ffi.errno()))
        break
    elseif tonumber(n) == evsize then
        raw_events = raw_events + 1
        local ev = evbuf[0]
        local t, code, value = tonumber(ev.type), tonumber(ev.code), tonumber(ev.value)
        local ts = event_us(ev)

        if t == EV_ABS then
            if code == ABS_MT_SLOT then
                current_slot = value
                get_slot(current_slot)
            else
                local s = get_slot(current_slot)
                if code == ABS_MT_TRACKING_ID then
                    s.changed = true
                    if value >= 0 then
                        slots[current_slot] = new_slot()
                        s = slots[current_slot]
                        s.active = true
                        s.start_us = ts
                        s.transition = "START"
                        s.changed = true
                    else
                        s.lifetime_us = s.active and math.max(0, ts - (s.start_us or ts)) or 0
                        s.active = false
                        s.transition = "END"
                    end
                elseif code == x_code then
                    local old = s.x
                    s.x = value
                    s.changed = true
                    if s.active and old ~= nil then
                        s.path = s.path + math.abs(value - old)
                    end
                elseif code == y_code then
                    local old = s.y
                    s.y = value
                    s.changed = true
                    if s.active and old ~= nil then
                        s.path = s.path + math.abs(value - old)
                    end
                elseif code == ABS_MT_TOUCH_MAJOR then
                    s.touch_major = value
                    s.changed = true
                    if s.min_major == nil or value < s.min_major then s.min_major = value end
                end
            end
        elseif t == EV_SYN and code == SYN_REPORT then
            frames = frames + 1
            for slot_index, s in pairs(slots) do
                if s.changed and s.transition == "END" then
                    completed_contacts = completed_contacts + 1
                    local sample = score_slot(s, ts)

                    if sample.incomplete then
                        incomplete_contacts = incomplete_contacts + 1
                    else
                        complete_contacts = complete_contacts + 1
                    end

                    if sample.strong then
                        would_suppress = would_suppress + 1
                        if sample.incomplete then
                            would_suppress_incomplete = would_suppress_incomplete + 1
                        else
                            would_suppress_complete = would_suppress_complete + 1
                        end
                        append_decision("WOULD_SUPPRESS", slot_index, sample, "STRONG_MAPPED_V2_R2")
                    else
                        if sample.incomplete then
                            pass_incomplete = pass_incomplete + 1
                        else
                            pass_complete = pass_complete + 1
                        end

                        -- Sparse baseline logging only; counters remain exhaustive.
                        if completed_contacts % 32 == 0 then
                            append_decision("PASS_SAMPLE", slot_index, sample, "BASELINE")
                        end
                    end

                    if completed_contacts % 32 == 0 then
                        write_status("contact checkpoint")
                    end
                    slots[slot_index] = new_slot()
                elseif s.changed then
                    s.changed = false
                    s.transition = nil
                    s.lifetime_us = nil
                end
            end
        end
    end
end

ffi.C.close(fd)
cleanup()
os.exit(0)
