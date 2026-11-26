#!/usr/bin/env python3
"""Build the candidate offline ZIP and self-contained network OneClick script."""
from pathlib import Path
import base64, hashlib, io, subprocess, zipfile
p = Path(__file__).resolve().parent
root = p / "COPY_TO_KINDLE_ROOT"
trial = root / "GhostGuardIntentTrial"
plugin = trial / "dcprointentgate.koplugin"
def sums(directory, files):
    return "".join(f"{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.relative_to(directory).as_posix()}\n" for f in sorted(files))
(trial / "SHA256SUMS").write_text(sums(plugin, [f for f in plugin.rglob("*") if f.is_file()]), encoding="utf-8")
(trial / "BOOT_SHA256SUMS").write_text(sums(trial, [trial / "boot-launch.sh", trial / "dcpro-intentshield-boot.conf"]), encoding="utf-8")
for f in (root / "documents").glob("*.sh"):
    subprocess.run(["sh", "-n", str(f)], check=True)
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(root.rglob("*")):
        if f.is_file(): z.write(f, f.relative_to(p))
    z.write(p / "README_VI.txt", "README_VI.txt")
payload = buf.getvalue()
out = p / "dist"
out.mkdir(exist_ok=True)
(out / "DCPRO_IntentShield_1.0_Final_Basic2022.zip").write_bytes(payload)
template = (p / "OneClick.template.sh").read_bytes()
script = out / "DCPRO_IntentShield_OneClick_Install.sh"
script.write_bytes(template.rstrip(b"\n") + b"\n" + base64.encodebytes(payload))
# Shell parses only until the payload marker when extracting a syntax-checkable prefix.
subprocess.run(["sh", "-n"], input=template.split(b"__DCPRO_PAYLOAD_BELOW__\n")[-2] if False else template.rsplit(b"\n__DCPRO_PAYLOAD_BELOW__",1)[0], check=True)
print(out)
