#!/usr/bin/env python3
import argparse, base64, datetime, pathlib, secrets
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding

FIELDS = ["license_format","serial","customer","issued_at","expire","features","license_id","key_id","sig_alg"]

def norm_serial(s):
    return ''.join(c for c in s.upper() if c.isalnum())

def canon(d):
    return ''.join(f"{k}={d[k]}\n" for k in FIELDS).encode('utf-8')

def parse(path):
    d={}
    for raw in pathlib.Path(path).read_text(encoding='utf-8').splitlines():
        if not raw or raw.lstrip().startswith('#'): continue
        if '=' not in raw: raise SystemExit(f"Malformed line: {raw}")
        k,v=raw.split('=',1)
        if k in d: raise SystemExit(f"Duplicate field: {k}")
        d[k]=v
    return d

def cmd_init(a):
    key=rsa.generate_private_key(public_exponent=65537,key_size=a.bits)
    pathlib.Path(a.private).write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    pathlib.Path(a.public).write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo))
    print(f"Created RSA-{a.bits} keypair. Keep {a.private} OFFLINE and private.")

def cmd_issue(a):
    d={
      'license_format':'4', 'serial':norm_serial(a.serial), 'customer':a.customer.strip(),
      'issued_at':a.issued_at or datetime.date.today().isoformat(), 'expire':a.expire.lower(),
      'features':','.join(x.strip().lower() for x in a.features.split(',') if x.strip()),
      'license_id':a.license_id or ('GG4-'+secrets.token_hex(8).upper()),
      'key_id':a.key_id, 'sig_alg':'RSA-SHA256'
    }
    if not d['serial'] or '\n' in d['customer'] or '\r' in d['customer']: raise SystemExit('Invalid serial/customer')
    key=serialization.load_pem_private_key(pathlib.Path(a.private).read_bytes(),password=None)
    sig=key.sign(canon(d),padding.PKCS1v15(),hashes.SHA256())
    text=''.join(f"{k}={d[k]}\n" for k in FIELDS)+f"sig={base64.b64encode(sig).decode()}\n"
    pathlib.Path(a.output).write_text(text,encoding='utf-8')
    print(f"Issued {d['license_id']} for {d['serial']} -> {a.output}")

def cmd_verify(a):
    d=parse(a.license)
    for k in FIELDS+['sig']:
        if k not in d: raise SystemExit(f'Missing field: {k}')
    pub=serialization.load_pem_public_key(pathlib.Path(a.public).read_bytes())
    try:
        pub.verify(base64.b64decode(d['sig'],validate=True),canon(d),padding.PKCS1v15(),hashes.SHA256())
    except Exception as e: raise SystemExit(f'INVALID: {e}')
    print('VALID RSA-SHA256 signature')

def main():
    p=argparse.ArgumentParser(description='GhostGuard License v4 issuer/verifier')
    sub=p.add_subparsers(dest='cmd',required=True)
    s=sub.add_parser('init'); s.add_argument('--private',required=True); s.add_argument('--public',required=True); s.add_argument('--bits',type=int,default=3072,choices=[2048,3072,4096]); s.set_defaults(func=cmd_init)
    s=sub.add_parser('issue'); s.add_argument('--private',required=True); s.add_argument('--serial',required=True); s.add_argument('--customer',required=True); s.add_argument('--expire',default='lifetime'); s.add_argument('--issued-at'); s.add_argument('--features',default='ghostguard'); s.add_argument('--license-id'); s.add_argument('--key-id',default='ghostguard-rc-2026-08'); s.add_argument('--output',default='license.key'); s.set_defaults(func=cmd_issue)
    s=sub.add_parser('verify'); s.add_argument('--public',required=True); s.add_argument('--license',required=True); s.set_defaults(func=cmd_verify)
    a=p.parse_args(); a.func(a)
if __name__=='__main__': main()
