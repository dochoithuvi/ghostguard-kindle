-- IntentShield 1.0 global action gate. No evdev injection/grab.
local UI = require('ui/uimanager')
local Device = require('device')
local Event = require('ui/event')
local Geom = require('ui/geometry')
local Time = require('ui/time')
local BD = require('ui/bidi')
local lfs = require('libs/libkoreader-lfs')
local root=debug.getinfo(1,'S').source:sub(2):match('(.*/)')
local Gate=dofile(root..'intent_gate.lua')
local License=dofile(root..'license_gate.lua')
local S={gen=0,active=false,license=License}
local DIS='/mnt/us/DISABLE_INTENTGATE'
local AUTO='/mnt/us/ENABLE_INTENTSHIELD_GLOBAL'
local REPORT='/mnt/us/GhostGuard_Reports/IntentGate'
local function exists(p) return lfs.attributes(p)~=nil end
local function screenOK()
    local s=Device.screen
    return Device.model=='KindleBasic4' and s and s:getRotationMode()==0 and s:getWidth()==1072 and s:getHeight()==1448
end
local function ts(e)
    local t=e.time
    if type(t)=='number' then return t>1e12 and math.floor(t) or math.floor(t*1e6) end
    if t then local a,b=tonumber(t.sec or t.tv_sec),tonumber(t.usec or t.tv_usec); if a and b then return a*1e6+b end end
end
function S:log(line)
    if self.file then local ok,v=pcall(self.file.write,self.file,line..'\n'); if not ok or not v then self.log_failed=true end end
end
function S:stop(reason,keep_resume)
    self.gen=self.gen+1; self.active=false; self.pending=nil; self.gate=nil; self.top=nil; self.exit=nil
    if not keep_resume then self.resume=false end
    if self.timer then UI:unschedule(self.timer); self.timer=nil end
    if self.monitor then UI:unschedule(self.monitor); self.monitor=nil end
    if self.wake then UI:unschedule(self.wake); self.wake=nil end
    if self.wrapper and UI.handleInputEvent==self.wrapper then UI.handleInputEvent=self.original end
    self.wrapper=nil; self.original=nil
    if self.file then self:log('END,'..tostring(reason)..',raw='..self.raw..',contacts='..self.contacts..',blocked_gestures='..self.blocked..',actions='..self.actions); pcall(self.file.flush,self.file); pcall(self.file.close,self.file); self.file=nil end
end
function S:context()
    local top=UI:getTopmostVisibleWidget()
    if not top then return nil,nil end
    local r=package.loaded['apps/reader/readerui']; r=r and r.instance
    if r and r.document and top==(r.dialog or r) then return top,r end
    return top,nil
end
function S:dispatch(v,top,reader,kind)
    if self.pending or not self.active then return end
    if self.last and v.ts-self.last<500000 then self:log('SKIP,rate_limit'); return end
    local token={}; self.pending=token; local gen=self.gen
    UI:nextTick(function()
        if self.gen~=gen or self.pending~=token or not self.active then return end
        self.pending=nil
        local ok,err=pcall(function()
            local now,r=self:context()
            if exists(DIS) or not screenOK() or now~=top or r~=reader then self:log('SKIP,context_changed'); return end
            self.last=v.ts; self.actions=self.actions+1
            self:log('ACTION,'..kind..','..v.ts..','..tostring(v.x1)..','..tostring(v.y1))
            if kind=='PAGE' then
                local d=BD.flipDirectionIfMirroredUILayout(v.dx<0 and 'west' or 'east')=='west' and 1 or -1
                if reader.view and reader.view.inverse_reading_order then d=-d end
                reader:handleEvent(Event:new('GotoViewRel',d))
            elseif kind=='MENU' then reader:handleEvent(Event:new('ShowMenu'))
            elseif kind=='SELECT' then
                -- End of an intentional horizontal stroke, not a physical tap.
                UI:sendEvent(Event:new('Gesture',{ges='tap',pos=Geom:new{x=v.x1,y=v.y1,w=0,h=0},time=Time.now()}))
            elseif kind=='SCROLL' then
                UI:sendEvent(Event:new('Gesture',{ges='swipe',pos=Geom:new{x=v.x0,y=v.y0,w=0,h=0},end_pos=Geom:new{x=v.x1,y=v.y1,w=0,h=0},direction=v.dy<0 and 'north' or 'south',distance=math.abs(v.dy),time=Time.now()}))
            end
        end)
        if not ok then self:log('FAULT,dispatch,'..tostring(err):gsub('[\r\n]',' ')); self:stop('dispatch_fault') end
    end)
end
function S:rawEvent(e)
    if not self.active or self.exiting then return end
    if self.log_failed then self:stop('guard_stop'); return end
    local top,r=self:context()
    if top~=self.top then self.gate=Gate.new(1072,1448,false); self.pending=nil; self.exit=nil; self.top=top end
    if not top then return end
    local a,b,c=tonumber(e.type),tonumber(e.code),tonumber(e.value)
    if not ((a==0 and (b==0 or b==3)) or (a==3 and (b==47 or b==53 or b==54 or b==57))) then return end
    local t=ts(e); if not t or not c then self:stop('bad_raw'); return end
    self.raw=self.raw+1
    local out=self.gate:feed(t,a,b,c)
    if self.gate.blocked then
        -- Remain shielded on desync, clear pending actions and require fresh contacts.
        self.pending=nil; self.exit=nil; self.gate=Gate.new(1072,1448,false); self:log('DESYNC,reset_gate'); return
    end
    for _,v in ipairs(out) do
        self.contacts=self.contacts+1
        if self.contacts<=5000 then self:log(string.format('CONTACT,%d,%s,%d,%d,%.1f,%.1f',v.ts,v.reason,v.duration,v.points,v.dx,v.dy)) end
        if v.compatible and v.x0 and v.y0 and v.x1 and v.y1 then
            local h=math.abs(v.dx)>=2*math.abs(v.dy)
            local vert=math.abs(v.dy)>=3*math.abs(v.dx)
            -- Escape requires two long opposing strokes in leftmost 25% of screen.
            if vert and math.abs(v.dy)>=350 and v.x0<=268 and v.x1<=268 then
                local sign=v.dy>0 and 1 or -1
                if self.exit and self.exit.sign~=sign and v.ts>self.exit.ts and v.ts-self.exit.ts<=8000000 then
                    self.pending=nil; self.exiting=true; local gen=self.gen
                    UI:nextTick(function() if self.gen==gen then self:stop('escape'); self.exiting=false; self.manual_off=true end end); return
                end
                self.exit={sign=sign,ts=v.ts}; self:log('ESCAPE_ARM'); return
            end
            self.exit=nil
            if h then self:dispatch(v,top,r,r and 'PAGE' or 'SELECT')
            elseif vert and r and math.abs(v.dy)>=300 then self:dispatch(v,top,r,'MENU')
            elseif vert and not r then self:dispatch(v,top,nil,'SCROLL') end
        end
    end
end
function S:start(seconds,auto_resume)
    if self.active then return true end
    local licensed,why=License.check(true)
    if not licensed then return false,'License: '..tostring(why) end
    if exists(DIS) or not screenOK() then return false,'disabled or incompatible device' end
    if not Device.input or type(Device.input.registerEventAdjustHook)~='function' or type(UI.handleInputEvent)~='function' or type(UI.sendEvent)~='function' or type(Time.now)~='function' then return false,'incompatible KOReader APIs' end
    local old=Device.input._dcpro_intentgate_trial
    if old and old.owner then old.owner:stop('global_start') end
    lfs.mkdir('/mnt/us/GhostGuard_Reports'); lfs.mkdir(REPORT)
    local f=io.open(REPORT..'/'..os.date('%Y%m%d_%H%M%S')..'_GLOBAL.log','a'); if not f then return false,'log unavailable' end
    self.file=f; self.log_failed=false; self.gen=self.gen+1; self.active=true; self.manual_off=false; self.exiting=false; self.resume=false; self.auto_resume=auto_resume==true; self.seconds=seconds; self.raw=0; self.contacts=0; self.blocked=0; self.actions=0; self.last=nil; self.gate=Gate.new(1072,1448,false); self.top=nil; self.pending=nil
    self:log('START,IntentShield1.0,GLOBAL,duration='..tostring(seconds)..',auto_resume='..tostring(self.auto_resume))
    if not self.installed then
        Device.input:registerEventAdjustHook(function(_,ev)
            if S.active then local ok,err=pcall(S.rawEvent,S,ev); if not ok then S:log('FAULT,raw,'..tostring(err)); S:stop('raw_fault') end end
        end); self.installed=true
    end
    self.original=UI.handleInputEvent; local original=self.original
    self.wrapper=function(m,e)
        if S.active and type(e)=='table' and e.handler=='onGesture' then S.blocked=S.blocked+1; return end
        return original(m,e)
    end
    UI.handleInputEvent=self.wrapper
    local gen=self.gen
    self.monitor=function()
        if not self.active or gen~=self.gen then return end
        if exists(DIS) or not screenOK() or UI.handleInputEvent~=self.wrapper or self.log_failed then self:stop('monitor_stop'); self.manual_off=true; return end
        if not License.check(false) then self:stop('license_invalid'); self.manual_off=true; return end
        if self.file then local ok,v=pcall(self.file.flush,self.file); if not ok or not v then self:stop('flush_failed'); return end end
        UI:scheduleIn(2,self.monitor)
    end
    UI:scheduleIn(2,self.monitor)
    if seconds>0 then self.timer=function() if gen==self.gen then self:stop('timeout'); self.manual_off=true end end; UI:scheduleIn(seconds,self.timer) end
    return true
end
function S:suspend()
    if self.active then self.resume=self.auto_resume and self.seconds==0; self:stop('suspend',true)
    elseif self.wake then self:stop('second_suspend') end
end
function S:onResume()
    if self.resume and not self.wake then
        self.resume=false; local gen=self.gen
        self.wake=function() self.wake=nil; if self.gen==gen and not exists(DIS) then self:start(0,true) end end
        UI:scheduleIn(5,self.wake)
    end
end
function S:maybeAuto()
    if self.auto_checked then return end
    self.auto_checked=true
    if exists(AUTO) and not exists(DIS) then
        UI:scheduleIn(1,function() if not self.manual_off and not self.active and not exists(DIS) then local ok,err=pcall(self.start,self,0,true); if not ok then self:stop('autostart_fault') end end end)
    end
end
return S
