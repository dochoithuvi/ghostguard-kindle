-- Test the production license manager and crypto using an ephemeral CI-only key.
local root=assert(arg[1]).."/"
local sample=assert(arg[2]).."/"
local cfg=dofile(root.."license_config.lua")
cfg.data_dir=sample
cfg.online_license_enabled=false
local Storage={}
function Storage:readFile(path) local f=io.open(path,"rb"); if not f then return nil end; local s=f:read("*a"); f:close(); return s end
function Storage:fileExists(path) return self:readFile(path)~=nil end
function Storage:writeAtomic(path,s) local f=assert(io.open(path,"wb")); f:write(s); f:close(); return true end
local lm=dofile(root.."license_manager.lua"):new(cfg,Storage,sample,"TESTDEVICE")
lm.online=nil
local ok,why=lm:check(true); assert(ok,tostring(why))
local original=Storage:readFile(sample.."license.key")
Storage:writeAtomic(sample.."license.key",original:gsub("customer=CI","customer=TAMPERED"))
ok,why=lm:check(true); assert(not ok and tostring(why):find("SIGNATURE",1,true),tostring(why))
Storage:writeAtomic(sample.."license.key",original)
lm.device_id="WRONGDEVICE"; ok,why=lm:check(true); assert(not ok and tostring(why):find("SERIAL_MISMATCH",1,true),tostring(why))
lm.device_id="TESTDEVICE"; lm.online={readCache=function() return {entry={},age=0} end,evaluateEntry=function() return false,"REVOKED" end}
ok,why=lm:check(true); assert(not ok and tostring(why):find("REVOKED",1,true),tostring(why))
print("PASS: real RSA signature; tamper, serial mismatch and signed-cache policy denial")
