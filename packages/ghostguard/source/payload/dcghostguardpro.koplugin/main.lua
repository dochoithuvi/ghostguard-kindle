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
    local SimpleUIBridge; SimpleUIBridge, err = load_local("simpleui_bridge.lua")
    if not SimpleUIBridge then return false, "simpleui_bridge.lua: " .. err end
    local ZenUIBridge; ZenUIBridge, err = load_local("zenui_bridge.lua")
    if not ZenUIBridge then return false, "zenui_bridge.lua: " .. err end

    local ok, guard_or_err = pcall(GhostGuard.new, GhostGuard, config, Storage, TouchObserver,
        ProfileManager, LicenseManager, CloudManager, plugin_dir)
    if not ok then return false, "GhostGuard:new: " .. tostring(guard_or_err) end
    self.config, self.guard = config, guard_or_err
    self.exit_diagnostics = ExitDiagnostics:new(config, self.guard.storage)
    self.guard.exit_diagnostics = self.exit_diagnostics
    self.exit_diagnostics:install(self)
    self.guard.on_profile_ready = function(_guard, progress)
        UIManager:scheduleIn(0.1, function()
            show(_("GhostGuard đã học đủ dữ liệu.\n\n") .. tostring(progress)
                .. _("\n\nMở Tools và chọn Hoàn tất thiết lập bảo vệ."), 14)
        end)
    end
    self.simpleui = SimpleUIBridge:new(self, plugin_dir)
    self.zenui = ZenUIBridge:new(self, plugin_dir)
    return true
end

function DCPROGhostGuard:startMode(mode, reason)
    local ok, result = self.guard:start(mode, reason)
    if not ok then show(_("Không thể bắt đầu GhostGuard:\n") .. tostring(result), 8); return false end
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

function DCPROGhostGuard:syncOnlineLicense(show_result)
    if self.load_error or not self.guard then return false end
    local ok, detail, allowed, policy = self.guard:syncOnlineLicense()
    if show_result then
        show((ok and _("Đồng bộ license online hoàn tất.\n") or _("Không đồng bộ được license online. Đang dùng cache/license local nếu có.\n")) .. tostring(detail), 10)
    end
    if ok and allowed == false and self.guard:isRunning() then
        self.guard:stop("online-license-policy")
    end

    -- A Library/bootstrap launch may arrive before the first online registry sync.
    -- Keep that request pending and start it immediately after signed online
    -- authorization succeeds, so first-time customers do not need a second tap.
    if ok and allowed == true and self.pending_online_start_mode then
        local mode = self.pending_online_start_mode
        local reason = self.pending_online_start_reason or "online-license-launch"
        self.pending_online_start_mode = nil
        self.pending_online_start_reason = nil
        if not self.guard:isRunning() and not self.guard.autostart_blocked then
            UIManager:scheduleIn(0.1, function()
                if self.guard and not self.guard:isRunning() and not self.guard.autostart_blocked then
                    self:startMode(mode, reason)
                end
            end)
        end
    elseif ok and allowed == false and self.pending_online_start_mode then
        self.pending_online_start_mode = nil
        self.pending_online_start_reason = nil
        if not show_result then
            show(_("GhostGuard chưa được kích hoạt cho Serial này.\n\n") .. tostring(policy or detail), 12)
        end
    elseif ok and allowed == true and self.online_startup_sync
        and not self.startup_license_was_valid and not self.guard:isRunning()
        and not self.guard.autostart_blocked then
        -- Normal KOReader startup with an online-only license: preserve the same
        -- auto-protect / customer-auto-learning behavior as a local RSA license.
        local mode, reason
        if self.guard:isAutoProtectEnabled() and self.guard:profileApproved()
            and self.guard:protectSupported() then
            mode, reason = self.config.protect_mode, "online-auto-protect"
        elseif self.config.customer_autolearn_default and self.guard:protectSupported()
            and not self.guard:profileApproved() then
            mode, reason = self.config.calibration_mode, "online-customer-auto-learning"
        end
        if mode then
            UIManager:scheduleIn(self.config.auto_start_delay_seconds, function()
                if self.guard and not self.guard:isRunning() and not self.guard.autostart_blocked then
                    self:startMode(mode, reason)
                end
            end)
        end
    end
    return ok, detail, allowed, policy
end

function DCPROGhostGuard:showToolsPanel()
    if self.load_error then
        show(_("KOReader đã thấy plugin nhưng runtime không nạp được:\n\n") .. tostring(self.load_error), 12)
        return
    end

    local ok_sui, SUIWindow = pcall(require, "sui_window")
    if not ok_sui or not SUIWindow then
        -- SimpleUI may still be starting; never leave the Tools tab dead.
        self:showStatus()
        return
    end

    local function opener(restore_indicator)
        local function buildRoot(ctx)
            local items = {
                {
                    text_func = function() return self:simpleUIPrimaryLabel() end,
                    callback = function() self:runSmartAction("simpleui-tools") end,
                },
                {
                    text = _("Tiến độ thiết lập khách hàng"),
                    callback = function() show(self.guard:customerProgressText(), 12) end,
                },
                {
                    text = _("Hoàn tất thiết lập bảo vệ"),
                    enabled_func = function() return self.guard:profileLiveReady() end,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = self.guard:customerProgressText()
                                .. _("\n\nDuyệt profile, bật Auto Protect và chạy bảo vệ thử ngay?"),
                            ok_text = _("Hoàn tất"),
                            ok_callback = function()
                                self:completeCustomerSetupAndProtect("simpleui-customer-complete")
                                ctx.repaint()
                            end,
                        })
                    end,
                },
                {
                    text = _("Kết thúc hiệu chuẩn và tạo profile"),
                    enabled_func = function() return self.guard:isCalibrating() end,
                    callback = function()
                        local ok, result = self.guard:finishCalibration()
                        show(ok and (_("Đã tạo profile chờ duyệt:\n\n") .. tostring(result))
                            or (_("Không thể hoàn tất:\n") .. tostring(result)), 15)
                        ctx.repaint()
                    end,
                },
                {
                    text = _("Xem profile đã học"),
                    callback = function() show(self.guard.profiles:summaryText(), 15) end,
                },
                {
                    text = _("Duyệt profile"),
                    enabled_func = function() return not self.guard:isRunning() and self.guard:profileReady() end,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = self.guard.profiles:summaryText() ..
                                _("\n\nDuyệt thủ công chỉ dùng cho kỹ thuật viên; license.key phải hợp lệ."),
                            ok_text = _("Duyệt profile"),
                            ok_callback = function()
                                local approved, result = self.guard:approveProfile()
                                show(approved and _("Đã duyệt profile. Bây giờ có thể bật Protect.")
                                    or (_("Không thể duyệt:\n") .. tostring(result)), 7)
                                ctx.repaint()
                            end,
                        })
                    end,
                },
                {
                    text = _("Trạng thái GhostGuard"),
                    callback = function() self:showStatus() end,
                },
                {
                    text = _("Đồng bộ license online"),
                    callback = function() self:syncOnlineLicense(true); ctx.repaint() end,
                },
                {
                    text = _("Dừng và đóng báo cáo"),
                    enabled_func = function() return self.guard:isRunning() end,
                    callback = function() self:stopAndShow("simpleui-tools-stop"); ctx.repaint() end,
                },
                {
                    text = _("Gửi báo cáo Cloud"),
                    callback = function() self:cloudUploadFlow("simpleui-tools-cloud") end,
                },
                {
                    text = _("SAFE_MODE"),
                    checked_func = function() return self.guard:isSafeMode() end,
                    callback = function()
                        local safe = self.guard:isSafeMode()
                        if safe then
                            UIManager:show(ConfirmBox:new{
                                text = _("Tắt SAFE_MODE để cho phép GhostGuard chạy lại?"),
                                ok_text = _("Tắt SAFE_MODE"),
                                ok_callback = function()
                                    local changed, result = self.guard:setSafeMode(false)
                                    show(changed and _("SAFE_MODE đã tắt.") or tostring(result), 4)
                                    ctx.repaint()
                                end,
                            })
                        else
                            local changed, result = self.guard:setSafeMode(true)
                            show(changed and _("SAFE_MODE đã bật. GhostGuard dừng và không tự khởi động.")
                                or tostring(result), 5)
                            ctx.repaint()
                        end
                    end,
                },
            }
            return SUIWindow.MenuTable{
                inner_w = ctx.inner_w,
                items = items,
                repaint = function() ctx.repaint() end,
                push_stack = function(_id, params) ctx.push("nested_menu", params) end,
                on_close = function() end,
            }
        end

        local win = SUIWindow:new{
            name = "dcpro_ghostguard_tools",
            title = "Tools",
            screens = { __root__ = buildRoot },
            position = "bottom",
            auto_height = true,
            on_close = restore_indicator,
        }
        win:show()
    end

    if self.simpleui then
        self.simpleui:openTrackedToolsWindow(opener)
    else
        opener(function() end)
    end
end

function DCPROGhostGuard:runSmartAction(reason)
    local licensed, detail = self.guard:licenseValid(true)
    if not licensed then
        show(_("GhostGuard chưa được kích hoạt.\n\n") .. self.guard:licenseHelpText()
            .. _("\n\nChi tiết: ") .. tostring(detail), 15)
        return
    end
    if self.guard:isProtecting() then self:showStatus(); return end
    if self.guard:isCalibrating() then
        if self.guard:profileLiveReady() then
            UIManager:show(ConfirmBox:new{
                text = self.guard:customerProgressText()
                    .. _("\n\nHoàn tất thiết lập và bật bảo vệ ngay?"),
                ok_text = _("Hoàn tất"),
                ok_callback = function() self:completeCustomerSetupAndProtect(reason) end,
            })
        else
            show(self.guard:customerProgressText()
                .. _("\n\nKhách tiếp tục đọc và dùng máy bình thường."), 10)
        end
        return
    end
    if self.guard:profileLiveReady() and not self.guard:profileApproved() then
        self:completeCustomerSetupAndProtect(reason)
        return
    end
    if self.guard:isRunning() then self:showStatus(); return end
    if self.guard:profileApproved() then
        UIManager:show(ConfirmBox:new{
            text = _("Bật Protect theo profile đã duyệt và license.key hiện tại?"),
            ok_text = _("Bật Protect"),
            ok_callback = function() self:startMode(self.config.protect_mode, reason or "smart-protect") end,
        })
    else
        UIManager:show(ConfirmBox:new{
            text = _("Bắt đầu học profile? Khách chỉ cần đọc và thao tác bình thường; tiến độ được cộng dồn qua nhiều phiên."),
            ok_text = _("Bắt đầu học"),
            ok_callback = function() self:startMode(self.config.calibration_mode, reason or "smart-calibration") end,
        })
    end
end

function DCPROGhostGuard:registerSimpleUI(attempt)
    if type(rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")) == "function" then
        logger.info("DCPRO GhostGuard: Zen UI active; SimpleUI bridge skipped")
        return
    end
    if not self.simpleui or self.simpleui.registered then return end
    attempt = attempt or 1
    local ok, err = self.simpleui:register()
    if ok then return end
    if attempt < 8 then
        UIManager:scheduleIn(2, function() self:registerSimpleUI(attempt + 1) end)
    else
        logger.warn("DCPRO GhostGuard SimpleUI integration unavailable:", err)
    end
end

function DCPROGhostGuard:unregisterSimpleUI()
    if self.simpleui then self.simpleui:unregister() end
end

function DCPROGhostGuard:registerZenUI(attempt)
    if not self.zenui or self.zenui.registered then return end
    attempt = attempt or 1
    local ok, err = self.zenui:register()
    if ok then return end
    if attempt < 8 then
        UIManager:scheduleIn(2, function() self:registerZenUI(attempt + 1) end)
    else
        logger.info("DCPRO GhostGuard ZenUI integration unavailable:", err)
    end
end

function DCPROGhostGuard:unregisterZenUI()
    if self.zenui then self.zenui:unregister() end
end

function DCPROGhostGuard:onZenUIReady()
    self:unregisterSimpleUI()
    self:registerZenUI(1)
end

function DCPROGhostGuard:recordExitReason(reason, detail, traceback_text)
    local result
    if self.guard and type(self.guard.recordExitReason) == "function" then
        result = self.guard:recordExitReason(reason, detail, traceback_text)
        local terminal = reason == "UIMANAGER_QUIT"
            or reason == "UIMANAGER_RESTART"
            or reason == "UIMANAGER_REBOOT"
            or reason == "UIMANAGER_POWEROFF"
            or reason == "OS_EXIT"
        if terminal and self.guard:isRunning() then
            pcall(self.guard.stop, self.guard, "koreader-" .. tostring(reason):lower())
        end
    end
    return result
end

function DCPROGhostGuard:init()
    math.randomseed(os.time())
    local ok, err = self:loadRuntime()
    if not ok then
        self.load_error = err
        logger.warn("DCPRO GhostGuard runtime load failed:", err)
    else
        logger.info("DCPRO GhostGuard runtime loaded")
    end
    self.ui.menu:registerToMainMenu(self)

    if not self.load_error then
        UIManager:scheduleIn(0.5, function() self:registerSimpleUI(1) end)
        UIManager:scheduleIn(0.8, function() self:registerZenUI(1) end)
        UIManager:scheduleIn(1.5, function()
            self.online_startup_sync = true
            pcall(function() self:syncOnlineLicense(false) end)
            self.online_startup_sync = false
        end)
        local requested, requested_mode = self.guard:consumeLaunchRequest()
        local start_reason, start_mode
        local licensed = self.guard:licenseValid(true)
        self.startup_license_was_valid = licensed == true
        if requested then
            if licensed then
                start_reason, start_mode = "home-launcher", requested_mode
            else
                self.pending_online_start_mode = requested_mode
                self.pending_online_start_reason = "home-launcher-online"
                UIManager:scheduleIn(0.7, function()
                    show(_("Đang xác thực license GhostGuard online cho Serial máy..."), 5)
                end)
            end
        elseif licensed and self.guard:isAutoProtectEnabled() and self.guard:profileApproved()
            and self.guard:protectSupported() then
            start_reason, start_mode = "auto-protect", self.config.protect_mode
        elseif licensed and self.guard:profileLiveReady() and not self.guard:profileApproved() then
            UIManager:scheduleIn(1, function()
                show(_("GhostGuard đã có đủ dữ liệu.\nMở Tools và chọn Hoàn tất thiết lập bảo vệ."), 10)
            end)
        elseif licensed and self.config.customer_autolearn_default
            and self.guard:protectSupported() and not self.guard:profileApproved() then
            start_reason, start_mode = "customer-auto-learning", self.config.calibration_mode
        end
        if start_reason then
            UIManager:scheduleIn(self.config.auto_start_delay_seconds, function()
                if self.guard and not self.guard:isRunning() and not self.guard.autostart_blocked then
                    local started, result = self.guard:start(start_mode, start_reason)
                    if not started then show(_("GhostGuard không tự khởi động:\n") .. tostring(result), 8) end
                end
            end)
        end
    end
end

function DCPROGhostGuard:addToMainMenu(menu_items)
    local sub_items = {}
    if self.load_error then
        sub_items[#sub_items + 1] = {
            text = _("Lỗi nạp GhostGuard"), keep_menu_open = true,
            callback = function() show(_("KOReader đã thấy plugin nhưng runtime không nạp được:\n\n") .. tostring(self.load_error), 12) end,
        }
    else
        sub_items[#sub_items + 1] = {
            text = _("1. Bắt đầu/tiếp tục học profile"),
            enabled_func = function() return not self.guard:isRunning() end,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Khách dùng máy bình thường. GhostGuard chỉ học contact có dấu hiệu bất thường và cộng dồn tiến độ qua nhiều phiên."),
                    ok_text = _("Bắt đầu học"),
                    ok_callback = function() self:startMode(self.config.calibration_mode, "manual-calibration") end,
                })
            end,
        }
        sub_items[#sub_items + 1] = {
            text = _("2. Kết thúc phiên học"),
            enabled_func = function() return self.guard:isCalibrating() end,
            callback = function()
                local ok, result = self.guard:finishCalibration()
                show(ok and (_("Đã tạo profile chờ duyệt:\n\n") .. tostring(result))
                    or (_("Không thể hoàn tất:\n") .. tostring(result)), 15)
            end,
        }
        sub_items[#sub_items + 1] = {
            text = _("3. Xem profile đã học"), keep_menu_open = true,
            callback = function() show(self.guard.profiles:summaryText(), 15) end,
        }
        sub_items[#sub_items + 1] = {
            text = _("4. Duyệt profile"),
            enabled_func = function() return not self.guard:isRunning() and self.guard:profileReady() end,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = self.guard.profiles:summaryText() .. _("\n\nDuyệt profile không tự bật Protect. Yêu cầu license.key hợp lệ trong thư mục plugin."),
                    ok_text = _("Duyệt profile"),
                    ok_callback = function()
                        local ok, result = self.guard:approveProfile()
                        show(ok and _("Đã duyệt profile. Bây giờ có thể bật Protect.")
                            or (_("Không thể duyệt:\n") .. tostring(result)), 7)
                    end,
                })
            end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Hoàn tất thiết lập cho khách"),
            enabled_func = function() return self.guard:profileLiveReady() end,
            callback = function() self:completeCustomerSetupAndProtect("manual-customer-complete") end,
        }
        sub_items[#sub_items + 1] = {
            text = _("5. Bắt đầu bảo vệ theo profile"),
            enabled_func = function()
                return not self.guard:isRunning() and self.guard:profileApproved()
                    and self.guard:protectSupported()
            end,
            callback = function() self:runSmartAction("manual-protect") end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Dừng và đóng báo cáo"),
            enabled_func = function() return self.guard:isRunning() end,
            callback = function() self:stopAndShow("manual") end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Tự bảo vệ khi mở KOReader"),
            enabled_func = function()
                return self.guard:profileApproved() and self.guard:protectSupported()
            end,
            checked_func = function() return self.guard:isAutoProtectEnabled() end,
            callback = function()
                local enable = not self.guard:isAutoProtectEnabled()
                local changed, result = self.guard:setAutoProtectEnabled(enable)
                show(changed and (enable and _("Đã bật tự bảo vệ.") or _("Đã tắt tự bảo vệ.")) or tostring(result), 6)
            end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Quan sát thuần túy"),
            enabled_func = function() return not self.guard:isRunning() end,
            callback = function() self:startMode(self.config.default_mode, "manual-observe") end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Xóa profile và hiệu chuẩn lại"),
            enabled_func = function() return not self.guard:isRunning() end,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Xóa profile chờ duyệt và profile đã duyệt? Báo cáo cũ không bị xóa."),
                    ok_text = _("Xóa profile"),
                    ok_callback = function()
                        local ok, result = self.guard:resetProfile()
                        show(ok and _("Đã xóa profile. Hãy hiệu chuẩn lại.") or tostring(result), 5)
                    end,
                })
            end,
        }
        sub_items[#sub_items + 1] = {
            text = _("License GhostGuard"), keep_menu_open = true,
            callback = function()
                show(self.guard:licenseStatusText() .. "\n\n" .. self.guard:licenseHelpText(), 14)
            end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Đồng bộ license online"), keep_menu_open = true,
            callback = function() self:syncOnlineLicense(true) end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Dừng và gửi báo cáo Cloud"),
            callback = function() self:cloudUploadFlow("manual-cloud") end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Trạng thái Cloud"), keep_menu_open = true,
            callback = function() show(self.guard:cloudStatusText(), 15) end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Tích hợp SimpleUI"), keep_menu_open = true,
            callback = function()
                self:registerSimpleUI(1)
                show(_("SimpleUI:\n") .. self.simpleui:statusText() ..
                    _("\n\nTab Tools được tự đặt ngay bên phải Home. Quick Actions cũ vẫn có thể dùng nếu cần."), 12)
            end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Trạng thái"), keep_menu_open = true,
            callback = function() self:showStatus() end,
        }
        sub_items[#sub_items + 1] = {
            text = _("Bật SAFE_MODE"),
            checked_func = function() return self.guard:isSafeMode() end,
            callback = function()
                local safe = self.guard:isSafeMode()
                if safe then
                    UIManager:show(ConfirmBox:new{
                        text = _("Tắt SAFE_MODE để cho phép GhostGuard chạy lại?"),
                        ok_text = _("Tắt SAFE_MODE"),
                        ok_callback = function()
                            local changed, result = self.guard:setSafeMode(false)
                            show(changed and _("SAFE_MODE đã tắt.") or tostring(result), 4)
                        end,
                    })
                else
                    local changed, result = self.guard:setSafeMode(true)
                    show(changed and _("SAFE_MODE đã bật. GhostGuard dừng và không tự khởi động.") or tostring(result), 5)
                end
            end,
        }
    end
    menu_items.dcpro_ghostguard = {
        text = _("DCPRO GhostGuard"), sorting_hint = "more_tools", sub_item_table = sub_items,
    }
end

function DCPROGhostGuard:onSuspend()
    if not self.guard then return end
    -- Never keep a touch wrapper installed across Kindle suspend/resume.
    -- KOReader may replace or inhibit its input handlers while sleeping; a
    -- stale wrapper can leave the touchscreen unusable after wake.
    self._resume_protect_after_suspend = self.guard:isProtecting()
        or (self.guard:isAutoProtectEnabled() and self.guard:profileApproved())
    self.guard:stop("suspend-fail-open")
end

function DCPROGhostGuard:onResume()
    if not self.guard then return end
    local should_resume = self._resume_protect_after_suspend == true
    self._resume_protect_after_suspend = false
    if not should_resume then return end

    -- Let KOReader finish restoring Device.input before installing a fresh
    -- wrapper. If anything is not ready, remain fail-open instead of risking
    -- a locked touchscreen.
    UIManager:scheduleIn(4, function()
        if not self.guard or self.guard:isRunning() or self.guard:isSafeMode() then return end
        local licensed = self.guard:licenseValid(true)
        if not licensed or not self.guard:profileApproved()
            or not self.guard:protectSupported() then
            return
        end
        local ok, result = self.guard:start(self.config.protect_mode, "resume-auto-protect")
        if not ok then
            logger.warn("DCPRO GhostGuard resume Protect skipped:", result)
        end
    end)
end

function DCPROGhostGuard:onPowerOff()
    self:recordExitReason("POWER_OFF", "KOReader dispatched onPowerOff", debug.traceback("onPowerOff", 2))
    self:unregisterSimpleUI()
    self:unregisterZenUI()
    if self.guard then self.guard:stop("poweroff") end
end

function DCPROGhostGuard:onReboot()
    self:recordExitReason("REBOOT", "KOReader dispatched onReboot", debug.traceback("onReboot", 2))
    self:unregisterSimpleUI()
    self:unregisterZenUI()
    if self.guard then self.guard:stop("reboot") end
end

function DCPROGhostGuard:onCloseWidget()
    -- Do not turn an ordinary widget teardown into a fake koreader-exit. Keep
    -- the engine alive, flush evidence, and let UIManager/os.exit wrappers
    -- record the actual termination caller.
    self:recordExitReason("ON_CLOSE_WIDGET",
        "KOReader called plugin onCloseWidget; ENGINE_ACTION=FLUSH_KEEP_RUNNING",
        debug.traceback("GhostGuard onCloseWidget callback", 2))
    if self.guard then self.guard:flush() end
end

function DCPROGhostGuard:stopPlugin()
    self:recordExitReason("PLUGIN_STOP", "GhostGuard plugin explicitly stopped", debug.traceback("stopPlugin", 2))
    self:unregisterSimpleUI()
    self:unregisterZenUI()
    if self.guard then self.guard:stop("plugin-stop") end
    return true
end

return DCPROGhostGuard
