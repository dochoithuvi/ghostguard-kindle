local Gate=dofile('intent_gate.lua')
local function stroke(g,opts)
    opts=opts or {}; local t=opts.t or 1000000; local x=opts.x or 100; local y=opts.y or 100
    local function e(a,b,c) return g:feed(t,a,b,c) end
    e(3,47,0); e(3,57,1); e(3,53,x); if not opts.omit_y then e(3,54,y) end; e(0,0,0)
    if opts.overlap then e(3,47,1); e(3,57,2); e(3,53,500); e(3,54,500); e(0,0,0); e(3,47,0) end
    for i=1,4 do t=t+(opts.step_time or 50000); e(3,53,x+i*(opts.step or 40)); if opts.diagonal then e(3,54,y+i*25) end; e(0,0,0) end
    t=t+20000; e(3,57,-1); return e(0,0,0)[1]
end
local function new() return Gate.new(1072,1448) end
assert(stroke(new()).compatible)
assert(stroke(new(),{step=0}).reason=='FEW_DISTINCT_POINTS')
assert(stroke(new(),{step_time=5000}).reason=='DURATION')
assert(stroke(new(),{step=110}).reason=='LARGE_FRAME_JUMP')
assert(stroke(new(),{step=10}).reason=='SHORT_DISPLACEMENT')
assert(stroke(new(),{omit_y=true}).reason=='AXIS_NOT_EXPLICIT_THIS_CONTACT')
assert(stroke(new(),{overlap=true}).reason=='OVERLAPPING_CONTACT')
local g=new(); assert(stroke(g).compatible); local r=stroke(g,{t=2000000,omit_y=true}); assert(r.retained_position and not r.compatible)
local c={start={x0=80,x1=120,y0=80,y1=120},finish={x0=240,x1=280,y0=80,y1=120},expires=3000000}
g=new();g:arm(c,900000); assert(stroke(g).challenge_authorized);assert(not stroke(g,{t=2000000}).challenge_authorized)
g=new();g:arm(c,900000); assert(not stroke(g,{y=200}).challenge_authorized)
g=new();g:arm(c,900000); assert(not stroke(g,{t=4000000}).challenge_authorized)
g=new();g:feed(1000000,0,3,0);assert(g.blocked and stroke(g,{t=2000000})==nil)
g=new();g:feed(2000000,0,0,0);g:feed(1000000,0,0,0);assert(g.blocked)
print('PASS: 15 synthetic assertions (including one-time challenge, stale axes, overlap, loss of sync).')

local function faststroke(fast, duration, step, n, zigzag)
    local g=Gate.new(1072,1448,fast);local t=1000000
    local function e(a,b,c) return g:feed(t,a,b,c) end
    e(3,47,0);e(3,57,1);e(3,53,600);e(3,54,500);e(0,0,0)
    for i=1,n do t=1000000+math.floor((duration-10000)*i/n);e(3,53,600-i*step);if zigzag then e(3,54,500+(i%2)*90) end;e(0,0,0) end
    t=1000000+duration;e(3,57,-1);return e(0,0,0)[1]
end
assert(faststroke(false,137539,43,9).reason=='DURATION')
assert(faststroke(true,137539,43,9).reason=='FAST_COMPATIBLE_STROKE')
assert(not faststroke(true,90000,43,9).compatible)
assert(not faststroke(true,137539,5,9).compatible)
assert(not faststroke(true,137539,80,4).compatible)
assert(not faststroke(true,137539,43,9,true).compatible)
print('PASS: 6 fast-lane assertions (synthetic analogue, short duration, low movement, few frames, zigzag).')
