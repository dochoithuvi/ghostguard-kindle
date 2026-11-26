#!/bin/sh
set -eu
P="$1"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp "$P/license_crypto.lua" "$P/online_license.lua" "$T/"
mkdir "$T/keys"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$T/private.pem" 2>/dev/null
openssl pkey -in "$T/private.pem" -pubout -out "$T/keys/ci.pem" 2>/dev/null
printf 'return { ci = "ci.pem" }\n' > "$T/keys/keyring.lua"
cat > "$T/body" <<'EOF'
license_format=4
serial=TESTDEVICE
customer=CI
issued_at=2020-01-01
expire=lifetime
features=ghostguard
license_id=CI
key_id=ci
sig_alg=RSA-SHA256
EOF
openssl dgst -sha256 -sign "$T/private.pem" -out "$T/signature" "$T/body"
cat "$T/body" > "$T/license.key"
printf 'sig=%s\n' "$(openssl base64 -A -in "$T/signature")" >> "$T/license.key"
luajit TESTS/test_license_rsa.lua "$P" "$T"
