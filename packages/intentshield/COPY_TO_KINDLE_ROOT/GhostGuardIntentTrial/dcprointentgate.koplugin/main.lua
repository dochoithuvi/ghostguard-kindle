-- DCPRO IntentShield 1.0 -- Reader and Global Shield.
-- No input grabbing, firmware edits, license changes, or evdev injection.
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local BD = require("ui/bidi")
local root = debug.getinfo(1,"S").source:sub(2):match("(.*/)")
local Gate = dofile(root.."intent_gate.lua")
local License = dofile(root.."license_gate.lua")
local Plugin = WidgetContainer:extend{name="dcprointentgate",is_doc_only=false}
local Global=Device.input and Device.input._dcpro_intentshield_global
if not Global then Global=dofile(root.."global_shield.lua"); if Device.input then Device.input._dcpro_intentshield_global=Global end end
local REPORT = "/mnt/us/GhostGuard_Reports/IntentGate"
local DISABLE = "/mnt/us/DISABLE_INTENTGATE"
local shared = Device.input and Device.input._dcpro_intentgate_trial
if not shared then
    shared = {owner=nil,installed=false,input=nil}
    if Device.input then Device.input._dcpro_intentgate_trial=shared end
end
local function notice(text,seconds)
    UIManager:show(InfoMessage:new{text=text,timeout=seconds or 3})
end
local function exists(path)
    return lfs.attributes(path) ~= nil
end
local function timestamp(ev)
    local t=ev.time
    if type(t)=="number" then
        return t>1000000000000 and math.floor(t) or math.floor(t*1000000)
    end
    if t==nil then return nil end
    local sec=tonumber(t.sec or t.tv_sec)
    local usec=tonumber(t.usec or t.tv_usec)
    if not sec or not usec then return nil end
    return sec*1000000+usec
end
function Plugin:foreground()
    local r=package.loaded["apps/reader/readerui"]
    return r and r.instance==self.ui and self.ui.document~=nil and
        UIManager:getTopmostVisibleWidget()==(self.ui.dialog or self.ui)
end
function Plugin:log(text)
    if self.report then
        local ok, result=pcall(self.report.write,self.report,tostring(text).."\n")
        if not ok or not result then self.log_error=true end
    end
end
function Plugin:stop(reason)
    -- Idempotent. Stop before showing any dialog; physical power events pass through.
    local was=self.mode
    self.mode=nil; self.gate=nil; self.pending=nil; self.armed=false
    self.continuous=false; self.auto_resume=false; self.resume_plan=nil; self.exit_stroke=nil; self.unlock_pending=false
    if self.resume_timer then UIManager:unschedule(self.resume_timer); self.resume_timer=nil end
    if self.audit_timer then UIManager:unschedule(self.audit_timer); self.audit_timer=nil; self.audit_unknown=(self.audit_unknown or 0)+1 end
    self.generation=(self.generation or 0)+1
    if shared.owner==self then shared.owner=nil end
    if self.timer then UIManager:unschedule(self.timer); self.timer=nil end
    if self.monitor then UIManager:unschedule(self.monitor); self.monitor=nil end
    if self.start_timer then UIManager:unschedule(self.start_timer); self.start_timer=nil end
    if self.wrapper and UIManager.handleInputEvent==self.wrapper then
        UIManager.handleInputEvent=self.original
    end
    self.wrapper=nil; self.original=nil
    if self.report then
        self:log(string.format("END,%s,raw_events=%d,completed=%d,compatible=%d,horizontal=%d,gesture_suppressed=%d,page_requests=%d,page_changed=%d,page_unchanged=%d,page_unknown=%d,fast_accepted=%d,log_error=%s",reason or "manual",self.raw_events or 0,self.completed or 0,self.compatible or 0,self.horizontal or 0,self.suppressed or 0,self.page_requests or 0,self.audit_changed or 0,self.audit_unchanged or 0,self.audit_unknown or 0,self.fast_accepted or 0,tostring(self.log_error==true)))
        pcall(self.report.flush,self.report); pcall(self.report.close,self.report); self.report=nil
    end
    if was then logger.info("IntentGate stopped",reason) end
end
function Plugin:fail(reason)
    self:log("FAULT,"..tostring(reason):gsub("[\r\n,]"," "):sub(1,240))
    self:stop("fault_fail_open")
end
-- Read the location without modifying document settings. Page number can stay
-- unchanged in scroll mode; report observed change, not verified page success.
function Plugin:location()
    local u=self.ui
    if u.rolling and u.view and u.view.view_mode=="scroll" then
        local pos=u.rolling.current_pos
        if type(pos)=="number" then return "pos:"..tostring(pos) end
    end
    if type(u.getCurrentPage)=="function" then
        local ok,page=pcall(u.getCurrentPage,u)
        if ok and type(page)=="number" then return "page:"..tostring(page) end
    end
    return nil
end
function Plugin:queuePage(v)
    if self.pending or self.unlock_pending or not self.mode or self.mode~="SHIELD" then return end
    local gap=self.gate.fast and 350000 or 500000
    if self.audit_timer or (self.last_page_ts and v.ts-self.last_page_ts<gap) then self:log("SKIP,rate_limit"); return end
    local direction=v.dx<0 and "west" or "east"
    direction=BD.flipDirectionIfMirroredUILayout(direction)
    local diff=direction=="west" and 1 or -1
    if self.ui.view and self.ui.view.inverse_reading_order then diff=-diff end
    local token={diff=diff,ts=v.ts}
    self.pending=token
    local generation=self.generation
    UIManager:nextTick(function()
        if self.generation~=generation or self.pending~=token then return end
        self.pending=nil
        if self.mode~="SHIELD" then return end
        local ok,err=pcall(function()
            if not self:foreground() or exists(DISABLE) then self:stop("foreground_or_usb_stop"); return end
            self.last_page_ts=token.ts
            self.page_requests=self.page_requests+1
            local before=self:location()
            self:log("PAGE_REQUEST,"..token.diff..","..tostring(before or "unknown"))
            self.ui:handleEvent(Event:new("GotoViewRel",token.diff))
            if self.generation~=generation or self.mode~="SHIELD" then return end
            if self.audit_timer then UIManager:unschedule(self.audit_timer); self.audit_unknown=self.audit_unknown+1 end
            self.audit_timer=function()
                self.audit_timer=nil
                if self.generation~=generation or self.mode~="SHIELD" then return end
                local ok,err=pcall(function()
                    local after=self:foreground() and self:location() or nil
                    local result="UNKNOWN"
                    if before and after then result=before~=after and "CHANGED" or "UNCHANGED" end
                    if result=="CHANGED" then self.audit_changed=self.audit_changed+1
                    elseif result=="UNCHANGED" then self.audit_unchanged=self.audit_unchanged+1
                    else self.audit_unknown=self.audit_unknown+1 end
                    self:log("PAGE_OBSERVED,"..result..","..tostring(before or "unknown")..","..tostring(after or "unknown"))
                end)
                if not ok then self:fail(err) end
            end
            UIManager:scheduleIn(0.25,self.audit_timer)
        end)
        if not ok then self:fail(err) end
    end)
end
function Plugin:raw(ev)
    if not self.mode or self.unlock_pending then return end
    if self.log_error then self:stop("report_write_failed"); return end
    if not self:foreground() then self:stop("foreground_lost"); return end
    local typ,code,val=tonumber(ev.type),tonumber(ev.code),tonumber(ev.value)
    if not ((typ==0 and (code==0 or code==3)) or (typ==3 and (code==47 or code==53 or code==54 or code==57))) then return end
    local ts=timestamp(ev)
    if not ts or ts<=0 or val==nil then self:fail("invalid_event_time_or_value"); return end
    self.raw_events=self.raw_events+1
    local out=self.gate:feed(ts,typ,code,val)
    if self.gate.blocked then self:stop("raw_desync"); return end
    for _,v in ipairs(out) do
        self.completed=self.completed+1
        local horizontal=v.compatible and math.abs(v.dx)>=2*math.abs(v.dy)
        if v.compatible then self.compatible=self.compatible+1 end
        if v.reason=="FAST_COMPATIBLE_STROKE" then self.fast_accepted=self.fast_accepted+1 end
        if horizontal then self.horizontal=self.horizontal+1 end
        -- Bound reports: 3000 contact lines; aggregate counters remain exact.
        if self.completed<=3000 then
            self:log(string.format("CONTACT,%d,%s,%d,%d,%.1f,%.1f,%d,%s,%.3f,%.1f",v.ts,v.reason,v.duration,v.points,v.dx,v.dy,v.slot,horizontal and "HORIZONTAL" or "NO_PAGE",v.straight,v.maxstep))
        end
        -- Two deliberate opposite vertical strokes provide a touch-only escape.
        -- Never enable a normal gesture or page turn from this sequence.
        if self.mode=="SHIELD" and self.continuous and v.compatible and
            math.abs(v.dy)>=350 and math.abs(v.dy)>=3*math.abs(v.dx) then
            local sign=v.dy>0 and 1 or -1
            local prev=self.exit_stroke
            if prev and prev.sign~=sign and v.ts>prev.ts and v.ts-prev.ts<=8000000 then
                self:log("EXIT,opposite_vertical_strokes")
                -- Keep the dispatch wrapper active until this input batch has
                -- finished, so the unlock stroke itself is not a stock gesture.
                self.unlock_pending=true
                self.pending=nil
                local gen=self.generation
                UIManager:nextTick(function()
                    if self.generation==gen and self.unlock_pending then
                        self:stop("intent_unlock")
                    end
                end)
                return
            end
            self.exit_stroke={sign=sign,ts=v.ts}
            self:log("EXIT_ARM,vertical_stroke")
        elseif horizontal then
            self.exit_stroke=nil
            self:queuePage(v)
        end
    end
    if self.raw_events%128==0 and self.report then self.report:flush() end
end
function Plugin:installRawHook()
    local input=Device.input
    if not input or type(input.registerEventAdjustHook)~="function" then return false end
    if shared.installed then return shared.input==input end
    input:registerEventAdjustHook(function(_,ev)
        local o=shared.owner
        if o and o.mode then
            local ok,err=pcall(o.raw,o,ev)
            if not ok then o:fail(err) end
        end
    end)
    shared.installed=true; shared.input=input
    return true
end
function Plugin:start(mode, seconds, fast, auto_resume)
    if Global.active then return false,"Stop Global Shield first" end
    if mode=="SHIELD" then local ok,why=License.check(true); if not ok then return false,why end end
    if self.mode then self:stop("replaced") end
    local continuous=mode=="SHIELD" and seconds==0
    if (mode~="SHADOW" and mode~="SHIELD") or type(seconds)~="number" or
        (not continuous and (seconds<1 or seconds>900)) then return false,"Invalid trial" end
    if exists(DISABLE) then return false,"DISABLE_INTENTGATE is present" end
    if not self:foreground() then return false,"Close menu and return to book" end
    if type(UIManager.handleInputEvent)~="function" or type(UIManager.nextTick)~="function" or type(UIManager.unschedule)~="function" then return false,"UIManager incompatible" end
    local screen=Device.screen
    if Device.model~="KindleBasic4" then return false,"Expected KindleBasic4" end
    if not screen or type(screen.getRotationMode)~="function" or screen:getRotationMode()~=0 then return false,"Portrait rotation 0 only" end
    if screen:getWidth()~=1072 or screen:getHeight()~=1448 then return false,"Expected 1072x1448 Basic 2022 portrait" end
    if not lfs.attributes("/mnt/us/documents","mode") then return false,"Kindle user store unavailable" end
    if shared.owner and shared.owner~=self then return false,"Another trial active" end
    if not self:installRawHook() then return false,"Raw hook unavailable" end
    lfs.mkdir("/mnt/us/GhostGuard_Reports"); lfs.mkdir(REPORT)
    local filename=REPORT.."/"..os.date("%Y%m%d_%H%M%S").."_"..mode..".log"
    local f,err=io.open(filename,"a")
    if not f then return false,"Cannot create log: "..tostring(err) end
    self.report=f; self.log_error=false; self.gate=Gate.new(1072,1448,fast)
    self.continuous=continuous; self.auto_resume=continuous and auto_resume==true; self.exit_stroke=nil
    self.mode=mode; self.completed=0; self.compatible=0; self.horizontal=0; self.suppressed=0; self.page_requests=0; self.raw_events=0
    self.audit_changed=0; self.audit_unchanged=0; self.audit_unknown=0; self.fast_accepted=0
    self.last_page_ts=nil; self.pending=nil; self.generation=(self.generation or 0)+1
    self:log("START,IntentShield1.0,"..mode..",duration="..seconds..",portrait=1072x1448,fast="..tostring(fast==true)..",continuous="..tostring(continuous)..",auto_resume="..tostring(self.auto_resume))
    if self.log_error then self:stop("report_write_failed"); return false,"Log write failed" end
    f:flush(); shared.owner=self
    if mode=="SHIELD" then
        local original=UIManager.handleInputEvent
        self.original=original
        local wrapper=function(manager,ev)
            if self.mode=="SHIELD" and type(ev)=="table" and ev.handler=="onGesture" then
                local ok,fg=pcall(self.foreground,self)
                if not ok then self:fail(fg); return end
                if not fg then self:stop("foreground_lost"); return end
                self.suppressed=self.suppressed+1
                return -- no stock tap, hold, pan, swipe, or timer-generated gesture
            end
            return original(manager,ev)
        end
        self.wrapper=wrapper; UIManager.handleInputEvent=wrapper
    end
    local gen=self.generation
    if not continuous then
        self.timer=function()
            if self.generation==gen and self.mode then self:stop("timeout"); notice("IntentShield: phien thu da ket thuc. Cam ung binh thuong.",3) end
        end
        UIManager:scheduleIn(seconds,self.timer)
    end
    -- USB stop marker, foreground and rotation checked even without touch events.
    self.monitor=function()
        if self.generation~=gen or not self.mode then return end
        local ok,err=pcall(function()
            if exists(DISABLE) or not self:foreground() or screen:getRotationMode()~=0 then
                self:stop("monitor_stop"); return
            end
            if self.mode=="SHIELD" and not License.check(false) then self:stop("license_invalid"); return end
            if self.mode=="SHIELD" and UIManager.handleInputEvent~=self.wrapper then
                self:stop("dispatch_hook_replaced"); return
            end
            if self.report then self.report:flush() end
            UIManager:scheduleIn(2,self.monitor)
        end)
        if not ok then self:fail(err) end
    end
    UIManager:scheduleIn(2,self.monitor)
    return true
end
function Plugin:arm(mode,seconds,fast,auto_resume)
    self:stop("rearm")
    self.armed=true
    local gen=self.generation
    notice("Ve trang sach. Bat dau sau 4 giay. Nut nguon de dung; che do tu khoi phuc se bat lai sau 5 giay.",2)
    self.start_timer=function()
        self.start_timer=nil
        if not self.armed or self.generation~=gen then return end
        self.armed=false
        local ok,a,b=pcall(self.start,self,mode,seconds,fast,auto_resume)
        if not ok then self:fail(a); notice("IntentGate loi: "..tostring(a),5)
        elseif not a then self:stop("start_refused"); notice("IntentGate: "..tostring(b),5) end
    end
    UIManager:scheduleIn(4,self.start_timer)
end
function Plugin:init()
    self.ui.menu:registerToMainMenu(self)
    Global:maybeAuto()
end
function Plugin:addToMainMenu(menu)
    local function startGlobal()
        local valid,why=License.check(true)
        if not valid then notice("Cần license hợp lệ: "..tostring(why),8); return end
        UIManager:show(ConfirmBox:new{
            text="Bật Global Shield liên tục. Vuốt ngang để chọn/lật trang; vuốt dọc để cuộn. Thoát: hai nét vuốt dọc dài ngược chiều ở 1/4 bên trái trong 8 giây.",
            ok_text="Bật",
            ok_callback=function()
                self:stop("global_arm")
                Global.manual_off=false
                UIManager:scheduleIn(3,function()
                    if Global.manual_off then return end
                    local ok,err=Global:start(0,true)
                    if not ok then notice(tostring(err),6) end
                end)
            end,
        })
    end
    menu.dcprointentgate={text="DCPRO IntentShield™",sorting_hint="more_tools",sub_item_table={
        {text="Global Shield — liên tục + Auto Resume",checked_func=function() return Global.active end,
            callback=function()
                if Global.active then Global:stop("manual"); Global.manual_off=true
                else startGlobal() end
            end},
        {text="Dừng bảo vệ",callback=function() Global:stop("manual"); Global.manual_off=true; self:stop("manual"); notice("Đã dừng IntentShield") end},
        {text="Trạng thái bảo vệ",callback=function() notice("Global Shield: "..(Global.active and "BẬT" or "TẮT").."\nAuto Resume: "..(Global.active and Global.auto_resume and "BẬT" or "TẮT"),6) end},
        {text="License",sub_item_table={
            {text="Kiểm tra license",callback=function() local ok,why=License.check(true); notice((ok and "HỢP LỆ" or "KHÔNG HỢP LỆ").."\n"..tostring(why),10) end},
            {text="Đồng bộ license online",callback=function() local ok,why=License.sync(); notice((ok and "Đã đồng bộ" or "Đồng bộ thất bại").."\n"..tostring(why),10) end},
            {text="Hướng dẫn kích hoạt",callback=function() notice("Dùng license GhostGuard RSA v4 hợp lệ (license.key trong thư mục plugin) hoặc đồng bộ license online qua Wi-Fi.",10) end},
        }},
        {text="Báo cáo & hướng dẫn",callback=function() notice("GhostGuard_Reports/IntentGate/\nVuốt ngang để chọn hoặc lật trang. Vuốt dọc để cuộn/mở menu. Hai nét vuốt dọc dài ngược chiều ở mép trái để thoát. USB: DISABLE_INTENTGATE.",12) end},
    }}
end
function Plugin:onSuspend()
    Global:suspend()
    local plan
    if self.mode=="SHIELD" and self.continuous and self.auto_resume then
        plan={fast=self.gate.fast,reader=self.ui}
    end
    -- A second suspend during the 5-second wake delay cancels auto resume.
    self:stop("suspend")
    self.resume_plan=plan
end
function Plugin:onResume()
    Global:onResume()
    local plan=self.resume_plan
    self:stop("resume")
    if not plan or plan.reader~=self.ui then return end
    local gen=self.generation
    self.resume_timer=function()
        self.resume_timer=nil
        if self.generation~=gen then return end
        local ok,a,b=pcall(self.start,self,"SHIELD",0,plan.fast,true)
        if not ok then self:fail(a)
        elseif not a then self:stop("resume_refused"); logger.info("IntentShield resume refused",b) end
    end
    UIManager:scheduleIn(5,self.resume_timer)
end
function Plugin:onPowerOff() Global:stop("poweroff"); self:stop("poweroff") end
function Plugin:onReboot() Global:stop("reboot"); self:stop("reboot") end
function Plugin:onCloseWidget() self:stop("close_widget") end
function Plugin:onClose() self:stop("close") end
return Plugin
