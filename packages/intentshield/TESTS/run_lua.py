# Local Lua 5.4 harness; not KOReader LuaJIT.
import ctypes as c,sys
l=c.CDLL('liblua5.4.so.0'); l.luaL_newstate.restype=c.c_void_p
L=l.luaL_newstate();l.luaL_openlibs.argtypes=[c.c_void_p];l.luaL_openlibs(L)
l.luaL_loadstring.argtypes=[c.c_void_p,c.c_char_p];l.lua_pcallk.argtypes=[c.c_void_p,c.c_int,c.c_int,c.c_int,c.c_longlong,c.c_void_p];l.lua_tolstring.argtypes=[c.c_void_p,c.c_int,c.c_void_p];l.lua_tolstring.restype=c.c_char_p
import json
s='arg={[1]='+json.dumps(sys.argv[2])+'}; dofile('+json.dumps(sys.argv[1])+')'
r=l.luaL_loadstring(L,s.encode()) or l.lua_pcallk(L,0,-1,0,0,None)
if r: print(l.lua_tolstring(L,-1,None).decode()); sys.exit(1)
