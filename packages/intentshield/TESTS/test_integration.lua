local plugin_dir=assert(arg[1])
local calls={}; local ui={tasks={},top=nil}; local reader={document={},view={},menu={registerToMainMenu=function() end}}
reader.dialog=reader
function reader:handleEvent(e) calls[#calls+1]=e; self.page=(self.page or 20)+e.args[1]; return true end
function reader:getCurrentPage() return self.page or 20 end
function ui:getTopmostVisibleWidget() return self.top end
function ui:handleInputEvent(e) self.passed=(self.passed or 0)+1 end
local original=ui.handleInputEvent
function ui:scheduleIn(sec,fn) self.tasks[fn]=sec end
function ui:unschedule(fn) self.tasks[fn]=nil end
function ui:nextTick(fn) self:scheduleIn(0,fn) end
function ui:show(w) self.notice=w end
local input={}
function input:registerEventAdjustHook(fn) self.hook=fn end
local dev={model="KindleBasic4",input=input,screen={getRotationMode=function() return 0 end,getWidth=function() return 1072 end,getHeight=function() return 1448 end}}
local marker=false
local lfs={attributes=function(p,k) if p:find("ENABLE_INTENTSHIELD_GLOBAL",1,true) then return nil elseif p:find("DISABLE_INTENTGATE",1,true) then return marker and "file" or nil end return k=="mode" and "directory" or {} end,mkdir=function() end}
local function stub(name,value) package.loaded[name]=value end
stub("ui/widget/container/widgetcontainer",{extend=function(_,t) t.__index=t; return t end})
stub("ui/uimanager",ui);stub("device",dev);stub("ui/event",{new=function(_,name,arg) return {handler="on"..name,args={arg}} end})
stub("ui/widget/infomessage",{new=function(_,t)return t end});stub("ui/widget/confirmbox",{new=function(_,t)return t end});stub("libs/libkoreader-lfs",lfs);stub("logger",{info=function()end});stub("ui/bidi",{flipDirectionIfMirroredUILayout=function(d)return d end});stub("apps/reader/readerui",{instance=reader})
stub("ui/geometry",{new=function(_,t)return t end});stub("ui/time",{now=function()return 123 end}); function ui:sendEvent(e) calls[#calls+1]=e end
local open=io.open
local log={};io.open=function(path,mode) if path:find("/mnt/us/",1,true)==1 then return {write=function(_,s)log[#log+1]=s;return true end,flush=function()return true end,close=function()return true end} end return open(path,mode) end
local C=dofile(plugin_dir.."/main.lua");local p=setmetatable({ui=reader},C);p:init();ui.top=reader
local ts=1
local function ev(typ,code,value) input.hook(input,{type=typ,code=code,value=value,time={sec=math.floor(ts),usec=math.floor((ts-math.floor(ts))*1000000)}}) end
local function stroke(x,step)
    ev(3,47,0);ev(3,57,1);ev(3,53,x);ev(3,54,300);ev(0,0,0)
    for i=1,4 do ts=ts+0.05;ev(3,53,x+i*step);ev(0,0,0) end
    ts=ts+0.02;ev(3,57,-1);ev(0,0,0)
end
local function runTasks(delay) local list={} for f,v in pairs(ui.tasks) do if v==delay then list[#list+1]=f end end; for _,f in ipairs(list) do if ui.tasks[f]==delay then ui.tasks[f]=nil; f() end end end
local function nextTicks() runTasks(0) end
assert(p:start("SHADOW",180));stroke(450,-40);nextTicks();assert(#calls==0 and p.horizontal==1);ui:handleInputEvent({handler="onGesture"});assert(ui.passed==1);p:stop("test");assert(ui.handleInputEvent==original)
assert(p:start("SHIELD",60));ts=ts+1;stroke(450,0);nextTicks();assert(#calls==0);ui:handleInputEvent({handler="onGesture"});assert(p.suppressed==1 and ui.passed==1);ui:handleInputEvent("Power");assert(ui.passed==2)
ts=ts+1;stroke(450,-40);nextTicks();assert(#calls==1 and calls[1].args[1]==1);runTasks(0.25);assert(p.audit_changed==1);ts=ts+1;stroke(450,40);nextTicks();assert(#calls==2 and calls[2].args[1]==-1);runTasks(0.25);assert(p.audit_changed==2)
-- stop on suspend, no queued page may run
 ts=ts+1;stroke(450,-40);p:onSuspend();nextTicks();assert(#calls==2 and p.mode==nil and ui.handleInputEvent==original)
assert(p:start("SHIELD",60));local timer=p.timer;timer();assert(p.mode==nil and ui.handleInputEvent==original)
assert(p:start("SHIELD",60));marker=true;p.monitor();assert(p.mode==nil and ui.handleInputEvent==original);assert(not p:start("SHIELD",60));marker=false
assert(p:start("SHIELD",60));ui.top={};ui:handleInputEvent({handler="onGesture"});assert(p.mode==nil and ui.handleInputEvent==original);ui.top=reader
assert(p:start("SHIELD",60));ev(0,3,0);assert(p.mode==nil and ui.handleInputEvent==original)
assert(p:start("SHIELD",60));ts=ts+1;stroke(450,-40);p:stop("manual");nextTicks();assert(#calls==2)
print("PASS: mock integration shadow, gesture interception, page directions, power pass-through, timeout, suspend, USB disable, foreground loss, SYN_DROPPED, stale page request")

assert(p:start("SHIELD",900,false));assert(ui.tasks[p.timer]==900);p:stop("test")
assert(p:start("SHIELD",300,true));assert(p.gate.fast);p:stop("test")
assert(not p:start("SHIELD",901,false));print("PASS: page-location observation, 15-min deadline, optional fast mode, max duration")
-- 0.4 continuous mode does not change strict classifier or auto-start.
assert(p:start("SHIELD",0,false,false));assert(p.continuous and not p.timer and not p.auto_resume)
ts=ts+1;stroke(450,-40);nextTicks();assert(#calls==3);runTasks(0.25)
p:onSuspend();assert(not p.mode and not p.resume_plan);p:onResume();runTasks(5);assert(not p.mode)
assert(p:start("SHIELD",0,false,true));p:onSuspend();assert(not p.mode and p.resume_plan);p:onResume();assert(not p.mode and ui.tasks[p.resume_timer]==5);runTasks(5);assert(p.mode=="SHIELD" and p.continuous and p.auto_resume);p:stop("test")
assert(p:start("SHIELD",0,false,true));p:onSuspend();p:onResume();p:onSuspend();runTasks(5);assert(not p.mode and not p.resume_plan)
assert(p:start("SHIELD",0,false,true));p:onSuspend();p:onResume();marker=true;runTasks(5);assert(not p.mode);marker=false
assert(p:start("SHIELD",0,false,true));p:onSuspend();p:onResume();ui.top={};runTasks(5);assert(not p.mode);ui.top=reader
assert(p:start("SHIELD",0,false,true));p:onSuspend();p:onResume();p:onClose();runTasks(5);assert(not p.mode)
local function vertical(y,step)
    ev(3,47,0);ev(3,57,1);ev(3,53,450);ev(3,54,y);ev(0,0,0)
    for i=1,6 do ts=ts+0.05;ev(3,54,y+i*step);ev(0,0,0) end
    ts=ts+0.02;ev(3,57,-1);ev(0,0,0)
end
assert(p:start("SHIELD",0,false,false));ts=ts+1;vertical(900,-70);assert(p.mode and p.exit_stroke);ts=ts+1;vertical(480,70);assert(p.mode and p.unlock_pending);local passed=ui.passed;ui:handleInputEvent({handler="onGesture"});assert(ui.passed==passed);nextTicks();assert(not p.mode and ui.handleInputEvent==original and #calls==3)
assert(p:start("SHIELD",0,false,false));ts=ts+1;vertical(900,-70);ts=ts+9;vertical(480,70);nextTicks();assert(p.mode and not p.unlock_pending);p:stop("test")
assert(p:start("SHIELD",60,false));ts=ts+1;vertical(900,-70);ts=ts+1;vertical(480,70);nextTicks();assert(p.mode and not p.unlock_pending);p:stop("test")
assert(p:start("SHIELD",300,true));ts=ts+1;stroke(450,-40);nextTicks();runTasks(0.25);ts=ts+0.15;stroke(450,-40);nextTicks();runTasks(0.25);assert(#calls==5);p:stop("test")
print("PASS: continuous, default suspend-off, opt-in resume, second sleep cancels, USB marker, foreground refusal, close cancellation, two-stroke escape, expiry, timed-mode unchanged, fast rate-limit")
-- Global tests: separate raw hook, preserve existing Reader-only behavior.
local G=dev.input._dcpro_intentshield_global
reader.handleEvent=function(self,e) calls[#calls+1]=e; if e.handler=='onGotoViewRel' then self.page=(self.page or 20)+e.args[1] end; return true end
local home={}; local library={}; ui.top=home
assert(G:start(300,false)); assert(G.active and ui.tasks[G.timer]==300)
local base=#calls; local passed=ui.passed
ui:handleInputEvent({handler='onGesture'}); assert(G.blocked==1 and ui.passed==passed)
ui:handleInputEvent('Power'); assert(ui.passed==passed+1)
ts=ts+1; stroke(450,40); nextTicks(); assert(#calls==base+1 and calls[#calls].args[1].ges=='tap' and calls[#calls].args[1].pos.x==610)
ts=ts+1; stroke(450,0); nextTicks(); assert(#calls==base+1)
ts=ts+1; stroke(450,40); ui.top=library; nextTicks(); assert(#calls==base+1,'stale action must not cross context')
ts=ts+1; vertical(900,-70); nextTicks(); assert(calls[#calls].args[1].ges=='swipe' and calls[#calls].args[1].direction=='north')
ui.top=reader; ts=ts+1; stroke(450,-40); nextTicks(); assert(calls[#calls].handler=='onGotoViewRel' and calls[#calls].args[1]==1)
ts=ts+1; vertical(900,-70); nextTicks(); assert(calls[#calls].handler=='onShowMenu')
ev(0,3,0); assert(G.active and not G.gate.blocked); G:stop('test'); assert(ui.handleInputEvent==original)
assert(G:start(0,true)); G:suspend(); assert(not G.active and G.resume); G:onResume(); runTasks(5); assert(G.active); G:stop('test')
assert(G:start(0,false)); marker=true; G.monitor(); assert(not G.active and ui.handleInputEvent==original); marker=false
assert(G:start(300,false)); local n=#calls; ts=ts+1; stroke(450,-40); G:stop('test'); nextTicks(); assert(#calls==n)
assert(G:start(300,false)); G.timer(); assert(not G.active)
print('PASS: global tap suppression, selection endpoint, stale context discard, vertical scroll, reader page/menu, desync reset, resume, USB stop, queued cancellation, timeout')
local function edgeVertical(y,step)
    ev(3,47,0);ev(3,57,1);ev(3,53,120);ev(3,54,y);ev(0,0,0)
    for i=1,6 do ts=ts+0.05;ev(3,54,y+i*step);ev(0,0,0) end
    ts=ts+0.02;ev(3,57,-1);ev(0,0,0)
end
assert(G:start(0,true)); local n=#calls; ts=ts+1;edgeVertical(900,-70);assert(G.exit);ts=ts+1;edgeVertical(480,70);nextTicks();assert(not G.active and G.manual_off and #calls==n)
assert(G:start(0,true)); G:suspend();G:onResume();G:suspend();runTasks(5);assert(not G.active)
print('PASS: global two-stroke left-edge escape, second suspend cancels resume')
