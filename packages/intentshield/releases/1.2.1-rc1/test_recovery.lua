local path=assert(arg[1]); local Device={model='KindleBasic4',input={},screen={getWidth=function()return 1072 end,getHeight=function()return 1448 end,getRotationMode=function()return 0 end}};local top={};local now=0
local stubs={['ui/uimanager']={getTopmostVisibleWidget=function()return top end},device=Device,['ui/event']={},['ui/geometry']={},['ui/time']={now=function()return now end,to_ms=function(v)return v end},['ui/bidi']={},['libs/libkoreader-lfs']={attributes=function()return nil end}}
for k,v in pairs(stubs) do package.preload[k]=function()return v end end
local old=dofile; dofile=function(f) if f:match('license_gate.lua$') then return {} end return old(f) end
local S=dofile(path..'/global_shield.lua');local Gate=dofile(path..'/intent_gate.lua');local count=0;local logs={}; S.log=function(_,x) logs[#logs+1]=x end
S.dispatch=function(_,v) assert(v.compatible);count=count+1 end
local function init()
  S.active=true; S.gate=Gate.new(1072,1448,false); S.top=top; S.pending=nil; S.inhibit_drain=false; S.context_drain=false; S.log_failed=false; S.exiting=false; S.recovering=false; S.recovery_slot=0; S.recovery_ids={};S.recovery_known=false;S.frame_up=false;S.frame_down=false;S.frame_release=false;S.recovery_probe=nil;S.raw=0;S.contacts=0;S.reject_run=0;S.desync_logged=false; count=0; Device.input._abs_ev_handler=nil; now=0;logs={}
  S.snapshot=function()return {slot=0,ids={}},'ok' end
end
local t=1000
local function e(a,b,c,dt) t=t+(dt or 0.001);now=now+((dt or 0.001)*1000); S:rawEvent{type=a,code=b,value=c,time=t} end
local function f() e(0,0,0) end
local function stroke(with_up,slot)
 e(3,47,slot or 0);e(3,57,100);e(3,53,100);e(3,54,300);f()
 for i=1,6 do e(3,53,100+i*35,0.04);e(3,54,300);f() end
 if with_up then e(1,330,0) end;e(3,57,-1);f()
end
init();stroke(true);assert(count==1 and not S.recovering,'BTN_TOUCH up must not suppress clean swipe')
init();e(3,47,1);e(3,57,77);e(3,53,50);e(3,54,50);f();stroke(true);assert(count==0,'overlap must remain rejected')
-- If BTN_TOUCH all-up disagrees with live kernel contact, do not recover.
init(); S.snapshot=function()return {slot=0,ids={[1]=22}},'ok' end;e(3,47,1);e(3,57,77);f();stroke(true);assert(S.recovering and count==0);assert(S.gate.slots[1].c~=nil)
-- Explicit up and verified kernel idle can recover stale state; recovery frame is never dispatched.
init();e(3,47,1);e(3,57,77);f();stroke(true);assert(not S.recovering and count==0 and not next(S.gate.slots));stroke(true);assert(count==1)
-- Unknown state / SYN_DROPPED: require explicit all-up with slot evidence.
init();e(0,3,0);stroke(false);assert(S.recovering and count==0);stroke(true);assert(not S.recovering and count==0);stroke(true);assert(count==1)
-- Startup active slot must be drained; missing BTN_TOUCH allowed only if all known slots released.
init();S:beginRecovery({slot=0,ids={[0]=19}});e(3,47,0);e(3,57,-1);f();assert(not S.recovering and count==0);stroke(true);assert(count==1)
init();S:beginRecovery({slot=0,ids={[0]=19,[1]=20}});e(3,47,0);e(3,57,-1);f();assert(S.recovering and count==0)
-- Query failure / slot mismatch / down in same frame must refuse recovery.
init();S:beginRecovery(nil);S.snapshot=function()return nil,'unavailable' end;stroke(true);assert(S.recovering and count==0)
init();S:beginRecovery(nil);S.snapshot=function()return {slot=1,ids={}},'ok' end;stroke(true);assert(S.recovering and count==0)
init();S:beginRecovery(nil);e(3,47,0);e(1,330,0);e(3,57,33);f();assert(S.recovering and count==0)
-- Inhibited contact cannot dispatch through restore frame; next clean swipe can.
init();Device.input._abs_ev_handler=true;e(3,47,0);e(3,57,9);e(3,53,100);e(3,54,300);f();Device.input._abs_ev_handler=nil
for i=1,6 do e(3,53,100+i*35,0.04);e(3,54,300);f() end;e(3,57,-1);f();assert(count==0 and not S.inhibit_drain);stroke(true);assert(count==1)
print('PASS: 11 recovery / isolation / inhibition regressions (mocked input, no hardware ioctl test)')
