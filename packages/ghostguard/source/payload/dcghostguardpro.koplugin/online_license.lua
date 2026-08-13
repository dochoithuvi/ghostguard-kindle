local OnlineLicense = {}
OnlineLicense.__index = OnlineLicense

local function trim(s) return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
local function feature_allowed(features)
    if type(features) == "table" then
        for _,v in ipairs(features) do
            v = tostring(v):lower()
            if v == "ghostguard" or v == "ultimate" then return true end
        end
        return false
    end
    local n = "," .. tostring(features or ""):lower():gsub("%s", "") .. ","
    return n:find(",ghostguard,",1,true) ~= nil or n:find(",ultimate,",1,true) ~= nil
end
local function valid_date(s)
    if not tostring(s):match("^%d%d%d%d%-%d%d%-%d%d$") then return false end
    local y,m,d=tonumber(s:sub(1,4)),tonumber(s:sub(6,7)),tonumber(s:sub(9,10))
    if not y or y<2020 or not m or m<1 or m>12 or not d or d<1 or d>31 then return false end
    local md={31,28,31,30,31,30,31,31,30,31,30,31}; if y%400==0 or (y%4==0 and y%100~=0) then md[2]=29 end
    return d<=md[m]
end
local function date_num(s) return tonumber((s or ""):gsub("-", "")) or 0 end
local function load_keyring(plugin_dir)
    local chunk,err=loadfile(plugin_dir.."keys/keyring.lua"); if not chunk then return nil,"KEYRING_LOAD_FAILED:"..tostring(err) end
    local ok,ring=pcall(chunk); if not ok or type(ring)~="table" then return nil,"KEYRING_INVALID" end
    return ring
end
local function decode_json(raw)
    local ok,JSON=pcall(require,"json"); if not ok then return nil,"JSON_MODULE_UNAVAILABLE" end
    local dok,obj=pcall(JSON.decode,raw); if not dok or type(obj)~="table" then return nil,"JSON_DECODE_FAILED" end
    return obj
end
local function https_get(url, block_timeout, total_timeout)
    local ok_https,https=pcall(require,"ssl.https"); local ok_ltn,ltn12=pcall(require,"ltn12"); local ok_su,socketutil=pcall(require,"socketutil")
    if not ok_https or not ok_ltn then return nil,"HTTPS_STACK_UNAVAILABLE" end
    local chunks={}; local sink
    if ok_su and socketutil then
        socketutil:set_timeout(block_timeout or 5,total_timeout or 12); sink=socketutil.table_sink(chunks)
    else sink=ltn12.sink.table(chunks) end
    local ok,a,b,c=pcall(https.request,{url=url,method="GET",headers={["User-Agent"]="DCPRO-GhostGuard/0.6"},sink=sink})
    if ok_su and socketutil then pcall(socketutil.reset_timeout,socketutil) end
    if not ok then return nil,"HTTPS_REQUEST_FAILED:"..tostring(a) end
    local code=tonumber(b) or tonumber(a)
    if code~=200 then return nil,"HTTP_STATUS_"..tostring(code or b or a) end
    return table.concat(chunks)
end

function OnlineLicense:new(config,storage,plugin_dir,device_id,crypto)
    return setmetatable({config=config,storage=storage,plugin_dir=plugin_dir,device_id=device_id,crypto=crypto,last_sync_detail="NOT_SYNCED",last_source="NONE"},self)
end
function OnlineLicense:verifyPair(reg_raw,sig_raw)
    if not self.crypto then return nil,"CRYPTO_UNAVAILABLE" end
    local sigobj,err=decode_json(sig_raw); if not sigobj then return nil,err end
    if tonumber(sigobj.signature_format)~=1 then return nil,"REGISTRY_SIG_FORMAT_UNSUPPORTED" end
    if tostring(sigobj.sig_alg):upper()~="RSA-SHA256" then return nil,"REGISTRY_SIG_ALG_UNSUPPORTED" end
    local ring,rerr=load_keyring(self.plugin_dir); if not ring then return nil,rerr end
    local key_id=trim(sigobj.key_id); local filename=ring[key_id]
    if type(filename)~="string" or not filename:match("^[A-Za-z0-9_.-]+%.pem$") then return nil,"REGISTRY_UNKNOWN_KEY_ID" end
    local ok,verified,verr=pcall(self.crypto.verify,self.plugin_dir.."keys/"..filename,reg_raw,trim(sigobj.sig))
    if not ok then return nil,"REGISTRY_CRYPTO_RUNTIME_FAILED:"..tostring(verified) end
    if not verified then return nil,verr or "REGISTRY_SIGNATURE_MISMATCH" end
    local reg,jerr=decode_json(reg_raw); if not reg then return nil,jerr end
    if tonumber(reg.registry_format)~=1 then return nil,"REGISTRY_FORMAT_UNSUPPORTED" end
    if tostring(reg.key_id)~=key_id then return nil,"REGISTRY_KEY_ID_MISMATCH" end
    if tostring(reg.sig_alg):upper()~="RSA-SHA256" then return nil,"REGISTRY_ALG_MISMATCH" end
    if type(reg.entries)~="table" then return nil,"REGISTRY_ENTRIES_INVALID" end
    return reg,key_id
end
function OnlineLicense:lookup(reg)
    local hash,herr=self.crypto.sha256Hex(tostring(self.device_id or "")); if not hash then return nil,"SERIAL_HASH_FAILED:"..tostring(herr) end
    for _,entry in ipairs(reg.entries or {}) do if tostring(entry.serial_hash):lower()==hash then return entry end end
    return false,"NOT_LISTED"
end
function OnlineLicense:evaluateEntry(entry)
    if entry==false or entry==nil then return nil,"ONLINE_NOT_LISTED" end
    local status=tostring(entry.status or "active"):lower()
    if status~="active" then return false,"ONLINE_"..status:upper() end
    if not feature_allowed(entry.features) then return false,"ONLINE_FEATURE_NOT_GRANTED" end
    local expire=tostring(entry.expire or ""):lower(); local today=os.date("%Y-%m-%d")
    if expire~="lifetime" then
        if not valid_date(expire) then return false,"ONLINE_EXPIRE_INVALID" end
        if valid_date(today) and date_num(today)>date_num(expire) then return false,"ONLINE_LICENSE_EXPIRED" end
    end
    return true,"ONLINE_ACTIVE;LICENSE_ID="..tostring(entry.license_id or "")..";EXPIRE="..expire
end
function OnlineLicense:cacheAgeSeconds()
    local raw=self.storage:readFile(self.config.online_license_sync_state) or ""
    local ts=tonumber(raw:match("SYNC_EPOCH=(%d+)")); if not ts then return math.huge end
    return math.max(0,os.time()-ts)
end
function OnlineLicense:readCache()
    local reg_raw=self.storage:readFile(self.config.online_license_cache_json); local sig_raw=self.storage:readFile(self.config.online_license_cache_sig)
    if not reg_raw or not sig_raw then return nil,"ONLINE_CACHE_MISSING" end
    local reg,detail=self:verifyPair(reg_raw,sig_raw); if not reg then return nil,detail end
    local entry=self:lookup(reg); return {registry=reg,entry=entry,age=self:cacheAgeSeconds()},"ONLINE_CACHE_VALID"
end
function OnlineLicense:sync()
    if not self.config.online_license_enabled then return false,"ONLINE_DISABLED" end
    local reg_raw,err=https_get(self.config.online_license_registry_url,self.config.online_license_connect_timeout,self.config.online_license_total_timeout); if not reg_raw then self.last_sync_detail=err; return false,err end
    local sig_raw,serr=https_get(self.config.online_license_signature_url,self.config.online_license_connect_timeout,self.config.online_license_total_timeout); if not sig_raw then self.last_sync_detail=serr; return false,serr end
    local reg,vdetail=self:verifyPair(reg_raw,sig_raw); if not reg then self.last_sync_detail=vdetail; return false,vdetail end
    local ok1=self.storage:writeAtomic(self.config.online_license_cache_json,reg_raw); local ok2=self.storage:writeAtomic(self.config.online_license_cache_sig,sig_raw)
    if not ok1 or not ok2 then self.last_sync_detail="ONLINE_CACHE_WRITE_FAILED"; return false,self.last_sync_detail end
    self.storage:writeAtomic(self.config.online_license_sync_state,"SYNC_EPOCH="..tostring(os.time()).."\nSYNC_UTC="..os.date("!%Y-%m-%dT%H:%M:%SZ").."\n")
    local entry=self:lookup(reg); local allowed,detail=self:evaluateEntry(entry)
    self.last_sync_detail="SYNC_OK;"..tostring(detail); self.last_source="NETWORK"
    return true,self.last_sync_detail,allowed,detail
end
return OnlineLicense
