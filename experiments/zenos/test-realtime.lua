-- Synthetic unit and event-stream tests; no Kindle access.
local O = dofile("packages/ghostguard/source/payload/dcghostguardpro.koplugin/touch_observer.lua")
local defaults = dofile("packages/ghostguard/source/payload/dcghostguardpro.koplugin/defaults.lua")
local session = setmetatable({}, {__index=function() return function() end end})
local function new(strip, match)
    local c = {}
    for k,v in pairs(defaults) do c[k]=v end
    c.zen_realtime_strip = strip
    c.zen_preserve_gestures = true
    return O:new(session,c,{protect_enabled=true,screen_width=1072,
        profile_manager={match=function() return match end}})
end
local function sample(i, opts)
    local t={timestamp_us=1000000+i*100000,frame=i,slot=0,x=450,y=100+i*90,
        duration_us=40000,touch_major=10,path_px=0,low_major=true,short=true,
        still=true,incomplete=false,extreme_edge=false,base_score=5,reason="test"}
    for k,v in pairs(opts or {}) do t[k]=v end
    return t
end
local a=new(true)
for i=1,4 do assert(not a:evaluateProtect(sample(i)),"early strip decision") end
assert(a:evaluateProtect(sample(5)).reason:find("ZEN_REALTIME_STRIP",1,true))
a:setProtectEnabled(false); a:setProtectEnabled(true)
assert(#a.zen_strip_history==0)
for i=1,4 do assert(not a:evaluateProtect(sample(i))) end
assert(not a:evaluateProtect(sample(5,{timestamp_us=5000000})),"expired history")
local b=new(false)
for i=1,8 do assert(not b:evaluateProtect(sample(i))) end
local c=new(true)
for i=1,8 do assert(not c:evaluateProtect(sample(i,{x=450,y=300})),"same point not strip") end
local d=new(true,{confidence=1,index=1,count=10})
assert(not d:evaluateProtect(sample(1,{overlapped=true})))
assert(not d:evaluateProtect(sample(2,{duration_us=250000})))
assert(not d:evaluateProtect(sample(3,{still=false,path_px=200})))
local e=new(true)
for i=1,4 do assert(not e:evaluateProtect(sample(i))) end
assert(not e:evaluateProtect(sample(5,{low_major=false,touch_major=100,base_score=3})))
assert(not e:evaluateProtect(sample(1)),"clock rollback")
local f=new(true,{confidence=1,index=1,count=10})
local ts=10
local function ev(typ,code,value)
    ts=ts+0.001
    return f:observe({type=typ,code=code,value=value,time=ts})
end
local function begin(slot,x,y)
    ev(3,47,slot); ev(3,57,slot+1); ev(3,53,x); ev(3,54,y); ev(3,48,10)
end
begin(0,450,200); begin(1,700,500); ev(0,0,0)
assert(f.slots[0].overlapped and f.slots[1].overlapped)
ev(3,47,0); ev(3,57,-1); assert(not ev(0,0,0),"overlap first release")
ev(3,47,1); ev(3,57,-1); assert(not ev(0,0,0),"overlap second release")
print("ZenOS synthetic tests passed")
