local logger = require("logger")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local _ = require("gettext")

local SimpleUIBridge = {}
SimpleUIBridge.__index = SimpleUIBridge

local ACTION_IDS = {
    "dcpro_ghostguard_smart",
    "dcpro_ghostguard_status",
    "dcpro_ghostguard_stop",
    "dcpro_ghostguard_cloud",
}

local TOOLS_LABEL = "Tools"
local DEFAULT_PLUGIN_KEY = "dcghostguardpro"
local LEGACY_PLUGIN_KEYS = { dcproghostguard = true, dcghostguardpro = true }
local TOOLS_PLUGIN_METHOD = "showToolsPanel"

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

local function copy_without(list, value)
    local out = {}
    for _, item in ipairs(list or {}) do
        if item ~= value then out[#out + 1] = item end
    end
    return out
end

local function resolve_module(current_name, legacy_name, validator)
    local loaded = package.loaded[current_name] or package.loaded[legacy_name]
    if loaded and validator(loaded) then
        package.loaded[current_name] = loaded
        package.loaded[legacy_name] = loaded
        return loaded
    end

    local ok, result = pcall(require, current_name)
    if not ok or not result or not validator(result) then
        ok, result = pcall(require, legacy_name)
    end

    if ok and result and validator(result) then
        -- Keep both names populated. This lets the rest of GhostGuard keep
        -- working with older require() paths while supporting refactored
        -- SimpleUI installations.
        package.loaded[current_name] = result
        package.loaded[legacy_name] = result
        return result
    end

    return nil, ok and ("SimpleUI module API unavailable: " .. current_name)
        or tostring(result)
end

function SimpleUIBridge:new(owner, plugin_dir)
    return setmetatable({
        owner = owner,
        plugin_dir = plugin_dir,
        qa = nil,
        config = nil,
        registered = false,
        tools_tab_id = nil,
        tools_tab_ready = false,
        tools_tab_detail = nil,
        last_error = nil,
        profile_ready_popup_installed = false,
        plugin_key = (owner and owner.name) or DEFAULT_PLUGIN_KEY,
    }, self)
end

function SimpleUIBridge:resolveQA()
    return resolve_module(
        "features/sui_quickactions",
        "sui_quickactions",
        function(mod) return type(mod.register) == "function" end
    )
end

function SimpleUIBridge:resolveConfig()
    return resolve_module(
        "infra/sui_config",
        "sui_config",
        function(mod) return type(mod.loadTabConfig) == "function" end
    )
end

function SimpleUIBridge:installWindowCompatibilityAlias()
    if package.loaded["sui_window"] then return true end
    local ok, window = pcall(require, "engines/sui_window")
    if ok and window then
        package.loaded["sui_window"] = window
        return true
    end

    -- Older SimpleUI releases still expose the legacy path directly.
    ok, window = pcall(require, "sui_window")
    if ok and window then
        package.loaded["engines/sui_window"] = window
        return true
    end
    return false, tostring(window)
end

function SimpleUIBridge:resolveSimpleUIPlugin()
    local fm_mod = package.loaded["apps/filemanager/filemanager"]
    local fm = fm_mod and fm_mod.instance
    if fm and fm._simpleui_plugin then return fm._simpleui_plugin end
    local rui_mod = package.loaded["apps/reader/readerui"]
    local rui = rui_mod and rui_mod.instance
    if rui and rui.simpleui then return rui.simpleui end
    return nil
end

function SimpleUIBridge:rebuildNavbars()
    local plugin = self:resolveSimpleUIPlugin()
    if plugin and type(plugin._rebuildAllNavbars) == "function" then
        local ok, err = pcall(plugin._rebuildAllNavbars, plugin)
        if not ok then logger.warn("DCPRO GhostGuard could not rebuild SimpleUI navbar:", err) end
        return ok
    end
    return false
end

function SimpleUIBridge:installProfileReadyApprovalPopup()
    if self.profile_ready_popup_installed then return true end
    local owner = self.owner
    local guard = owner and owner.guard
    if not guard or type(owner.completeCustomerSetupAndProtect) ~= "function" then
        return false, "GhostGuard owner is not ready for profile approval popup"
    end

    guard.on_profile_ready = function(_guard, progress)
        UIManager:scheduleIn(0.1, function()
            local live_guard = owner.guard
            if not live_guard then return end
            if type(live_guard.profileApproved) == "function" and live_guard:profileApproved() then return end
            if type(live_guard.protectSupported) == "function" and not live_guard:protectSupported() then return end

            UIManager:show(ConfirmBox:new{
                text = _("GHOSTGUARD ĐÃ HỌC XONG\n\n") .. tostring(progress)
                    .. _("\n\nProfile bảo vệ đã sẵn sàng. Kích hoạt bảo vệ tự động ngay bây giờ?"),
                cancel_text = _("Để sau"),
                ok_text = _("Kích hoạt"),
                flush_events_on_show = true,
                cancel_callback = function()
                    logger.info("DCPRO GhostGuard customer deferred ready profile approval")
                end,
                ok_callback = function()
                    owner:completeCustomerSetupAndProtect("customer-profile-ready-popup")
                end,
            })
        end)
    end

    self.profile_ready_popup_installed = true
    logger.info("DCPRO GhostGuard installed customer profile-ready approval popup")
    return true
end

function SimpleUIBridge:findOrCreateToolsQA(config)
    local list = config.getCustomQAList and config.getCustomQAList() or {}
    local tools_id
    local current_key = self.plugin_key or DEFAULT_PLUGIN_KEY
    for _, id in ipairs(list) do
        local cfg = config.getCustomQAConfig and config.getCustomQAConfig(id) or {}
        -- Reuse and migrate tabs created by older GhostGuard builds. The
        -- plugin registration key must match owner.name, not a guessed folder.
        if cfg.plugin_method == TOOLS_PLUGIN_METHOD
            and (cfg.plugin_key == current_key or LEGACY_PLUGIN_KEYS[cfg.plugin_key]) then
            tools_id = id
            break
        end
    end

    if not tools_id then
        if type(config.nextCustomQAId) ~= "function" then
            return nil, "SimpleUI custom Quick Action API unavailable"
        end
        tools_id = config.nextCustomQAId()
        list[#list + 1] = tools_id
        if type(config.saveCustomQAList) == "function" then config.saveCustomQAList(list) end
    end

    local icon = self.plugin_dir .. "assets/tools.svg"
    if type(config.saveCustomQAConfig) ~= "function" then
        return nil, "SimpleUI cannot save custom Quick Action"
    end
    config.saveCustomQAConfig(
        tools_id,
        TOOLS_LABEL,
        nil,
        nil,
        icon,
        current_key,
        TOOLS_PLUGIN_METHOD,
        nil,
        nil
    )
    return tools_id
end

function SimpleUIBridge:ensureToolsTab()
    local config, cfg_err = self:resolveConfig()
    if not config then
        self.tools_tab_ready = false
        self.tools_tab_detail = cfg_err
        return false, cfg_err
    end

    local tools_id, create_err = self:findOrCreateToolsQA(config)
    if not tools_id then
        self.tools_tab_ready = false
        self.tools_tab_detail = create_err
        return false, create_err
    end

    local tabs = config.loadTabConfig()
    local clean = copy_without(tabs, tools_id)
    local max_tabs = 6
    if type(config.effectiveMaxTabs) == "function" then
        local ok, value = pcall(config.effectiveMaxTabs)
        if ok and tonumber(value) then max_tabs = tonumber(value) end
    elseif tonumber(config.MAX_TABS) then
        max_tabs = tonumber(config.MAX_TABS)
    end

    -- In the normal bottom bar this yields:
    -- Library – Collections – Home – Tools – History – Power.
    local anchor = nil
    for i, id in ipairs(clean) do
        if id == "homescreen" then anchor = i; break end
    end
    if not anchor then
        for i, id in ipairs(clean) do
            if id == "home" then anchor = i; break end
        end
    end
    anchor = anchor or #clean

    local replaced
    if #clean >= max_tabs then
        -- Prefer replacing SimpleUI Settings: it remains reachable from KOReader Tools.
        local replace_index
        for i, id in ipairs(clean) do
            if id == "sui_settings" then replace_index = i; break end
        end
        if not replace_index then
            for i, id in ipairs(clean) do
                if id == "recent" then replace_index = i; break end
            end
        end
        if not replace_index then
            self.tools_tab_ready = false
            self.tools_tab_detail = "Bottom bar is full; free one slot or disable Navpager"
            return false, self.tools_tab_detail
        end
        replaced = clean[replace_index]
        table.remove(clean, replace_index)
        if replace_index <= anchor then anchor = math.max(0, anchor - 1) end
    end

    table.insert(clean, math.min(anchor + 1, #clean + 1), tools_id)
    if type(config.saveTabConfig) == "function" then config.saveTabConfig(clean) end
    if type(config.invalidateTabsCache) == "function" then config.invalidateTabsCache() end

    self.config = config
    self.tools_tab_id = tools_id
    self.tools_tab_ready = contains(clean, tools_id)
    self.tools_tab_detail = replaced and ("replaced " .. replaced) or "placed after Home"
    self:rebuildNavbars()
    logger.info("DCPRO GhostGuard installed SimpleUI Tools tab:", tools_id, self.tools_tab_detail)
    return self.tools_tab_ready, self.tools_tab_detail
end

function SimpleUIBridge:register()
    if self.registered and self.tools_tab_ready then return true, "already-registered" end
    local qa, err = self:resolveQA()
    if not qa then self.last_error = err; return false, err end

    -- main.lua still supports the legacy require("sui_window") path. Populate
    -- that alias up front when running against refactored SimpleUI versions so
    -- opening the Tools tab does not silently fall back to the status dialog.
    local window_ok, window_err = self:installWindowCompatibilityAlias()
    if not window_ok then
        logger.warn("DCPRO GhostGuard SimpleUI window compatibility unavailable:", window_err)
    end

    local owner = self.owner
    local icon = self.plugin_dir .. "assets/ghostguard.svg"

    local registered_ids = {}
    local function add(descriptor)
        local ok, result = pcall(qa.register, descriptor)
        if not ok or result == false then
            for _, id in ipairs(registered_ids) do pcall(qa.unregister, id) end
            return false, ok and "SimpleUI rejected action " .. descriptor.id or tostring(result)
        end
        registered_ids[#registered_ids + 1] = descriptor.id
        return true
    end

    local ok, reg_err = add{
        id = ACTION_IDS[1],
        label = "GhostGuard",
        icon = icon,
        get_label = function() return owner:simpleUIPrimaryLabel() end,
        is_in_place = true,
        is_async_in_place = true,
        execute = function(_ctx) owner:runSmartAction("simpleui") end,
    }
    if not ok then self.last_error = reg_err; return false, reg_err end
    ok, reg_err = add{
        id = ACTION_IDS[2],
        label = "GhostGuard: Trạng thái",
        icon = icon,
        is_in_place = true,
        is_async_in_place = true,
        execute = function(_ctx) owner:showStatus() end,
    }
    if not ok then self.last_error = reg_err; return false, reg_err end
    ok, reg_err = add{
        id = ACTION_IDS[3],
        label = "GhostGuard: Dừng",
        icon = icon,
        is_in_place = true,
        is_async_in_place = true,
        execute = function(_ctx) owner:stopAndShow("simpleui-stop") end,
    }
    if not ok then self.last_error = reg_err; return false, reg_err end
    ok, reg_err = add{
        id = ACTION_IDS[4],
        label = "GhostGuard: Gửi Cloud",
        icon = icon,
        is_in_place = true,
        is_async_in_place = true,
        execute = function(_ctx) owner:cloudUploadFlow("simpleui-cloud") end,
    }
    if not ok then self.last_error = reg_err; return false, reg_err end

    self.qa = qa
    self.registered = true
    local tab_ok, tab_detail = self:ensureToolsTab()
    if not tab_ok then
        for _, id in ipairs(ACTION_IDS) do pcall(qa.unregister, id) end
        self.registered = false
        self.last_error = tab_detail
        return false, tab_detail
    end

    local popup_ok, popup_err = self:installProfileReadyApprovalPopup()
    if not popup_ok then
        logger.warn("DCPRO GhostGuard profile-ready popup unavailable:", popup_err)
    end

    self.last_error = nil
    logger.info("DCPRO GhostGuard registered SimpleUI Quick Actions and Tools tab")
    return true, "registered"
end

function SimpleUIBridge:openTrackedToolsWindow(opener)
    local qa = self.qa or self:resolveQA()
    local plugin = self:resolveSimpleUIPlugin()
    if qa and type(qa.trackIndicatorViaCallback) == "function" and self.tools_tab_id then
        return qa.trackIndicatorViaCallback(plugin, self.tools_tab_id, opener)
    end
    return opener(function() end)
end

function SimpleUIBridge:unregister()
    if self.qa and type(self.qa.unregister) == "function" then
        for _, id in ipairs(ACTION_IDS) do pcall(self.qa.unregister, id) end
    end
    -- The persistent custom QA/tab is intentionally retained across normal
    -- KOReader shutdown. It is refreshed on the next plugin startup.
    self.registered = false
    return true
end

function SimpleUIBridge:statusText()
    local qa_text = self.registered and "4 QUICK ACTIONS" or "QUICK ACTIONS CHƯA KẾT NỐI"
    local tab_text = self.tools_tab_ready and "TAB TOOLS ĐÃ GẮN CẠNH HOME"
        or ("TAB TOOLS CHƯA SẴN SÀNG" .. (self.tools_tab_detail and (" — " .. self.tools_tab_detail) or ""))
    local popup_text = self.profile_ready_popup_installed and " + PROFILE POPUP ĐÃ BẬT" or ""
    return qa_text .. " + " .. tab_text .. popup_text
end

return SimpleUIBridge
