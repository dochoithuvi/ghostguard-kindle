import base64, hashlib, io, pathlib, re, subprocess, tempfile, zipfile
p=pathlib.Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
subprocess.run(["sha256sum","-c","SHA256SUMS"],cwd=p,check=True)
sh=p/"DCPRO_IntentShield_OneClick_Install.sh"
subprocess.run(["sh","-n",str(sh)],check=True)
header,encoded=sh.read_bytes().split(b"\n__DCPRO_PAYLOAD_BELOW__\n",1)
assert b"1.2.1 RC1" in header
assert b"fbbda29e0d46a54ab9d3d8ddf9b606f02341ef789f45bd3463bcda05d853b330" in header
assert b"kindle-koplugin-armv7.zip" in header
with zipfile.ZipFile(io.BytesIO(base64.b64decode(encoded))) as z:
    assert z.testzip() is None and len(z.namelist())==len(set(z.namelist()))
    files={n:z.read(n) for n in z.namelist()}
pre="COPY_TO_KINDLE_ROOT/GhostGuardIntentTrial/"
plugin=pre+"dcprointentgate.koplugin/"
tools="COPY_TO_KINDLE_ROOT/.dcpro_intentshield/tools/"
for manifest,prefix,expected in [(pre+"SHA256SUMS",plugin,23),(pre+"BOOT_SHA256SUMS",pre,2)]:
    lines=files[manifest].decode().splitlines()
    assert len(lines)==expected
    for line in lines:
        digest,n=line.split(None,1)
        assert sha(files[prefix+n])==digest,n
assert sha(files[plugin+"intent_gate.lua"])=="28e1fc837e588a1bc7935aeedf46bbae7f1a6c97ad7e9134a5812943d467a357"
assert files[plugin+"update-version.txt"]==b"12101\n"
for n,d in files.items():
    assert not re.search(rb"-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----",d),n
    assert not n.endswith(("license.key","database.json")),n
    if n.endswith((".sh",".tool")): subprocess.run(["sh","-n"],input=d,check=True)
pkg=p/"IntentShield_UPDATE.zip"
with zipfile.ZipFile(pkg) as z:
    assert z.testzip() is None and len(z.namelist())==23
    new={n:z.read(n) for n in z.namelist()}
    assert new=={n[len(plugin):]:d for n,d in files.items() if n.startswith(plugin)}
    with tempfile.TemporaryDirectory() as t:
        z.extractall(t)
        for n in new:
            if n.endswith(".lua"): subprocess.run(["luac5.4","-p",str(pathlib.Path(t)/n)],check=True)
        subprocess.run(["lua5.4",str(p/"test_recovery.lua"),t],check=True)
with zipfile.ZipFile(p.parent/"1.2.0"/"IntentShield_UPDATE.zip") as z:
    old={n:z.read(n) for n in z.namelist()}
assert set(old)==set(new)
assert {n for n in old if old[n]!=new[n]}=={"_meta.lua","main.lua","global_shield.lua","smart_update.lua","update-version.txt"}
assert (p/"IntentShield_UPDATE.manifest").read_text()==f"DCPRO-UPDATE-1\nsequence=12101\nversion=1.2.1-rc1\nsha256={sha(pkg.read_bytes())}\nbytes={pkg.stat().st_size}\n"
assert (p/"IntentShield_UPDATE.sig").stat().st_size==384
with tempfile.TemporaryDirectory() as t:
    pub=pathlib.Path(t)/"production.pub"; pub.write_bytes(files[tools+"IntentShield_UPDATE_RC.pub"])
    subprocess.run(["openssl","dgst","-sha256","-verify",str(pub),"-signature",str(p/"IntentShield_UPDATE.sig"),str(p/"IntentShield_UPDATE.manifest")],check=True)
with zipfile.ZipFile(p/"DCPRO_IntentShield_1.2.1_RC1_OneClick.zip") as z:
    assert z.testzip() is None
    assert z.read(sh.name)==sh.read_bytes()
    assert z.read("README.md")== (p/"README.md").read_bytes()
print("PASS: recovery mock tests, release assets, protected core, signed update, no private key.")
