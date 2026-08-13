local Device = require("device")

local GhostGuard = {}
GhostGuard.__index = GhostGuard

local EV_SYN = 0
local SYN_REPORT = 0

local function read_model()
    local model = Device and Device.model
    if type(Device and Device.getModel) == "function" then
        local ok, value = pcall(Device.getModel, Device)
        if ok and value then model = value end
    end
    return tostring(model or "unknown")
end

local function normalize_device_id(value)
    value = tostring(value or "")
        :gsub("%z", "")
        :gsub("[%c]", "")
        :upper()
        :gsub("[^A-Z0-9]", "")
    if value == "" then return nil end
    return value
end

local function read_device_id()
    local f = io.open("/proc/usid", "rb")
    if not f then return "UNKNOWNDEVICE" end
    local value = normalize_device_id(f:read("*a") or "")
    f:close()
    return value or "UNKNOWNDEVICE"
end

local function screen_size()
    local width, height = 0, 0
    if Device and Device.screen then
        if type(Device.screen.getWidth) == "function" then
            local ok, value = pcall(Device.screen.getWidth, Device.screen)
            if ok then width = tonumber(value) or 0 end
        end
        if type(Device.screen.getHeight) == "function" then
            local ok, value = pcall(Device.screen.getHeight, Device.screen)
            if ok then height = tonumber(value) or 0 end
        end
    end
    return width, height
end

local function parse_marker_value(content, key)
    if type(content) ~= "string" then return nil end
    return content:match("\n?" .. key .. "=([^\r\n]+)")
end

function GhostGuard:new(config, Storage, TouchObserver, ProfileManager, LicenseManager, CloudManager, plugin_dir)
    local existing_bridge = Device and Device.input and Device.input._dcpro_ghostguard_bridge
    local existing_owner = existing_bridge and existing_bridge.owner
    if existing_owner and type(existing_owner.stop) == "function" then
        pcall(existing_owner.stop, existing_owner, "plugin-reload")
    end

    local storage = Storage:new(config)
    local stale, stale_report = false, nil
    local ok = storage:ensureLayout()
    if ok then stale, stale_report = storage:archiveStaleMarker() end

    local width, height = screen_size()
    local model = read_model()
    local device_id = read_device_id()
    local profiles = ProfileManager:new(config, storage, {
        device_id = device_id,
        model = model,
        screen_width = width,
        screen_height = height,
    })
    local license = LicenseManager:new(config, storage, plugin_dir, device_id)
    local cloud = CloudManager:new(config, storage, plugin_dir)
    if stale and stale_report and type(storage.prepareStaleOutbox) == "function" then
        pcall(storage.prepareStaleOutbox, storage, stale_report, {
            device_id = device_id, model = model,
        })
    end

    return setmetatable({
        config = config,
        storage = storage,
        TouchObserver = TouchObserver,
        profiles = profiles,
        license = license,
        cloud = cloud,
        plugin_dir = plugin_dir,
        running = false,
        observer_enabled = false,
        protect_enabled = false,
        calibration_enabled = false,
        autostart_blocked = stale,
        stale_report = stale_report,
        session = nil,
        observer = nil,
        input = nil,
        bridge = nil,
        hook_installed = false,
        protect_wrapper_installed = false,
        last_error = nil,
        start_reason = nil,
        mode = config.default_mode,
        model = model,
        device_id = device_id,
        screen_width = width,
        screen_height = height,
        pending_frame_decision = nil,
        quarantine_until_us = 0,
        block_timestamps = {},
        protect_stats = { blocked_frames = 0, quarantines = 0, circuit_breakers = 0 },
        session_started_wall = nil,
        last_safe_check_wall = nil,
        last_license_check_wall = nil,
        last_outbox = nil,
        last_profile_result = nil,
        profile_ready_notified = false,
        on_profile_ready = nil,
        exit_diagnostics = nil,
        wrapper_mode = "NONE",
    }, self)
end

function GhostGuard:isRunning() return self.running end
function GhostGuard:isProtecting() return self.running and self.protect_enabled end
function GhostGuard:isCalibrating() return self.running and self.calibration_enabled end
function GhostGuard:isSafeMode() return self.storage:isSafeMode() end

function GhostGuard:consumeLaunchRequest()
    if not self.storage:fileExists(self.config.launch_once_marker) then return false end
    local content = self.storage:readFile(self.config.launch_once_marker) or ""
    self.storage:removeExact(self.config.launch_once_marker)
    local mode = parse_marker_value(content, "MODE") or "AUTO"
    if mode == "AUTO" then
        mode = self.profiles:hasApproved() and self.config.protect_mode or self.config.calibration_mode
    end
    return true, mode, content
end

function GhostGuard:protectSupported()
    return self.config.protect_supported_models[self.model] == true
end

function GhostGuard:profileReady() return self.profiles:hasPendingReady() end
function GhostGuard:profileApproved() return self.profiles:hasApproved() end
function GhostGuard:licenseValid(force)
    -- Final build: activation is always enforced. There is no config switch
    -- that can accidentally leave calibration/protection unlicensed.
    return self.license:check(force == true)
end
function GhostGuard:licenseStatusText()
    return self.license:statusText()
end
function GhostGuard:syncOnlineLicense()
    return self.license:syncOnline()
end
function GhostGuard:licenseHelpText()
    return self.license:activationHelp()
end
function GhostGuard:profileLiveReady()
    return self.profiles:isCalibrationReady() or self.profiles:hasPendingReady()
end
function GhostGuard:customerProgressText()
    if self.profiles:hasApproved() then return "ĐÃ SẴN SÀNG BẢO VỆ" end
    return self.profiles:progressText()
end
function GhostGuard:probationRemaining()
    local raw = self.storage:readFile(self.config.probation_marker)
    return math.max(0, tonumber(raw and raw:match("(%d+)") or "0") or 0)
end
function GhostGuard:setProbationRemaining(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    if value == 0 then
        self.storage:removeExact(self.config.probation_marker)
        return true
    end
    return self.storage:writeAtomic(self.config.probation_marker, tostring(value) .. "\n")
end
function GhostGuard:cloudStatusText() return self.cloud:statusText() end
function GhostGuard:startCloudUpload() return self.cloud:start() end

function GhostGuard:exitState()
    return {
        running = self.running == true and "YES" or "NO",
        mode = self.mode or "UNKNOWN",
        protect_enabled = self.protect_enabled == true and "YES" or "NO",
        protect_wrapper = self.protect_wrapper_installed == true and "YES" or "NO",
        start_reason = self.start_reason or "NONE",
        last_error = self.last_error or "NONE",
    }
end

function GhostGuard:recordExitReason(reason, detail, traceback_text)
    if self.exit_diagnostics and type(self.exit_diagnostics.record) == "function" then
        return self.exit_diagnostics:record(reason, detail, traceback_text, self:exitState())
    end
    local fallback = "DCPRO_GHOSTGUARD_EXIT_REASON_V2\nUTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ")
        .. "\nEXIT_REASON=" .. tostring(reason or "UNKNOWN")
        .. "\nEXIT_REASON_DETAIL=" .. tostring(detail or "NONE")
        .. "\n\n" .. tostring(traceback_text or debug.traceback("GhostGuard exit diagnostic", 2)) .. "\n"
    return self.storage:writeAtomic(self.config.exit_reason_detail_file, fallback)
end

function GhostGuard:ensureInputBridge()
    local input = Device.input
    if not input then return false, "Device.input unavailable" end
    if type(input.registerEventAdjustHook) ~= "function" then
        return false, "Input:registerEventAdjustHook unavailable"
    end
    local bridge = input._dcpro_ghostguard_bridge
    if not bridge then
        bridge = { owner = self, event_hook_installed = false, wrapper = nil, original_handle_touch = nil }
        input._dcpro_ghostguard_bridge = bridge
    elseif bridge.owner and bridge.owner ~= self then
        pcall(bridge.owner.stop, bridge.owner, "replaced-by-new-instance")
        bridge.owner = self
    else
        bridge.owner = self
    end
    if not bridge.event_hook_installed then
        input:registerEventAdjustHook(function(this, event)
            local active_bridge = this._dcpro_ghostguard_bridge
            local owner = active_bridge and active_bridge.owner
            if owner then
                local ok, err = xpcall(function() owner:onRawEvent(event) end, debug.traceback)
                if not ok and type(owner.recordRuntimeFault) == "function" then
                    pcall(owner.recordRuntimeFault, owner, "RAW_EVENT_HOOK", err)
                end
            end
        end)
        bridge.event_hook_installed = true
    end
    self.input, self.bridge, self.hook_installed = input, bridge, true
    return true
end

function GhostGuard:restoreProtectWrapper()
    local input, bridge = self.input, self.bridge
    if not input or not bridge or not bridge.wrapper then
        self.protect_wrapper_installed = false
        self.wrapper_mode = "NONE"
        return true
    end
    if input.handleTouchEv == bridge.wrapper and type(bridge.original_handle_touch) == "function" then
        input.handleTouchEv = bridge.original_handle_touch
    end
    bridge.wrapper = nil
    bridge.original_handle_touch = nil
    self.protect_wrapper_installed = false
    self.wrapper_mode = "NONE"
    return true
end

function GhostGuard:recordRuntimeFault(stage, err)
    local detail = tostring(err or "unknown error")
    self.last_error = tostring(stage or "RUNTIME_FAULT") .. ": " .. detail
    self.protect_enabled = false
    self.pending_frame_decision = nil
    if self.observer then pcall(self.observer.setProtectEnabled, self.observer, false) end
    if self.session then
        pcall(self.session.writeAction, self.session,
            { timestamp_us = os.time() * 1000000, frame = -1, slot = -1, score = 0 },
            "FAIL_OPEN_RUNTIME_FAULT", self.last_error)
        pcall(self.session.flush, self.session)
    end
    pcall(self.storage.writeAtomic, self.storage,
        self.config.data_dir .. "/RUNTIME_FAULT.txt",
        "DCPRO_GHOSTGUARD_RUNTIME_FAULT_V1\nUTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ") ..
        "\nSTAGE=" .. tostring(stage or "unknown") .. "\nDETAIL=" .. detail .. "\n")
    pcall(self.recordExitReason, self, "GHOSTGUARD_RUNTIME_FAULT",
        "STAGE=" .. tostring(stage or "unknown") .. "; DETAIL=" .. detail, detail)
    pcall(self.restoreProtectWrapper, self)
end

function GhostGuard:ensureProtectWrapper()
    local input, bridge = self.input, self.bridge
    if not input or not bridge then return false, "input bridge unavailable" end
    if bridge.wrapper then
        if input.handleTouchEv ~= bridge.wrapper and input._abs_ev_handler ~= bridge.wrapper then
            return false, "KOReader handleTouchEv changed after bridge installation"
        end
        self.protect_wrapper_installed = true
        self.wrapper_mode = self.protect_enabled and "PROTECT" or "PASS_THROUGH"
        return true
    end
    if input._abs_ev_handler then return false, "KOReader input is inhibited; try after it unlocks" end
    if type(input.handleTouchEv) ~= "function" then
        return false, "required KOReader touch method unavailable"
    end
    bridge.original_handle_touch = input.handleTouchEv
    bridge.wrapper = function(this, event)
        local active_bridge = this._dcpro_ghostguard_bridge
        local owner = active_bridge and active_bridge.owner
        local original = active_bridge and active_bridge.original_handle_touch or bridge.original_handle_touch
        if type(original) ~= "function" then return {} end

        -- IMPORTANT: KOReader must consume the complete raw frame first.
        -- GhostGuard only suppresses the already-built gesture result afterwards.
        -- The previous order skipped SYN_REPORT before KOReader saw it, leaving
        -- GestureDetector with an incomplete contact and eventually crashing.
        local original_ok, result = xpcall(function()
            return original(this, event)
        end, debug.traceback)
        if not original_ok then
            if owner and type(owner.recordRuntimeFault) == "function" then
                pcall(owner.recordRuntimeFault, owner, "KOReader_HANDLE_TOUCH", result)
            end
            if type(this.resetState) == "function" then pcall(this.resetState, this) end
            return {}
        end

        if owner and owner.running and owner.protect_enabled then
            local decision = owner:takeFrameDecision()
            if decision then
                local apply_ok, apply_err = xpcall(function()
                    owner:applyProtectionDecision(this, decision)
                end, debug.traceback)
                if not apply_ok then
                    pcall(owner.recordRuntimeFault, owner, "PROTECT_DECISION", apply_err)
                    return result
                end
                return {}
            end
        end
        return result
    end
    input.handleTouchEv = bridge.wrapper
    self.protect_wrapper_installed = true
    self.wrapper_mode = self.protect_enabled and "PROTECT" or "PASS_THROUGH"
    return true
end

function GhostGuard:onRawEvent(event)
    if not self.running or not self.observer_enabled or not self.observer then return end
    local wall_now = os.time()
    if self.last_safe_check_wall ~= wall_now then
        self.last_safe_check_wall = wall_now
        if self.storage:isSafeMode() then self:stop("external-safe-mode"); return end
    end
    if not self.last_license_check_wall
        or wall_now - self.last_license_check_wall >= (self.config.license_recheck_seconds or 30) then
        self.last_license_check_wall = wall_now
        local licensed, detail = self:licenseValid(true)
        if not licensed then
            self.last_error = "License failsafe: " .. tostring(detail)
            if self.session then
                self.session:writeAction({ timestamp_us = wall_now * 1000000, slot = -1, tracking_id = -1 },
                    "LICENSE_FAILSAFE_STOP", self.last_error)
                self.session:flush()
            end
            self:setAutoProtectEnabled(false, true)
            self:stop("license-invalid")
            return
        end
    end

    local max_seconds = self.config.max_observe_session_seconds
    if self.calibration_enabled then max_seconds = self.config.max_calibration_session_seconds end
    if self.protect_enabled then max_seconds = self.config.max_protect_session_seconds end
    if max_seconds > 0 and self.session_started_wall
        and wall_now - self.session_started_wall >= max_seconds then
        self:stop("time-limit")
        return
    end

    local observe_ok, decision_or_err = pcall(self.observer.observe, self.observer, event)
    if not observe_ok then
        self.last_error = "OBSERVER_ERROR: " .. tostring(decision_or_err)
        if self.session then
            self.session:writeCandidate(os.time() * 1000000, -1, -1,
                "OBSERVER_ERROR", -1, nil, nil, self.last_error)
            self.session:flush()
        end
        if self.calibration_enabled then
            self.calibration_enabled = false
            if type(self.profiles.cancelCalibration) == "function" then
                self.profiles:cancelCalibration()
            end
        end
        self:recordRuntimeFault("OBSERVER", decision_or_err)
        self:stop("observer-error")
        return
    end
    if tonumber(event.type) == EV_SYN and tonumber(event.code) == SYN_REPORT then
        self.pending_frame_decision = self.protect_enabled and decision_or_err or nil
        if self.calibration_enabled and not self.profile_ready_notified
            and self.profiles:isCalibrationReady()
            and self.session_started_wall
            and wall_now - self.session_started_wall >= (self.config.customer_ready_notice_after_seconds or 180) then
            self.profile_ready_notified = true
            self.storage:touch(self.config.customer_profile_ready_marker,
                "READY=1\nUTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
            if type(self.on_profile_ready) == "function" then
                pcall(self.on_profile_ready, self, self.profiles:progressText())
            end
        end
    end
end

function GhostGuard:takeFrameDecision()
    local decision = self.pending_frame_decision
    self.pending_frame_decision = nil
    return decision
end

function GhostGuard:trimBlockTimestamps(now_us)
    local keep, cutoff = {}, now_us - 60000000
    for _, ts in ipairs(self.block_timestamps) do if ts >= cutoff then keep[#keep + 1] = ts end end
    self.block_timestamps = keep
end

function GhostGuard:applyProtectionDecision(input, decision)
    local ts = tonumber(decision.timestamp_us) or os.time() * 1000000
    self.protect_stats.blocked_frames = self.protect_stats.blocked_frames + 1
    self.block_timestamps[#self.block_timestamps + 1] = ts
    self:trimBlockTimestamps(ts)
    if self.session then self.session:writeAction(decision, "DROP_GESTURE_FRAME", decision.reason) end

    local quarantine = tonumber(decision.quarantine_seconds) or 0
    if quarantine > 0 and type(input.inhibitInputUntil) == "function" then
        self.quarantine_until_us = ts + math.floor(quarantine * 1000000)
        self.protect_stats.quarantines = self.protect_stats.quarantines + 1
        if self.session then self.session:writeAction(decision, "QUARANTINE", "seconds=" .. quarantine .. ";" .. decision.reason) end
        local ok, err = pcall(input.inhibitInputUntil, input, quarantine)
        if not ok then self.last_error = "quarantine failed: " .. tostring(err) end
    end

    local max_blocks = self.config.protect_max_blocks_per_minute
    if self:probationRemaining() > 0 then
        max_blocks = self.config.protect_probation_max_blocks_per_minute or max_blocks
    end
    if #self.block_timestamps > max_blocks then
        self.protect_enabled = false
        if self.observer then self.observer:setProtectEnabled(false) end
        self.protect_stats.circuit_breakers = self.protect_stats.circuit_breakers + 1
        self.last_error = "Protect circuit breaker: too many blocked frames; fell back to Observe-Only"
        if self.session then
            self.session:writeAction(decision, "CIRCUIT_BREAKER", self.last_error)
            self.session:flush()
        end
    end
end

function GhostGuard:start(mode, reason)
    if self.running then return true, "already running" end
    local safe, safe_path = self.storage:isSafeMode()
    if safe then return false, "SAFE_MODE: " .. tostring(safe_path) end
    mode = mode or self.config.default_mode
    if mode ~= self.config.default_mode and mode ~= self.config.calibration_mode and mode ~= self.config.protect_mode then
        return false, "unsupported mode: " .. tostring(mode)
    end

    local licensed, license_detail = self:licenseValid(true)
    if not licensed then
        return false, "Cần license.key hợp lệ trong thư mục plugin: " .. tostring(license_detail)
    end

    local hook_ok, hook_err = self:ensureInputBridge()
    if not hook_ok then return false, hook_err end
    local protect = mode == self.config.protect_mode
    local calibrate = mode == self.config.calibration_mode
    if protect then
        if not self:protectSupported() then return false, "Protect limited to KindleBasic4/KT5; detected " .. self.model end
        if not self.profiles:hasApproved() then return false, "Chưa có profile đã duyệt. Hãy Hiệu chuẩn trước." end
    end
    if protect or self.config.protect_wrapper_all_modes == true then
        self.protect_enabled = protect
        local wrapper_ok, wrapper_err = self:ensureProtectWrapper()
        if not wrapper_ok then
            self.protect_enabled = false
            return false, "PROTECT_WRAPPER: " .. tostring(wrapper_err)
        end
        self.wrapper_mode = protect and "PROTECT" or "PASS_THROUGH"
    end
    if calibrate then
        self.profiles:startCalibration()
        self.storage:touch(self.config.customer_setup_marker,
            "STATE=LEARNING\nDEVICE_ID=" .. self.device_id .. "\n")
    end

    local session_id = os.date("%Y%m%d_%H%M%S") .. "_" .. tostring(math.random(1000, 9999))
    local metadata = {
        version = self.config.version,
        mode = mode,
        session_id = session_id,
        start_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    local session, err = self.storage:openSession(session_id, metadata)
    if not session then
        if calibrate and type(self.profiles.cancelCalibration) == "function" then
            pcall(self.profiles.cancelCalibration, self.profiles)
        end
        self.protect_enabled = false
        self:restoreProtectWrapper()
        return false, "cannot open report: " .. tostring(err)
    end

    self.session = session
    self.mode = mode
    self.protect_enabled = protect
    self.calibration_enabled = calibrate
    self.observer = self.TouchObserver:new(session, self.config, {
        mode = mode,
        protect_enabled = protect,
        calibration_enabled = calibrate,
        profile_manager = self.profiles,
        screen_width = self.screen_width,
        screen_height = self.screen_height,
    })
    self.start_reason = reason or "manual"
    self.last_error = nil
    self.pending_frame_decision = nil
    self.quarantine_until_us = 0
    self.block_timestamps = {}
    self.protect_stats = { blocked_frames = 0, quarantines = 0, circuit_breakers = 0 }
    self.session_started_wall = os.time()
    self.last_safe_check_wall = nil
    self.last_license_check_wall = os.time()
    self.profile_ready_notified = false
    self.observer_enabled, self.running = true, true

    local marker_ok, marker_err = self.storage:writeAtomic(self.config.run_marker,
        "VERSION=" .. self.config.version .. "\nMODE=" .. mode .. "\nMODEL=" .. self.model ..
        "\nDEVICE_ID=" .. self.device_id .. "\nSESSION=" .. session_id ..
        "\nSTART_UTC=" .. metadata.start_utc .. "\nREASON=" .. self.start_reason .. "\n")
    if not marker_ok then self:stop("marker-failure"); return false, "cannot create RUNNING marker: " .. tostring(marker_err) end
    self.autostart_blocked = false
    return true, session_id
end

function GhostGuard:flush() if self.session then self.session:flush() end end

function GhostGuard:stop(reason)
    local was_protecting = self.protect_enabled == true
    local had_protect_wrapper = self.protect_wrapper_installed == true
    if not self.running and not self.session then
        self.storage:removeExact(self.config.run_marker)
        return true, "already stopped"
    end
    self.running, self.observer_enabled = false, false
    self.protect_enabled, self.pending_frame_decision = false, nil
    if self.observer then self.observer:setProtectEnabled(false) end
    self:restoreProtectWrapper()

    local profile_result = nil
    if self.calibration_enabled and self.profiles:isCalibrating() then
        local ok, result = self.profiles:finalize()
        profile_result = ok and result or nil
        if not ok then self.last_error = "profile finalize failed: " .. tostring(result) end
    end
    self.calibration_enabled = false
    self.last_profile_result = profile_result

    local stats = self.observer and self.observer:getStats() or {}
    local session = self.session
    if session then
        session:close({
            result = self.last_error and "DEGRADED_FAIL_OPEN" or "OK",
            stop_reason = reason or "manual",
            start_reason = self.start_reason or "unknown",
            device_id = self.device_id,
            model = self.model,
            screen = self.screen_width .. "x" .. self.screen_height,
            hook_registered = self.hook_installed and "YES" or "NO",
            protect_wrapper = had_protect_wrapper and "YES" or "NO",
            protect_wrapper_mode = had_protect_wrapper and (was_protecting and "PROTECT" or "PASS_THROUGH") or "NONE",
            raw_events = stats.raw_events or 0,
            frames = stats.frames or 0,
            contact_starts = stats.starts or 0,
            contact_moves = stats.moves or 0,
            contact_ends = stats.ends or 0,
            candidates = stats.candidates or 0,
            calibration_samples = stats.calibration_samples or 0,
            calibration_rejected = stats.calibration_rejected or 0,
            profile_ready = self.profiles:hasPendingReady() and "YES" or "NO",
            profile_approved = self.profiles:hasApproved() and "YES" or "NO",
            license_status = self:licenseStatusText(),
            probation_remaining = self:probationRemaining(),
            protect_candidates = stats.protect_candidates or 0,
            blocked_frames = self.protect_stats.blocked_frames or 0,
            quarantines = self.protect_stats.quarantines or 0,
            circuit_breakers = self.protect_stats.circuit_breakers or 0,
            last_error = self.last_error or "NONE",
        })
        local active_profile = self.profiles:hasApproved() and self.profiles.approved_path
            or (self.profiles.pending and self.profiles.pending_path or nil)
        local out_ok, out_result = self.storage:prepareCloudOutbox(session, {
            device_id = self.device_id,
            model = self.model,
            profile_path = active_profile,
        })
        if out_ok then self.last_outbox = out_result end
    end

    self.storage:removeExact(self.config.run_marker)
    self.session, self.observer = nil, nil
    self.session_started_wall, self.last_safe_check_wall, self.last_license_check_wall = nil, nil, nil
    if was_protecting and not self.last_error then
        local remaining = self:probationRemaining()
        if remaining > 0 then self:setProbationRemaining(remaining - 1) end
    end
    return true, "stopped; report queued in cloud_outbox"
end

function GhostGuard:finishCalibration()
    if not self:isCalibrating() then return false, "Không có phiên hiệu chuẩn đang chạy" end
    local ok, result = self:stop("calibration-finish")
    if not ok then return false, result end
    return true, self.profiles:summaryText()
end

function GhostGuard:completeCustomerSetup()
    local licensed, detail = self:licenseValid(true)
    if not licensed then return false, "license.key không hợp lệ: " .. tostring(detail) end
    if self:isCalibrating() then
        local stopped, stop_detail = self:stop("customer-setup-complete")
        if not stopped then return false, stop_detail end
    end
    if not self.profiles:hasPendingReady() then
        return false, self.profiles:progressText()
    end
    local approved, approved_detail = self.profiles:approvePending()
    if not approved then return false, approved_detail end
    self.storage:touch(self.config.customer_setup_marker,
        "STATE=READY\nDEVICE_ID=" .. self.device_id .. "\nUTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    self.storage:removeExact(self.config.customer_profile_ready_marker)
    self:setProbationRemaining(self.config.customer_probation_sessions or 2)
    local auto_ok, auto_detail = self:setAutoProtectEnabled(true)
    if not auto_ok then return false, auto_detail end
    return true, "Profile đã duyệt; Auto Protect đã bật; bảo vệ thử "
        .. tostring(self:probationRemaining()) .. " phiên"
end

function GhostGuard:approveProfile()
    if self.running then return false, "Hãy dừng phiên hiện tại trước" end
    local licensed, detail = self:licenseValid(true)
    if not licensed then return false, "license.key không hợp lệ: " .. tostring(detail) end
    return self.profiles:approvePending()
end

function GhostGuard:resetProfile()
    if self.running then return false, "Hãy dừng GhostGuard trước" end
    self:setAutoProtectEnabled(false)
    self.storage:removeExact(self.config.customer_setup_marker)
    self.storage:removeExact(self.config.customer_profile_ready_marker)
    self:setProbationRemaining(0)
    return self.profiles:reset()
end

function GhostGuard:isAutoProtectEnabled()
    return self.storage:fileExists(self.config.auto_protect_marker)
end

function GhostGuard:setAutoProtectEnabled(enabled, internal_failsafe)
    if enabled then
        if not self:protectSupported() then return false, "Auto Protect limited to KindleBasic4/KT5" end
        if not self.profiles:hasApproved() then return false, "Chưa có profile đã duyệt" end
        local licensed, license_detail = self:licenseValid(true)
        if not licensed then return false, "license.key không hợp lệ: " .. tostring(license_detail) end
        return self.storage:touch(self.config.auto_protect_marker,
            "AUTO_PROTECT=1\nVERSION=" .. self.config.version ..
            "\nDEVICE_ID=" .. self.device_id ..
            "\nCREATED_UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    end
    if self.storage:fileExists(self.config.auto_protect_marker) then self.storage:removeExact(self.config.auto_protect_marker) end
    return true, internal_failsafe and "disabled-by-failsafe" or "disabled"
end

function GhostGuard:setSafeMode(enabled)
    if enabled and self.running then self:stop("safe-mode") end
    return self.storage:setSafeMode(enabled)
end

function GhostGuard:statusText()
    local safe, safe_path = self.storage:isSafeMode()
    local state = "ĐÃ DỪNG"
    if self.running then
        if self.protect_enabled then state = "ĐANG BẢO VỆ THEO PROFILE"
        elseif self.calibration_enabled then state = "ĐANG HIỆU CHUẨN — KHÔNG CHẶN"
        else state = "ĐANG QUAN SÁT" end
    end
    local lines = {
        "DCPRO GhostGuard " .. self.config.version,
        "Thiết bị: " .. self.device_id .. " / " .. self.model .. " — " .. self.screen_width .. "x" .. self.screen_height,
        "Chế độ: " .. tostring(self.mode),
        "Trạng thái: " .. state,
        "Can thiệp: " .. (self.protect_enabled and "LỌC FRAME THEO PROFILE ĐÃ DUYỆT" or "KHÔNG"),
        "PROTECT_WRAPPER: " .. tostring(self.wrapper_mode or "NONE"),
        "Profile chờ duyệt: " .. (self.profiles:hasPendingReady() and "CÓ" or "KHÔNG"),
        "Profile đã duyệt: " .. (self.profiles:hasApproved() and "CÓ" or "KHÔNG"),
        "Tự bảo vệ: " .. (self:isAutoProtectEnabled() and "BẬT" or "TẮT"),
        "License: " .. self:licenseStatusText(),
        "Thiết lập khách hàng: " .. self:customerProgressText(),
        "Bảo vệ thử còn lại: " .. tostring(self:probationRemaining()) .. " phiên",
        "Safe Mode: " .. (safe and ("BẬT — " .. tostring(safe_path)) or "TẮT"),
        "Đã chặn: " .. tostring(self.protect_stats.blocked_frames or 0) .. " | Cách ly: " .. tostring(self.protect_stats.quarantines or 0),
        "Báo cáo: " .. self.config.report_dir,
        "Cloud outbox: " .. self.config.cloud_outbox_dir,
        "Cloud Apps Script: ĐÃ CẤU HÌNH",
        "Cloud worker: " .. (self.cloud:isBusy() and "ĐANG CHẠY" or "RẢNH"),
        "Drive đích: " .. tostring(self.config.drive_root_folder_id),
    }
    if self.last_outbox then lines[#lines + 1] = "Gói chờ upload: " .. self.last_outbox end
    if self.stale_report then lines[#lines + 1] = "Stale report: " .. self.stale_report end
    if self.last_error then lines[#lines + 1] = "Cảnh báo: " .. self.last_error end
    if self.observer then
        local s = self.observer:getStats()
        lines[#lines + 1] = string.format("Frames=%d | Ends=%d | Học=%d | Candidates=%d",
            s.frames or 0, s.ends or 0, s.calibration_samples or 0, s.candidates or 0)
    end
    return table.concat(lines, "\n")
end

return GhostGuard
