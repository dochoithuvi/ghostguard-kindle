import pathlib, subprocess, tempfile, time
here=pathlib.Path(__file__).resolve().parent
helper=(here/"kpm_index_timeout.sh").read_text()
with tempfile.TemporaryDirectory() as t:
    prefix='set -eu\nT="$1"\nKPM_WORKER=""\nline(){ :; }\n'+helper+'\n'
    def run(cmd,expected):
        start=time.monotonic()
        p=subprocess.run(["sh","-c",prefix+cmd,"sh",t],capture_output=True,text=True,timeout=15)
        assert p.returncode==expected,(p.returncode,p.stdout,p.stderr)
        assert time.monotonic()-start<15
        print("PASS",cmd,p.stdout.strip())
    run('kpm_index_run 5 sh -c "exit 0"',0)
    run('kpm_index_run 5 sh -c "exit 7"',7)
    run('kpm_index_run 1 sh -c \'sleep 90 & echo $! > "$1/child"; wait\' sh "$T"',124)
    child=int((pathlib.Path(t)/"child").read_text())
    p=pathlib.Path(f"/proc/{child}/stat")
    assert not p.exists() or p.read_text().split(") ",1)[1].startswith("Z "), "child survived timeout"
    print("PASS: stuck child terminated")
