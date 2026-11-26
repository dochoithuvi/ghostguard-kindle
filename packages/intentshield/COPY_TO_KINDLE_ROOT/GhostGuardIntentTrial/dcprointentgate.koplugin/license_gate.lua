-- Standalone license adapter: original RSA v4 and signed registry policy.
local root=debug.getinfo(1,"S").source:sub(2):match("(.*/)")
local M={}
local manager
local function get()
    if manager then return manager end
    local f=io.open("/proc/usid","rb")
    if not f then error("SERIAL_UNAVAILABLE") end
    local serial=(f:read("*a") or ""):upper():gsub("[^A-Z0-9]","")
    f:close()
    if serial=="" then error("SERIAL_UNAVAILABLE") end
    local config=dofile(root.."license_config.lua")
    local storage=dofile(root.."license_storage.lua"):new(config)
    manager=dofile(root.."license_manager.lua"):new(config,storage,root,serial)
    return manager
end
function M.check(force)
    local ok,a,b=pcall(function() return get():check(force==true) end)
    if not ok then return false,"LICENSE_CHECK_ERROR: "..tostring(a) end
    return a==true,b
end
function M.sync()
    local ok,a,b,c,d=pcall(function() return get():syncOnline() end)
    if not ok then return false,tostring(a) end
    return a,b,c,d
end
return M
