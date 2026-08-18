local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local logger = require("logger")
local _ = require("gettext")

local plugin_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local DCPROGhostGuard = WidgetContainer:extend{
    name = "dcghostguardpro",
    is_doc_only = false,
}

local function show(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

local function load_local(filename)
    local ok, result = pcall(dofile, plugin_dir .. filename)
    if not ok then return nil, tostring(result) end
    if result == nil then return nil, filename .. " returned nil" end
    return result
end

function DCPROGhostGuard:loadRuntime()
    if self.guard then return true end
    local config, err = load_local("defaults.lua")
    if not config then return false, "defaults.lua: " .. err end
    local Storage; Storage, err = load_local("storage.lua")
    if not Storage then return false, "storage.lua: " .. err end
    local TouchObserver; TouchObserver, err = load_local("touch_observer.lua")
    if not TouchObserver then return false, "touch_observer.lua: " .. err end
    local ProfileManager; ProfileManager, err = load_local("profile_manager.lua")
    if not ProfileManager then return false, "profile_manager.lua: " .. err end
    local LicenseManager; LicenseManager, err = load_local("license_manager.lua")
    if not LicenseManager then return false, "license_manager.lua: " .. err end
    local CloudManager; CloudManager, err = load_local("cloud_manager.lua")
    if not CloudManager then return false, "cloud_manager.lua: " .. err end
    local ExitDiagnostics; ExitDiagnostics, err = load_local("exit_diagnostics.lua")
    if not ExitDiagnostics then return false, "exit_diagnostics.lua: " .. err end
    local GhostGuard; GhostGuard, err = load_local("ghostguard.lua")
    if not GhostGuard then return false, "ghostguard.lua: " .. err end
    local ok, guard_or_err = pcall(GhostGuard.new, GhostGuard, config, Storage, TouchObserver,
        ProfileManager, LicenseManager, CloudManager, plugin_dir)
    if not ok then return false, "GhostGuard:new: " .. tostring(guard_or_err) end
    self.config, self.guard = config, guard_or_err

    -- SimpleUI and ZenUI integrations are optional UI bridges. Never fail
    -- GhostGuard runtime if either host UI is absent or exposes an older API.
    local SimpleUIBridge, bridge_err = load_local("simpleui_bridge.lua")
    if SimpleUIBridge then
        local bridge_ok, bridge_obj = pcall(SimpleUIBridge.new, SimpleUIBridge, self, plugin_dir)
        if bridge_ok then
            self.simpleui = bridge_obj
        else
            logger.warn("DCPRO GhostGuard SimpleUI bridge init failed:", bridge_obj)
        end
    else
        logger.info("DCPRO GhostGuard SimpleUI bridge unavailable:", bridge_err)
    end
    local ZenUIBridge, zen_err = load_local("zenui_bridge.lua")
    if ZenUIBridge then
        local zen_ok, zen_obj = pcall(ZenUIBridge.new, ZenUIBridge, self, plugin_dir)
        if zen_ok then
            self.zenui = zen_obj
        else
            logger.warn("DCPRO GhostGuard ZenUI bridge init failed:", zen_obj)
        end
    else
        logger.info("DCPRO GhostGuard ZenUI bridge unavailable:", zen_err)
    end
    self.exit_diagnostics = ExitDiagnostics:new(config, self.guard.storage)
    self.guard.exit_diagnostics = self.exit_diagnostics
    self.exit_diagnostics:install(self)
    self.guard.on_profile_ready = function(_guard, progress)
        UIManager:scheduleIn(0.1, function()
            show(_("GhostGuard đã học đủ dữ liệu.\n\n") .. tostring(progress)
                .. _("\n\nMở Tools và chọn Hoàn tất thiết lập bảo vệ."), 14)
        end)
    end
    return true
end

function DCPROGhostGuard:startMode(mode, reason)
    local ok, result = self.guard:start(mode, reason)
    if not ok then
        local detail = tostring(result)
        -- Auto-start must never interrupt the reading session merely because
        -- the current KOReader/SimpleUI build has no usable touch wrapper.
        -- Manual Protect still reports the real bridge error so technicians can
        -- diagnose unsupported input APIs instead of silently running unprotected.
        local auto_reason = tostring(reason or ""):match("auto") ~= nil
        if mode == self.config.protect_mode and auto_reason
            and detail:match("PROTECT_WRAPPER") then
            local fallback_mode = self.config.default_mode
            local fallback_ok, fallback_result = self.guard:start(fallback_mode, "auto-protect-bridge-fallback")
            if fallback_ok then
                show(_("GhostGuard chưa kết nối được input bridge của KOReader/SimpleUI.\n\nĐể không làm gián đoạn việc đọc, GhostGuard đã chuyển sang Observe-Only.\n\nKhi bridge khả dụng, Protect sẽ được đề xuất lại."), 12)
                return true
            end
            detail = detail .. "\nFallback Observe-Only cũng thất bại: " .. tostring(fallback_result)
        end
        show(_("Không thể bắt đầu GhostGuard:\n") .. detail, 8)
        return false
    end
    if mode == self.config.calibration_mode then
        show(_("Đang học cách khách sử dụng máy.\nHãy đọc và thao tác bình thường; GhostGuard chưa chặn cảm ứng.\nPhiên: ") .. tostring(result), 8)
    elseif mode == self.config.protect_mode then
        show(_("Đã bật bảo vệ theo profile và license.key hợp lệ.\nPhiên: ") .. tostring(result), 7)
    else
        show(_("Đã bắt đầu Observe-Only.\nPhiên: ") .. tostring(result), 4)
    end
    return true
end

function DCPROGhostGuard:showStatus()
    if self.load_error then show(tostring(self.load_error), 12); return end
    local extra = self.simpleui and ("\nSimpleUI: " .. self.simpleui:statusText()) or ""
    if self.zenui then extra = extra .. "\nZenUI: " .. self.zenui:statusText() end
    show(self.guard:statusText() .. extra, 18)
end

function DCPROGhostGuard:stopAndShow(reason)
    if not self.guard:isRunning() then show(_("GhostGuard đang dừng."), 3); return end
    local _, result = self.guard:stop(reason or "manual")
    show(_("GhostGuard đã dừng.\nBáo cáo đã đưa vào cloud_outbox.\n") .. tostring(result), 6)
end

function DCPROGhostGuard:startCloudUpload()
    local ok, result = self.guard:startCloudUpload()
    show((ok and _("Đã bắt đầu gửi báo cáo Cloud ở nền.\n") or _("Không thể gửi Cloud:\n")) .. tostring(result), 8)
end

function DCPROGhostGuard:cloudUploadFlow(reason)
    if self.guard:isRunning() then
        UIManager:show(ConfirmBox:new{
            text = _("Để gửi đủ report, GhostGuard cần dừng và đóng phiên hiện tại trước. Dừng rồi gửi Cloud ngay?"),
            ok_text = _("Dừng và gửi"),
            ok_callback = function()
                self.guard:stop(reason or "stop-and-cloud")
                self:startCloudUpload()
            end,
        })
    else
        self:startCloudUpload()
    end
end

function DCPROGhostGuard:simpleUIPrimaryLabel()
    if not self.guard then return "GhostGuard" end
    local licensed = self.guard:licenseValid(false)
    if not licensed then return "GhostGuard: Cần license.key" end
    if self.guard:isProtecting() then return "GhostGuard: Đang bảo vệ" end
    if self.guard:isCalibrating() then
        return self.guard:profileLiveReady() and "GhostGuard: Hoàn tất thiết lập"
            or "GhostGuard: Đang học cách dùng máy"
    end
    if self.guard:isRunning() then return "GhostGuard: Đang quan sát" end
    if self.guard:profileApproved() then return "GhostGuard: Bật bảo vệ" end
    if self.guard:profileLiveReady() then return "GhostGuard: Hoàn tất thiết lập" end
    return "GhostGuard: Bắt đầu học profile"
end

function DCPROGhostGuard:completeCustomerSetupAndProtect(reason)
    local ok, result = self.guard:completeCustomerSetup()
    if not ok then show(_("Chưa thể hoàn tất:\n") .. tostring(result), 12); return false end
    local started, start_result = self.guard:start(self.config.protect_mode, reason or "customer-setup-complete")
    if started then
        show(_("Thiết lập hoàn tất.\nGhostGuard đang chạy bảo vệ thử và sẽ tự bảo vệ ở các lần mở KOReader sau."), 9)
        return true
    end
    show(_("Profile đã sẵn sàng nhưng chưa bật được Protect:\n") .. tostring(start_result), 10)
    return false
end
