from pathlib import Path
import base64, hashlib, io, textwrap, zipfile, sys
here=Path(__file__).resolve().parent
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); mark=b'\n__DCPRO_PAYLOAD_BELOW__\n'
raw=src.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='d23e34c9f3b1d297b407d71f884c6a782d04124745646492d3c5cdc535a1eb2c', 'Unexpected Beta 1 source'
head,payload=raw.split(mark,1)
with zipfile.ZipFile(io.BytesIO(base64.b64decode(payload))) as z:
    assert z.testzip() is None
    files={n:z.read(n) for n in z.namelist()}
base='COPY_TO_KINDLE_ROOT/GhostGuardIntentTrial/'
p=base+'dcprointentgate.koplugin/'
def replace(s,a,b):
    assert s.count(a)==1,a
    return s.replace(a,b)
s=files[p+'global_shield.lua'].decode()
s=replace(s,"local Gate=dofile(root..'intent_gate.lua')", "local Gate=dofile(root..'intent_gate.lua')\nlocal Profile=dofile(root..'gesture_profile.lua')")
s=replace(s,"            elseif kind=='SELECT' then", "            elseif kind=='PANEL' then\n                Profile.openPanel(reader,Event)\n            elseif kind=='DICT' then\n                if not Profile.lookup(reader,v,Geom) then self:log('SKIP,no_word_or_unsupported_document') end\n            elseif kind=='SELECT' then")
s=replace(s,"            if h then self:dispatch(v,top,r,r and 'PAGE' or 'SELECT')", "            local action=r and Profile.action(v,1072,1448)\n            if action then self:dispatch(v,top,r,action)\n            elseif h then self:dispatch(v,top,r,r and 'PAGE' or 'SELECT')")
files[p+'global_shield.lua']=s.replace('1.1-beta1','1.1-beta2').encode()
files[p+'gesture_profile.lua']=(here/'gesture_profile.lua').read_bytes()
for name in ['_meta.lua','main.lua']:
    files[p+name]=files[p+name].replace(b'Beta 1',b'Beta 2').replace(b'1.1-beta1',b'1.1-beta2')
files[base+'SHA256SUMS']=''.join(f'{hashlib.sha256(files[n]).hexdigest()}  {n[len(p):]}\n' for n in sorted(files) if n.startswith(p)).encode()
files['README_VI.txt']+=b'\nBeta 2: Bottom-center upward swipe opens ZenOS Page Browser Aa; diagonal up-right ends on word for lookup (reflowable text). Auto Boot remains unsupported on Basic 2024.\n'
for n,data in files.items():
    assert not n.startswith('/') and '..' not in Path(n).parts
    assert b'-----BEGIN PRIVATE KEY-----' not in data and b'-----BEGIN RSA PRIVATE KEY-----' not in data
buf=io.BytesIO()
with zipfile.ZipFile(buf,'w',zipfile.ZIP_DEFLATED) as z:
    for n in sorted(files):
        info=zipfile.ZipInfo(n,date_time=(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED
        info.external_attr=(0o100644<<16)
        z.writestr(info,files[n])
encoded='\n'.join(textwrap.wrap(base64.b64encode(buf.getvalue()).decode(),76)).encode()+b'\n'
dst.write_bytes(head.replace(b'1.1 Beta 1',b'1.1 Beta 2')+mark+encoded)
with zipfile.ZipFile(buf) as z:
    assert z.testzip() is None
    for line in z.read(base+'SHA256SUMS').decode().splitlines():
        digest,n=line.split(None,1); assert hashlib.sha256(z.read(p+n)).hexdigest()==digest
print(dst,hashlib.sha256(dst.read_bytes()).hexdigest())
