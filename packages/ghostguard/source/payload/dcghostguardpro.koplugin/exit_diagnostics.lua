local UIManager = require("ui/uimanager")

local ExitDiagnostics = {}
ExitDiagnostics.__index = ExitDiagnostics

local unpack_fn = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function safe_tostring(value)
    local ok, result = pcall(tostring, value)
    return ok and result or "<tostring failed>"
end

local function summarize_args(args)
    local values = {}
    for i = 1, math.min(args.n or 0, 6) do
        values[#values + 1] = safe_tostring(args[i])
    end
    if (args.n or 0) > 6 then values[#values + 1] = "..." end
    return table.concat(values, " | ")
end

function ExitDiagnostics:new(config, storage)
    return setmetatable({
        config = config,
        storage = storage,
        installed = false,
        last_priority = 0,
        last_wall = 0,
    }, self)
end

function ExitDiagnostics:appendHistory(text)
    local path = self.config.exit_history_file
    if not path then return end
    local old = self.storage:readFile(path) or ""
    local combined = old .. text
    local max_bytes = 131072
    if #combined > max_bytes then combined = combined:sub(#combined - max_bytes + 1) end
    self.storage:writeAtomic(path, combined)
end

local function reason_priority(reason)
    local priorities = {
        UIMANAGER_QUIT = 100,
        UIMANAGER_RESTART = 100,
        UIMANAGER_REBOOT = 100,
        UIMANAGER_POWEROFF = 100,
        OS_EXIT = 100,
        POWER_OFF = 90,
        REBOOT = 90,
        PLUGIN_STOP = 80,
        ON_CLOSE_WIDGET = 10,
    }
    return priorities[reason] or 50
end

function ExitDiagnostics:record(reason, detail, traceback_text, state)
    reason = safe_tostring(reason or "UNKNOWN")
    detail = safe_tostring(detail or "NONE")
    traceback_text = safe_tostring(traceback_text or debug.traceback("GhostGuard exit diagnostic", 2))
    state = state or {}
    local now = os.time()
    local priority = reason_priority(reason)

    local lines = {
        "DCPRO_GHOSTGUARD_EXIT_REASON_V2",
        "UTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "EXIT_REASON=" .. reason,
        "EXIT_REASON_DETAIL=" .. detail,
        "CAPTURE_PRIORITY=" .. tostring(priority),
        "ENGINE_RUNNING=" .. safe_tostring(state.running),
        "ENGINE_MODE=" .. safe_tostring(state.mode),
        "PROTECT_ENABLED=" .. safe_tostring(state.protect_enabled),
        "PROTECT_WRAPPER=" .. safe_tostring(state.protect_wrapper),
        "START_REASON=" .. safe_tostring(state.start_reason),
        "LAST_ERROR=" .. safe_tostring(state.last_error),
        "TRACEBACK_FILE=" .. safe_tostring(self.config.koreader_traceback_file),
        "",
    }
    local detail_text = table.concat(lines, "\n")
    pcall(self.appendHistory, self, detail_text .. "\n")

    -- onCloseWidget often runs as part of the normal quit teardown. Never let
    -- that low-information callback overwrite a stronger UIManager/os.exit
    -- capture recorded moments earlier.
    if now - (self.last_wall or 0) <= 30 and priority < (self.last_priority or 0) then
        return true, "history-only-lower-priority"
    end

    self.last_priority = priority
    self.last_wall = now
    pcall(self.storage.writeAtomic, self.storage, self.config.exit_reason_detail_file, detail_text)
    pcall(self.storage.writeAtomic, self.storage, self.config.koreader_traceback_file,
        "DCPRO_GHOSTGUARD_KOREADER_TRACEBACK_V2\nUTC=" .. os.date("!%Y-%m-%dT%H:%M:%SZ")
        .. "\nEXIT_REASON=" .. reason .. "\nEXIT_REASON_DETAIL=" .. detail .. "\n\n" .. traceback_text .. "\n")
    return true
end

function ExitDiagnostics:install(owner)
    local bridge = UIManager._dcpro_ghostguard_exit_diagnostics
    if not bridge then
        bridge = { owner = nil, originals = {}, wrappers = {} }
        UIManager._dcpro_ghostguard_exit_diagnostics = bridge
    end
    bridge.owner = owner

    local function install_method(name, reason)
        local current = UIManager[name]
        if type(current) ~= "function" or bridge.originals[name] then return false end
        bridge.originals[name] = current
        bridge.wrappers[name] = function(...)
            local args = pack(...)
            local active = UIManager._dcpro_ghostguard_exit_diagnostics
            local plugin = active and active.owner
            if plugin and type(plugin.recordExitReason) == "function" then
                pcall(plugin.recordExitReason, plugin, reason,
                    "UIManager." .. name .. " called; args=" .. summarize_args(args),
                    debug.traceback("KOReader termination call: UIManager." .. name, 2))
            end
            return current(unpack_fn(args, 1, args.n))
        end
        UIManager[name] = bridge.wrappers[name]
        return true
    end

    -- Only termination-related methods are wrapped. UIManager.close is not
    -- wrapped because closing ordinary dialogs is normal KOReader behaviour.
    install_method("quit", "UIMANAGER_QUIT")
    install_method("restart", "UIMANAGER_RESTART")
    install_method("reboot", "UIMANAGER_REBOOT")
    install_method("powerOff", "UIMANAGER_POWEROFF")

    local os_bridge = rawget(os, "_dcpro_ghostguard_exit_diagnostics")
    if not os_bridge and type(os.exit) == "function" then
        os_bridge = { original = os.exit, owner = owner }
        os._dcpro_ghostguard_exit_diagnostics = os_bridge
        os.exit = function(...)
            local args = pack(...)
            local active = rawget(os, "_dcpro_ghostguard_exit_diagnostics")
            local plugin = active and active.owner
            if plugin and type(plugin.recordExitReason) == "function" then
                pcall(plugin.recordExitReason, plugin, "OS_EXIT",
                    "os.exit called; args=" .. summarize_args(args),
                    debug.traceback("KOReader termination call: os.exit", 2))
            end
            return active.original(unpack_fn(args, 1, args.n))
        end
    elseif os_bridge then
        os_bridge.owner = owner
    end

    self.installed = true
    return true
end

return ExitDiagnostics
