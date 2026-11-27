import base64, hashlib, io, pathlib, re, subprocess, textwrap, zipfile
here=pathlib.Path(__file__).resolve().parent
out=pathlib.Path("dist")
out.mkdir(exist_ok=True)
raw=(here/"DCPRO_IntentShield_OneClick_Beta5_r2.sh").read_bytes()
sha=lambda b:hashlib.sha256(b).hexdigest()
assert sha(raw)=="7b5acc36e37e91bd1d7c231a1d32a46141888bacdab1e600c2e62cbb238ee62b"
marker=b"\n__DCPRO_PAYLOAD_BELOW__\n"
header,encoded=raw.split(marker,1)
with zipfile.ZipFile(io.BytesIO(base64.b64decode(encoded))) as z:
    assert z.testzip() is None
    assert len(z.namelist())==len(set(z.namelist()))
    original={n:z.read(n) for n in z.namelist()}
    attrs={n:z.getinfo(n) for n in z.namelist()}
root="COPY_TO_KINDLE_ROOT/GhostGuardIntentTrial/"
plugin=root+"dcprointentgate.koplugin/"
def verify(files, manifest, prefix):
    lines=files[manifest].decode().splitlines()
    for line in lines:
        digest,n=line.split(None,1)
        assert sha(files[prefix+n])==digest, n
    return len(lines)
assert verify(original,root+"SHA256SUMS",plugin)==21
assert verify(original,root+"BOOT_SHA256SUMS",root)==2
assert sha(original[plugin+"intent_gate.lua"])=="28e1fc837e588a1bc7935aeedf46bbae7f1a6c97ad7e9134a5812943d467a357"
files=original.copy()
tool="COPY_TO_KINDLE_ROOT/.dcpro_intentshield/tools/GhostGuard_IntentGate_INSTALL.tool"
changed={tool,plugin+"_meta.lua",plugin+"global_shield.lua",plugin+"main.lua"}
for n in changed:
    files[n]=original[n].replace(b"1.1 Beta 5 r2",b"1.1 Final").replace(b"1.1-beta5-r2",b"1.1-final").replace(b"1.1-beta5-demo",b"1.1-final")
    assert files[n]!=original[n], n
files["README_VI.txt"]=(here/"README.md").read_bytes()
manifest=root+"SHA256SUMS"
files[manifest]="".join(f"{sha(files[n])}  {n[len(plugin):]}\n" for n in sorted(files) if n.startswith(plugin)).encode()
assert verify(files,manifest,plugin)==21
assert verify(files,root+"BOOT_SHA256SUMS",root)==2
assert {n for n in files if files[n]!=original[n]}==changed|{"README_VI.txt",manifest}
for n,d in files.items():
    assert not n.startswith("/") and ".." not in pathlib.PurePosixPath(n).parts
    assert not re.search(rb"-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}",d),n
    assert not n.endswith(("licenses.json","license.key","database.json")),n
    if n.endswith(".pem"): assert d.startswith(b"-----BEGIN PUBLIC KEY-----"),n
    if n.endswith((".sh",".tool")): subprocess.run(["sh","-n"],input=d,check=True)
header=header.replace(b"1.1 Beta 5 r2",b"1.1 Final")
subprocess.run(["sh","-n"],input=header,check=True)
buf=io.BytesIO()
with zipfile.ZipFile(buf,"w",zipfile.ZIP_DEFLATED) as z:
    for n in sorted(files):
        info=attrs[n]
        z.writestr(info,files[n])
with zipfile.ZipFile(buf) as z:
    assert z.testzip() is None
    assert {n:z.read(n) for n in z.namelist()}==files
installer=out/"DCPRO_IntentShield_OneClick_Install.sh"
installer.write_bytes(header+marker+("\n".join(textwrap.wrap(base64.b64encode(buf.getvalue()).decode(),76))+"\n").encode())
subprocess.run(["sh","-n",str(installer)],check=True)
with zipfile.ZipFile(out/"DCPRO_IntentShield_1.1_Final_OneClick.zip","w",zipfile.ZIP_DEFLATED) as z:
    z.write(installer,installer.name)
    z.write(here/"README.md","README.md")
    z.writestr("SHA256SUMS",f"{sha(installer.read_bytes())}  {installer.name}\n")
with zipfile.ZipFile(out/"DCPRO_IntentShield_1.1_Final_OneClick.zip") as z:
    assert z.testzip() is None
    assert z.read(installer.name)==installer.read_bytes()
(out/"SHA256SUMS").write_text("".join(f"{sha(p.read_bytes())}  {p.name}\n" for p in sorted(out.iterdir()) if p.suffix in (".sh",".zip")))
print("PASS: exact Beta 5 r2 source; 21 plugin checksums, 2 boot checksums; only branding and docs changed; no private keys; SH syntax and ZIP integrity.")
print((out/"SHA256SUMS").read_text())
