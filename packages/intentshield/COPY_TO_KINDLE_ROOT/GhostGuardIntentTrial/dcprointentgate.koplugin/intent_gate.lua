-- GhostGuard IntentGate Lab 0.1 -- offline/shadow prototype, no device I/O.
-- Input: timestamp in microseconds, Linux MT Type-B event (post-adjustment coordinates).
-- Output: completed contact verdicts only. No gesture dispatch, no EVIOCGRAB.
local Gate = {}; Gate.__index = Gate
local function dist(x,y) return math.sqrt(x*x+y*y) end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function inside(p,b)
    return p and b and p.x>=b.x0 and p.x<=b.x1 and p.y>=b.y0 and p.y<=b.y1
end
function Gate.new(w,h,fast)
    assert(finite(w) and finite(h) and w>0 and h>0)
    local scale=math.min(w,h)/1072
    return setmetatable({w=w,h=h,scale=scale,slots={},slot=0,frame=0,last_ts=nil,
        blocked=false,challenge=nil,fast=fast==true},Gate)
end
function Gate:reset()
    self.slots={}; self.slot=0; self.last_ts=nil; self.challenge=nil
end
-- Intended caller supplies visible, independently selected non-overlapping targets.
-- Challenge is a single-use permission, not a claim of hardware authentication.
function Gate:arm(challenge, now)
    assert(finite(now) and type(challenge)=='table' and finite(challenge.expires))
    assert(challenge.expires>now and challenge.expires-now<=5000000)
    for _, b in ipairs({challenge.start,challenge.finish}) do
        assert(type(b)=='table' and finite(b.x0) and finite(b.x1) and finite(b.y0) and finite(b.y1))
        assert(b.x0>=0 and b.y0>=0 and b.x1<=self.w and b.y1<=self.h and b.x0<b.x1 and b.y0<b.y1)
    end
    local a,b=challenge.start,challenge.finish
    assert(a.x1<b.x0 or b.x1<a.x0 or a.y1<b.y0 or b.y1<a.y0)
    self.challenge={start=a,finish=b,armed=now,expires=challenge.expires}
end
local function point(self,s,c)
    if not (finite(s.x) and finite(s.y)) then return end
    if s.x<0 or s.x>self.w or s.y<0 or s.y>self.h then c.invalid=true; return end
    local p={x=s.x,y=s.y}
    if not c.first then c.first=p; c.last=p; c.points=1; return end
    local d=dist(p.x-c.last.x,p.y-c.last.y)
    if d>0 then
        c.points=c.points+1; c.path=c.path+d; c.maxstep=math.max(c.maxstep,d); c.last=p
    end
end
function Gate:verdict(c,ts,slot)
    local duration=ts-c.start
    local net=c.first and c.last and dist(c.last.x-c.first.x,c.last.y-c.first.y) or 0
    local straight=c.path>0 and net/c.path or 0
    local dx=c.first and c.last and c.last.x-c.first.x or 0
    local dy=c.first and c.last and c.last.y-c.first.y or 0
    -- Experimental fast lane: all original integrity checks still apply.
    local fast=self.fast and duration>=110000 and duration<150000
        and c.points>=8 and math.abs(dx)>=240*self.scale
        and math.abs(dx)>=3*math.abs(dy) and straight>=0.90
        and c.maxstep<=72*self.scale
    local reason
    if c.invalid then reason='INVALID_SEQUENCE'
    elseif c.overlap then reason='OVERLAPPING_CONTACT'
    elseif not c.seen_x or not c.seen_y then reason='AXIS_NOT_EXPLICIT_THIS_CONTACT'
    elseif (duration<150000 and not fast) or duration>1200000 then reason='DURATION'
    elseif c.points<4 then reason='FEW_DISTINCT_POINTS'
    elseif net<120*self.scale then reason='SHORT_DISPLACEMENT'
    elseif straight<0.78 then reason='IRREGULAR_PATH'
    elseif c.maxstep>96*self.scale then reason='LARGE_FRAME_JUMP'
    else reason=fast and 'FAST_COMPATIBLE_STROKE' or 'INTENT_COMPATIBLE_STROKE' end
    local compatible=reason=='INTENT_COMPATIBLE_STROKE' or reason=='FAST_COMPATIBLE_STROKE'
    local auth=false
    local ch=self.challenge
    if ch then
        -- Only a completed stroke started after the arm action may consume it.
        -- Any completed attempt consumes it; expiry also clears it.
        self.challenge=nil
        auth=compatible and c.start>=ch.armed and ts<=ch.expires
            and inside(c.first,ch.start) and inside(c.last,ch.finish) or false
    end
    return {frame=self.frame,slot=slot,ts=ts,reason=reason,compatible=compatible,
        challenge_authorized=auth,duration=duration,net=net,points=c.points,straight=straight,maxstep=c.maxstep,
        dx=c.first and c.last and (c.last.x-c.first.x) or 0,
        dy=c.first and c.last and (c.last.y-c.first.y) or 0,
        explicit_x=c.seen_x,explicit_y=c.seen_y,retained_position=c.used_retained,
        x0=c.first and c.first.x,y0=c.first and c.first.y,x1=c.last and c.last.x,y1=c.last and c.last.y}
end
function Gate:feed(ts,typ,code,value)
    if not (finite(ts) and finite(typ) and finite(code) and finite(value)) then
        self:reset(); self.blocked=true; return {}
    end
    if self.last_ts and ts<self.last_ts then self:reset(); self.blocked=true end
    self.last_ts=ts
    if typ==0 and code==3 then self:reset(); self.blocked=true; return {} end -- SYN_DROPPED: no resync here
    if self.blocked then return {} end -- require explicit new session/resync by host
    if self.challenge and ts>self.challenge.expires then self.challenge=nil end
    if typ==3 then
        if code==47 then
            if value<0 or value>31 or value%1~=0 then self:reset(); self.blocked=true; return {} end
            self.slot=value; return {}
        end
        local s=self.slots[self.slot]
        if not s then s={}; self.slots[self.slot]=s end
        if code==57 then
            if value>=0 then
                local invalid=s.c~=nil
                s.c={start=ts,id=value,seen_x=false,seen_y=false,points=0,path=0,maxstep=0,
                    overlap=false,invalid=invalid,used_retained=false}
                s.changed=true
            elseif value==-1 then
                if s.c then s.c.ended=true; s.changed=true end
            else
                if s.c then s.c.invalid=true end
            end
        elseif code==53 or code==54 then
            if code==53 then s.x=value else s.y=value end
            if s.c then
                if code==53 then s.c.seen_x=true else s.c.seen_y=true end
                s.changed=true
            end
        end
    elseif typ==0 and code==0 then
        self.frame=self.frame+1
        local count=0
        for _,s in pairs(self.slots) do if s.c then count=count+1 end end
        local out={}
        for slot,s in pairs(self.slots) do
            local c=s.c
            if c then
                if count>1 then c.overlap=true end
                if s.changed then
                    if (not c.seen_x or not c.seen_y) and s.x~=nil and s.y~=nil then c.used_retained=true end
                    -- Retained coordinates are protocol-valid but not evidence of intent.
                    -- Start measuring only after both axes have been observed in this contact.
                    if c.seen_x and c.seen_y then point(self,s,c) end
                    if c.ended then out[#out+1]=self:verdict(c,ts,slot); s.c=nil end
                    s.changed=false
                end
            end
        end
        return out
    end
    return {}
end
return Gate
