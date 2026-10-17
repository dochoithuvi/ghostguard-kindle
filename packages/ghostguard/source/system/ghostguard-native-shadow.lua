-- DCPRO GhostGuard v1.0 Phase 1 native shadow decision observer.
--
-- SAFETY CONTRACT:
--   * READ-ONLY /dev/input/eventN
--   * NO EVIOCGRAB
--   * NO /dev/uinput
--   * NO event injection
--   * NO actual suppression
--
-- Phase 1 adds a "would suppress" decision trace so real Kindle-native
-- behavior can be measured before any interception design is enabled.

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
int open(const char *pathname, int flags, ...);
int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
]]

local EV_ABS, EV_SYN = 3, 0
local SYN_REPORT = 0
local ABS_MT_SLOT = 47
local ABS_MT_TOUCH_MAJOR = 48
local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
local ABS_MT_TRACKING_ID = 57
local O_RDONLY = 0

local device = arg[1]
local spool = arg[2]
local status_path = arg[3]
local pause_path = arg[4]
local approved_profile = arg[5]
if not device or not spool or not status_path then os.exit(2) end

local decision_path = status_path:gsub("%.status$", "") .. "-decisions.log"

local function exists(path)
    if not path or path == "" then return false end
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local function read_screen_width(path)
    if not path or path == "" then return 0 end
    local f = io.open(path, "rb")
    if not f then return 0 end
    local width = 0
    for line in f:lines() do
        local value = line:match("^SCREEN_WIDTH=(%d+)")
        if value then width = tonumber(value) or 0; break end
    end
    f:close()
    return width
end

local screen_width = read_screen_width(approved_profile)

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

local candidate_count = 0
local raw_events = 0
local frame_count = 0
local completed_contacts = 0
local would_suppress_count = 0
local sampled_pass_count = 0
local start_wall = os.time()

local function write_status(state, detail)
    atomic_write(status_path, table.concat({
        "DCPRO_GHOSTGUARD_NATIVE_SHADOW_DECISION_V1",
        "VERSION=1.0.0-PHASE1",
        "STATUS=" .. tostring(state or "UNKNOWN"),
        "DEVICE=" .. tostring(device),
        "MODE=READ_ONLY_SHADOW_DECISION",
        "DECISION_POLICY=STRONG_EVIDENCE_V1",
        "ACTUAL_SUPPRESSION=OFF",
        "INPUT_GRAB=OFF",
        "EVENT_INJECTION=OFF",
        "FAIL_OPEN=YES",
        "RAW_EVENTS=" .. tostring(raw_events),
        "FRAMES=" .. tostring(frame_count),
        "COMPLETED_CONTACTS=" .. tostring(completed_contacts),
        "CANDIDATES=" .. tostring(candidate_count),
        "WOULD_SUPPRESS=" .. tostring(would_suppress_count),
        "PASS_SAMPLES=" .. tostring(sampled_pass_count),
        "SCREEN_WIDTH=" .. tostring(screen_width),
        "DECISION_LOG=" .. tostring(decision_path),
        "START_WALL=" .. tostring(start_wall),
        "UPDATED_WALL=" .. tostring(os.time()),
        "DETAIL=" .. tostring(detail or "NONE"),
        "",
    }, "\n"))
end

local function rotate_path_if_needed(path)
    local f = io.open(path, "rb")
    if not f then return end
    local size = f:seek("end") or 0
    f:close()
    if size <= 131072 then return end
    os.remove(path .. ".1")
    os.rename(path, path .. ".1")
end

local function rotate_if_needed()
    rotate_path_if_needed(spool)
end

local function append_decision(kind, slot, sample)
    if exists(pause_path) then return end
    rotate_path_if_needed(decision_path)
    local f = io.open(decision_path, "ab")
    if not f then return end
    f:write(table.concat({
        tostring(kind),
        tostring(os.time()),
        tostring(slot or -1),
        sample.x == nil and "" or tostring(sample.x),
        sample.y == nil and "" or tostring(sample.y),
        tostring(sample.score or 0),
        sample.incomplete and "1" or "0",
        sample.low_major and "1" or "0",
        sample.short and "1" or "0",
        sample.extreme_edge and "1" or "0",
        sample.near_edge and "1" or "0",
        tostring(sample.path_px or 0),
        tostring(sample.duration_us or 0),
    }, "|") .. "\n")
    f:close()
end

local function append_candidate(slot, sample)
    if exists(pause_path) then return end
    rotate_if_needed()
    local f = io.open(spool, "ab")
    if not f then return end
    -- Preserve the v0.9 candidate spool format exactly.
    f:write(table.concat({
        "CANDIDATE",
        tostring(os.time()),
        tostring(slot or -1),
        sample.x == nil and "" or tostring(sample.x),
        sample.y == nil and "" or tostring(sample.y),
        tostring(sample.score or 0),
        sample.incomplete and "1" or "0",
        sample.low_major and "1" or "0",
        sample.short and "1" or "0",
        sample.extreme_edge and "1" or "0",
        sample.near_edge and "1" or "0",
    }, "|") .. "\n")
    f:close()
    candidate_count = candidate_count + 1
end

local function new_slot()
    return {
        active = false,
        tracking_id = -1,
        x = nil, y = nil,
        previous_x = nil, previous_y = nil,
        start_us = nil,
        touch_major = nil,
        min_touch_major = nil,
        path_px = 0,
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

local function score_slot(slot, ts)
    local duration = tonumber(slot.lifetime_us) or math.max(0, ts - (slot.start_us or ts))
    local major = tonumber(slot.min_touch_major or slot.touch_major)
    local x, y = tonumber(slot.x), tonumber(slot.y)
    local incomplete = x == nil or y == nil
    local path_px = tonumber(slot.path_px) or 0
    local still = path_px <= 55
    local short = duration <= 100000
    local incomplete_short = incomplete and duration <= 250000
    local low_major = major ~= nil and major <= 20
    local edge_distance = nil
    if x ~= nil and screen_width > 0 then
        edge_distance = math.min(x, math.abs(screen_width - x))
    end
    local extreme_edge = edge_distance ~= nil and edge_distance <= 24
    local near_edge = edge_distance ~= nil and edge_distance <= 80
    local score = 0
    if incomplete then score = score + 4 end
    if low_major then score = score + 2 end
    if short then score = score + 2 end
    if still then score = score + 1 end
    if incomplete_short and still then score = score + 2 end
    if extreme_edge then score = score + 3 elseif near_edge then score = score + 1 end
    local strong = score >= 7 and still and (
        incomplete or (low_major and short) or (extreme_edge and short))
    return {
        x = x, y = y, score = score,
        incomplete = incomplete,
        low_major = low_major,
        short = short,
        extreme_edge = extreme_edge,
        near_edge = near_edge,
        strong = strong,
        path_px = path_px,
        duration_us = duration,
    }
end

local fd = ffi.C.open(device, O_RDONLY)
if fd < 0 then
    write_status("OPEN_FAILED", "errno=" .. tostring(ffi.errno()))
    os.exit(3)
end

write_status("RUNNING", "read-only shadow decision observer active")
local evbuf = ffi.new("struct input_event[1]")
local evsize = ffi.sizeof("struct input_event")

while true do
    local n = ffi.C.read(fd, evbuf, evsize)
    if n == 0 then
        write_status("DEVICE_CLOSED", "EOF")
        break
    elseif n < 0 then
        write_status("READ_FAILED", "errno=" .. tostring(ffi.errno()))
        break
    elseif tonumber(n) == evsize then
        raw_events = raw_events + 1
        local ev = evbuf[0]
        local ev_type, code, value = tonumber(ev.type), tonumber(ev.code), tonumber(ev.value)
        local ts = event_us(ev)
        if ev_type == EV_ABS then
            if code == ABS_MT_SLOT then
                current_slot = value
                get_slot(current_slot)
            else
                local slot = get_slot(current_slot)
                if code == ABS_MT_TRACKING_ID then
                    slot.changed = true
                    if value >= 0 then
                        slot.active = true
                        slot.tracking_id = value
                        slot.x, slot.y = nil, nil
                        slot.previous_x, slot.previous_y = nil, nil
                        slot.start_us = ts
                        slot.touch_major, slot.min_touch_major = nil, nil
                        slot.path_px = 0
                        slot.lifetime_us = nil
                        slot.transition = "START"
                    else
                        slot.lifetime_us = slot.active and math.max(0, ts - (slot.start_us or ts)) or 0
                        slot.active = false
                        slot.transition = "END"
                    end
                elseif code == ABS_MT_POSITION_X or code == ABS_MT_POSITION_Y then
                    slot.changed = true
                    local old_x, old_y = slot.x, slot.y
                    if code == ABS_MT_POSITION_X then slot.x = value else slot.y = value end
                    if slot.active and old_x ~= nil and old_y ~= nil and slot.x ~= nil and slot.y ~= nil then
                        slot.path_px = slot.path_px + math.abs(slot.x - old_x) + math.abs(slot.y - old_y)
                    end
                    slot.previous_x, slot.previous_y = old_x, old_y
                    if not slot.transition then slot.transition = "MOVE" end
                elseif code == ABS_MT_TOUCH_MAJOR then
                    slot.changed = true
                    slot.touch_major = value
                    if slot.min_touch_major == nil or value < slot.min_touch_major then
                        slot.min_touch_major = value
                    end
                end
            end
        elseif ev_type == EV_SYN and code == SYN_REPORT then
            frame_count = frame_count + 1
            for slot_index, slot in pairs(slots) do
                if slot.changed then
                    if slot.transition == "END" then
                        completed_contacts = completed_contacts + 1
                        local sample = score_slot(slot, ts)

                        if sample.strong then
                            -- Phase 1 decision only. Nothing is blocked.
                            would_suppress_count = would_suppress_count + 1
                            append_candidate(slot_index, sample)
                            append_decision("WOULD_SUPPRESS", slot_index, sample)
                            if would_suppress_count % 8 == 0 then
                                write_status("RUNNING", "would-suppress checkpoint")
                            end
                        elseif completed_contacts % 64 == 0 then
                            -- Sparse pass-through sampling gives us a baseline without
                            -- writing every normal touch to flash.
                            sampled_pass_count = sampled_pass_count + 1
                            append_decision("PASS_SAMPLE", slot_index, sample)
                            write_status("RUNNING", "pass sample checkpoint")
                        end

                        slots[slot_index] = new_slot()
                    else
                        slot.changed = false
                        slot.transition = nil
                        slot.lifetime_us = nil
                    end
                end
            end
        end
    end
end

ffi.C.close(fd)
os.exit(0)
