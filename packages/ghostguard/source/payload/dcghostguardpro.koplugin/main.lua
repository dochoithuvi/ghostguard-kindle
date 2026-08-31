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
    local ExitDiagnostics; ExitDiagnostics, err = load_local("exit_diagnostics.lua")
    if not ExitDiagnostics then return false, "exit_diagnostics.lua: " .. err end
    local GhostGuard; GhostGuard, err = load_local("ghostguard.lua")
    if not GhostGuard then return false, "ghostguard.lua: " .. err end
    local ok, guard_or_err = pcall(GhostGuard.new, GhostGuard, config, Storage, TouchObserver,
        ProfileManager, LicenseManager, plugin_dir)
    if not ok then return false, "GhostGuard:new: " .. tostring(guard_or_err) end
    self.config, self.guard = config, guard_or_err

    -- v0.9: continuous adaptive learning. A fault in this optional layer must
    -- never prevent the proven core protection path from loading.
    local AdaptiveBootstrap, adaptive_err = load_local("adaptive_bootstrap.lua")
    if AdaptiveBootstrap then
        local call_ok, install_ok, adaptive_or_err = pcall(AdaptiveBootstrap, self.guard, config)
        if call_ok and install_ok == true then
            self.adaptive = adaptive_or_err
            logger.info("DCPRO GhostGuard continuous learning v0.9 loaded")
        else
            logger.warn("DCPRO GhostGuard adaptive learning unavailable:",
                call_ok and adaptive_or_err or install_ok)
        end
    else
        logger.warn("DCPRO GhostGuard adaptive bootstrap missing:", adaptive_err)
    end

    -- SimpleUI is the only UI bridge in this local build.
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
    self.exit_diagnostics = ExitDiagnostics:new(config, self.guard.storage)
    self.guard.exit_diagnostics = self.exit_diagnostics
    self.exit_diagnostics:install(self)
    self.guard.on_profile_ready = function(_guard, progress)
        UIManager:scheduleIn(0.1, function()
            show(_("GhostGuard đã học đủ dữ liệu.\n\n") .. tostring(progress)
                .. _("\n\nChạm GhostGuard để kích hoạt profile và bật bảo vệ."), 14)
        end)
    end
    return true
end

function DCPROGhostGuard:startMode(mode, reason)
    local ok, result = self.guard:start(mode, reason)
    if not ok then show(_("Không thể bắt đầu GhostGuard:\n") .. tostring(result), 8); return false end
    if mode == self.config.calibration_mode then
        show(_("Đang học cách khách sử dụng máy.\nHãy đọc và thao tác bình thường; GhostGuard chưa chặn cảm ứng.\nPhiên: ") .. tostring(result), 8)
        UIManager:scheduleIn(self.config.calibration_input_watchdog_seconds or 30, function()
            if not self.guard or not self.guard:isCalibrating() then return end
            local st = self.guard:inputLearningStatus()
            if not st.hook_installed then
                self.guard:stop("calibration-input-missing")
                show(_("GhostGuard đã dừng học vì không gắn được bộ nghe cảm ứng. Không có tiến độ giả được lưu."), 12)
            elseif st.raw_events == 0 then
                show(_("GhostGuard đang học nhưng chưa nhận sự kiện cảm ứng nào. Hãy chạm/lật vài trang; nếu bộ đếm vẫn không tăng, mở Trạng thái GhostGuard để kiểm tra."), 10)
            end
        end)
    elseif mode == self.config.protect_mode then
        show(_("Đã bật bảo vệ theo profile và license.key hợp lệ.\nPhiên: ") .. tostring(result), 7)
    else
        show(_("Đã bắt đầu Observe-Only.\nPhiên: ") .. tostring(result), 4)
    end
    return true
end

function DCPROGhostGuard:showStatus()
    if self.load_error then show(tostring(self.load_error), 12); return end
    show(self.guard:statusText(), 18)
end

function DCPROGhostGuard:showContinuousLearning()
    if not self.adaptive then
        show(_("Học liên tục chưa sẵn sàng."), 8)
        return
    end
    pcall(self.adaptive.writeExternalStatus, self.adaptive, true)
    pcall(self.adaptive.writeProfileSnapshot, self.adaptive)
    show(self.adaptive:statusText()
        .. "\n\nBáo cáo USB: /mnt/us/GhostGuard_Reports/"
        .. "\n- ContinuousLearning_Status.txt"
        .. "\n- ContinuousLearning_Changes.log"
        .. "\n- ActiveProfile_AutoLearned.txt", 15)
end

function DCPROGhostGuard:stopAndShow(reason)
    if not self.guard:isRunning() then show(_("GhostGuard đang dừng."), 3); return end
    local _, result = self.guard:stop(reason or "manual")
    show(_("GhostGuard đã dừng.\nBáo cáo GhostGuard đã được tạo và lưu trên Kindle.\n") .. tostring(result), 6)
end


function DCPROGhostGuard:simpleUIPrimaryLabel()
    if not self.guard then return "GhostGuard" end
    local licensed = self.guard:licenseValid(false)
    if not licensed then return "GhostGuard: Cần license.key" end
    if self.guard:isProtecting() then return "GhostGuard: Đang bảo vệ" end
    if self.guard:isCalibrating() then
        return self.guard:profileLiveReady() and "GhostGuard: Kích hoạt profile"
            or "GhostGuard: Đang học cách dùng máy"
    end
    if self.guard:isRunning() then return "GhostGuard: Đang quan sát" end
    if self.guard:profileApproved() then return "GhostGuard: Bật bảo vệ" end
    if self.guard:profileLiveReady() then return "GhostGuard: Kích hoạt profile" end
    if self.guard.profiles and self.guard.profiles.pending then return "GhostGuard: Tiếp tục học profile" end
    return "GhostGuard: Bắt đầu học profile"
end

function DCPROGhostGuard:activateReadyProfileAndProtect(reason)
    local ok, result = self.guard:completeCustomerSetup()
    if not ok then show(_("Chưa thể kích hoạt profile:\n") .. tostring(result), 12); return false end
    local started, start_result = self.guard:start(self.config.protect_mode, reason or "profile-activate")
    if started then
        show(_("Profile đã kích hoạt.\nGhostGuard đang bảo vệ và Auto Protect đã bật."), 8)
        return true
    end
    show(_("Profile đã kích hoạt nhưng chưa bật được Protect:\n") .. tostring(start_result), 10)
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
    if not ok_sui or not SUIWindow then self:showStatus(); return end

    local function opener(restore_indicator)
        local function buildRoot(ctx)
            local items = {
                { text_func = function() return self:simpleUIPrimaryLabel() end,
                  callback = function() self:runSmartAction("simpleui-tools"); ctx.repaint() end },
                { text = _("Trạng thái GhostGuard"), callback = function() self:showStatus() end },
                { text = _("Profile đang dùng"), callback = function() show(self.guard.profiles:summaryText(), 15) end },
                { text = _("Học liên tục & báo cáo"), callback = function() self:showContinuousLearning() end },
                { text = _("Tự bảo vệ khi mở KOReader"),
                  enabled_func = function() return self.guard:profileApproved() and self.guard:protectSupported() end,
                  checked_func = function() return self.guard:isAutoProtectEnabled() end,
                  callback = function()
                      local enable = not self.guard:isAutoProtectEnabled()
                      local changed, result = self.guard:setAutoProtectEnabled(enable)
                      show(changed and (enable and _("Đã bật tự bảo vệ.") or _("Đã tắt tự bảo vệ.")) or tostring(result), 5)
                      ctx.repaint()
                  end },
                { text = _("Dừng GhostGuard"), enabled_func = function() return self.guard:isRunning() end,
                  callback = function() self:stopAndShow("simpleui-tools-stop"); ctx.repaint() end },
                { text = _("Xóa profile & học lại"), enabled_func = function() return not self.guard:isRunning() end,
                  callback = function()
                      UIManager:show(ConfirmBox:new{
                          text = _("Xóa profile hiện tại và dữ liệu học liên tục để học lại từ đầu? Báo cáo cũ vẫn được giữ."),
                          ok_text = _("Xóa & học lại"),
                          ok_callback = function()
                              local ok, result = self.guard:resetProfile()
                              show(ok and _("Đã xóa profile. Chạm GhostGuard để bắt đầu học lại.") or tostring(result), 6)
                              ctx.repaint()
                          end,
                      })
                  end },
                { text = _("SAFE_MODE"), checked_func = function() return self.guard:isSafeMode() end,
                  callback = function()
                      local safe = self.guard:isSafeMode()
                      if safe then
                          UIManager:show(ConfirmBox:new{ text = _("Tắt SAFE_MODE để cho phép GhostGuard chạy lại?"), ok_text = _("Tắt SAFE_MODE"), ok_callback = function()
                              local changed, result = self.guard:setSafeMode(false); show(changed and _("SAFE_MODE đã tắt.") or tostring(result), 4); ctx.repaint()
                          end })
                      else
                          local changed, result = self.guard:setSafeMode(true)
                          show(changed and _("SAFE_MODE đã bật. GhostGuard dừng và không tự khởi động.") or tostring(result), 5)
                          ctx.repaint()
                      end
                  end },
            }
            return SUIWindow.MenuTable{
                inner_w = ctx.inner_w, items = items,
                repaint = function() ctx.repaint() end,
                push_stack = function(_id, params) ctx.push("nested_menu", params) end,
                on_close = function() end,
            }
        end
        local win = SUIWindow:new{
            name = "dcpro_ghostguard_tools", title = "GhostGuard",
            screens = { __root__ = buildRoot }, position = "bottom",
            auto_height = true, on_close = restore_indicator,
        }
        win:show()
    end
    if self.simpleui then self.simpleui:openTrackedToolsWindow(opener) else opener(function() end) end
end

function DCPROGhostGuard:runSmartAction(reason)
    local licensed, detail = self.guard:licenseValid(true)
    if not licensed then show(_("GhostGuard chưa được kích hoạt.\n\n") .. self.guard:licenseHelpText() .. _("\n\nChi tiết: ") .. tostring(detail), 15); return end
    if self.guard:isProtecting() then self:showStatus(); return end
    if self.guard:isCalibrating() then
        if self.guard:profileLiveReady() then
            UIManager:show(ConfirmBox:new{ text = self.guard:customerProgressText() .. _("\n\nProfile đã sẵn sàng. Kích hoạt và bật bảo vệ ngay?"), ok_text = _("Kích hoạt"), ok_callback = function() self:activateReadyProfileAndProtect(reason) end })
        else show(self.guard:customerProgressText() .. _("\n\nTiếp tục đọc và sử dụng máy bình thường."), 10) end
        return
    end
    if self.guard:profileLiveReady() and not self.guard:profileApproved() then self:activateReadyProfileAndProtect(reason); return end
    if self.guard:isRunning() then self:showStatus(); return end
    if self.guard:profileApproved() then
        UIManager:show(ConfirmBox:new{ text = _("Bật Protect theo profile đã duyệt và license.key hiện tại?"), ok_text = _("Bật Protect"), ok_callback = function() self:startMode(self.config.protect_mode, reason or "smart-protect") end })
    else
        UIManager:show(ConfirmBox:new{ text = _("Bắt đầu học profile? Chỉ cần đọc và thao tác bình thường; tiến độ được cộng dồn qua nhiều phiên."), ok_text = _("Bắt đầu học"), ok_callback = function() self:startMode(self.config.calibration_mode, reason or "smart-calibration") end })
    end
end

function DCPROGhostGuard:registerSimpleUI(attempt)
    if not self.simpleui or self.simpleui.registered then return end
    attempt = attempt or 1
    local ok, err = self.simpleui:register()
    if ok then return end
    if attempt < 8 then UIManager:scheduleIn(2, function() self:registerSimpleUI(attempt + 1) end) else logger.warn("DCPRO GhostGuard SimpleUI integration unavailable:", err) end
end

function DCPROGhostGuard:unregisterSimpleUI()
    if self.simpleui then self.simpleui:unregister() end
end

function DCPROGhostGuard:recordExitReason(reason, detail, traceback_text)
    local result
    if self.guard and type(self.guard.recordExitReason) == "function" then
        result = self.guard:recordExitReason(reason, detail, traceback_text)
        local terminal = reason == "UIMANAGER_QUIT" or reason == "UIMANAGER_RESTART" or reason == "UIMANAGER_REBOOT" or reason == "UIMANAGER_POWEROFF" or reason == "OS_EXIT"
        if terminal and self.guard:isRunning() then pcall(self.guard.stop, self.guard, "koreader-" .. tostring(reason):lower()) end
    end
    return result
end

function DCPROGhostGuard:init()
    math.randomseed(os.time())
    local ok, err = self:loadRuntime()
    if not ok then self.load_error = err; logger.warn("DCPRO GhostGuard runtime load failed:", err) else logger.info("DCPRO GhostGuard runtime loaded") end
    self.ui.menu:registerToMainMenu(self)
    if not self.load_error then
        UIManager:scheduleIn(0.5, function() self:registerSimpleUI(1) end)
        UIManager:scheduleIn(1.5, function() self.online_startup_sync = true; pcall(function() self:syncOnlineLicense(false) end); self.online_startup_sync = false end)
        local requested, requested_mode = self.guard:consumeLaunchRequest()
        local start_reason, start_mode
        local licensed = self.guard:licenseValid(true)
        self.startup_license_was_valid = licensed == true
        if requested then
            if licensed then start_reason, start_mode = "home-launcher", requested_mode else
                self.pending_online_start_mode = requested_mode; self.pending_online_start_reason = "home-launcher-online"
                UIManager:scheduleIn(0.7, function() show(_("Đang xác thực license GhostGuard online cho Serial máy..."), 5) end)
            end
        elseif licensed and self.guard:isAutoProtectEnabled() and self.guard:profileApproved() and self.guard:protectSupported() then
            start_reason, start_mode = "auto-protect", self.config.protect_mode
        elseif licensed and self.guard:profileLiveReady() and not self.guard:profileApproved() then
            UIManager:scheduleIn(1, function() show(_("GhostGuard đã có đủ dữ liệu.\nChạm GhostGuard để kích hoạt profile."), 10) end)
        elseif licensed and self.config.customer_autolearn_default and self.guard:protectSupported() and not self.guard:profileApproved() then
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
        sub_items[#sub_items + 1] = { text = _("Lỗi nạp GhostGuard"), keep_menu_open = true,
            callback = function() show(_("KOReader đã thấy plugin nhưng runtime không nạp được:\n\n") .. tostring(self.load_error), 12) end }
    else
        sub_items[#sub_items + 1] = { text_func = function() return self:simpleUIPrimaryLabel() end,
            callback = function() self:runSmartAction("main-menu") end }
        sub_items[#sub_items + 1] = { text = _("Trạng thái GhostGuard"), keep_menu_open = true,
            callback = function() self:showStatus() end }
        sub_items[#sub_items + 1] = { text = _("Profile đang dùng"), keep_menu_open = true,
            callback = function() show(self.guard.profiles:summaryText(), 15) end }
        sub_items[#sub_items + 1] = { text = _("Học liên tục & báo cáo"), keep_menu_open = true,
            callback = function() self:showContinuousLearning() end }
        sub_items[#sub_items + 1] = { text = _("Tự bảo vệ khi mở KOReader"),
            enabled_func = function() return self.guard:profileApproved() and self.guard:protectSupported() end,
            checked_func = function() return self.guard:isAutoProtectEnabled() end,
            callback = function()
                local enable = not self.guard:isAutoProtectEnabled()
                local changed, result = self.guard:setAutoProtectEnabled(enable)
                show(changed and (enable and _("Đã bật tự bảo vệ.") or _("Đã tắt tự bảo vệ.")) or tostring(result), 5)
            end }
        sub_items[#sub_items + 1] = { text = _("Dừng GhostGuard"), enabled_func = function() return self.guard:isRunning() end,
            callback = function() self:stopAndShow("manual") end }
        sub_items[#sub_items + 1] = { text = _("License"), keep_menu_open = true,
            callback = function() show(self.guard:licenseStatusText(), 10) end }
        sub_items[#sub_items + 1] = { text = _("Xóa profile & học lại"), enabled_func = function() return not self.guard:isRunning() end,
            callback = function() UIManager:show(ConfirmBox:new{
                text = _("Xóa profile hiện tại và dữ liệu học liên tục để học lại từ đầu? Báo cáo cũ vẫn được giữ."),
                ok_text = _("Xóa & học lại"),
                ok_callback = function()
                    local ok, result = self.guard:resetProfile()
                    show(ok and _("Đã xóa profile. Chạm GhostGuard để bắt đầu học lại.") or tostring(result), 6)
                end,
            }) end }
        sub_items[#sub_items + 1] = { text = _("SAFE_MODE"), checked_func = function() return self.guard:isSafeMode() end,
            callback = function()
                local safe = self.guard:isSafeMode()
                if safe then
                    UIManager:show(ConfirmBox:new{ text = _("Tắt SAFE_MODE để cho phép GhostGuard chạy lại?"), ok_text = _("Tắt SAFE_MODE"), ok_callback = function()
                        local changed, result = self.guard:setSafeMode(false); show(changed and _("SAFE_MODE đã tắt.") or tostring(result), 4)
                    end })
                else
                    local changed, result = self.guard:setSafeMode(true)
                    show(changed and _("SAFE_MODE đã bật. GhostGuard dừng và không tự khởi động.") or tostring(result), 5)
                end
            end }
    end
    menu_items.dcpro_ghostguard = { text = _("DCPRO GhostGuard"), sorting_hint = "more_tools", sub_item_table = sub_items }
end

function DCPROGhostGuard:onSuspend()
    if not self.guard then return end
    self._resume_calibration_after_suspend = self.guard:isCalibrating()
    self._resume_protect_after_suspend = self.guard:isProtecting() or (self.guard:isAutoProtectEnabled() and self.guard:profileApproved())
    self.guard:stop("suspend-fail-open")
end

function DCPROGhostGuard:onResume()
    if not self.guard then return end
    local resume_calibration = self._resume_calibration_after_suspend == true
    local resume_protect = self._resume_protect_after_suspend == true
    self._resume_calibration_after_suspend = false
    self._resume_protect_after_suspend = false
    if not resume_calibration and not resume_protect then return end
    UIManager:scheduleIn(self.config.resume_restart_delay_seconds or 4, function()
        if not self.guard or self.guard:isRunning() or self.guard:isSafeMode() then return end
        local licensed = self.guard:licenseValid(true)
        if not licensed then return end
        if resume_calibration and not self.guard:profileApproved() then
            if self.guard:profileLiveReady() then
                show(_("GhostGuard đã học đủ dữ liệu trong phiên trước. Chạm GhostGuard để kích hoạt profile."), 10)
                return
            end
            local ok, result = self.guard:start(self.config.calibration_mode, "resume-customer-learning")
            if not ok then logger.warn("DCPRO GhostGuard resume Calibration skipped:", result) end
            return
        end
        if resume_protect and self.guard:profileApproved() and self.guard:protectSupported() then
            local ok, result = self.guard:start(self.config.protect_mode, "resume-auto-protect")
            if not ok then logger.warn("DCPRO GhostGuard resume Protect skipped:", result) end
        end
    end)
end

function DCPROGhostGuard:onPowerOff()
    self:recordExitReason("POWER_OFF", "KOReader dispatched onPowerOff", debug.traceback("onPowerOff", 2))
    self:unregisterSimpleUI(); if self.guard then self.guard:stop("poweroff") end
end

function DCPROGhostGuard:onReboot()
    self:recordExitReason("REBOOT", "KOReader dispatched onReboot", debug.traceback("onReboot", 2))
    self:unregisterSimpleUI(); if self.guard then self.guard:stop("reboot") end
end

function DCPROGhostGuard:onCloseWidget()
    self:recordExitReason("ON_CLOSE_WIDGET", "KOReader called plugin onCloseWidget; ENGINE_ACTION=FLUSH_KEEP_RUNNING", debug.traceback("GhostGuard onCloseWidget callback", 2))
    if self.guard then self.guard:flush() end
end

function DCPROGhostGuard:stopPlugin()
    self:recordExitReason("PLUGIN_STOP", "GhostGuard plugin explicitly stopped", debug.traceback("stopPlugin", 2))
    self:unregisterSimpleUI(); if self.guard then self.guard:stop("plugin-stop") end
    return true
end

return DCPROGhostGuard
