#!/bin/sh
# DCPRO GhostGuard Apps Script uploader. Manual/background invocation only.
# Never enables Wi-Fi, never logs the private token, and preserves source reports.
set -u
umask 077

DATA="${DCPRO_DATA_DIR:-/mnt/us/.dcpro_ghostguard}"
OUTBOX="$DATA/cloud_outbox"
STATUS="$DATA/CLOUD_UPLOAD_STATUS.txt"
LOCK="$DATA/CLOUD_UPLOAD.lock"
EXTERNAL_TOKEN_FILE="${DCPRO_TOKEN_FILE:-/mnt/us/documents/dochoithuvi_drive_token.conf}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
PLUGIN_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
BUNDLED_TOKEN_FILE="$PLUGIN_DIR/config/dochoithuvi_drive_token.conf"
OBSOLETE_ENDPOINT='https://script.google.com/macros/s/AKfycbwT4-nfLnkseEhacKzs_7V-DlbD10ZlSc448deipMJa6RAOLssL9b22QYoOLfS2O08g/exec'
TOKEN_FILE="$EXTERNAL_TOKEN_FILE"
[ -f "$TOKEN_FILE" ] || TOKEN_FILE="$BUNDLED_TOKEN_FILE"
# Migrate transparently from the known retired deployment shipped by v0.4.3-test.
if [ "$TOKEN_FILE" = "$EXTERNAL_TOKEN_FILE" ] && [ -f "$BUNDLED_TOKEN_FILE" ]; then
    external_url="$(sed -n 's/^[[:space:]]*WEB_APP_URL[[:space:]]*=[[:space:]]*//p' "$EXTERNAL_TOKEN_FILE" | head -n 1 | tr -d '\r\n[:space:]')"
    [ "$external_url" = "$OBSOLETE_ENDPOINT" ] && TOKEN_FILE="$BUNDLED_TOKEN_FILE"
fi
ENDPOINT_DEFAULT='https://script.google.com/macros/s/AKfycbw2Ex8MShC1eHmv3_rN1HN3P-Wkhd3G2Y6R5BTsxc5jGTf-ysifCDAOas5gbknajHYgKQ/exec'
CONFIG_ENDPOINT=""
if [ -f "$TOKEN_FILE" ]; then
    CONFIG_ENDPOINT="$(sed -n 's/^[[:space:]]*WEB_APP_URL[[:space:]]*=[[:space:]]*//p' "$TOKEN_FILE" | head -n 1 | tr -d '\r\n[:space:]')"
fi
ENDPOINT="${DCPRO_ENDPOINT:-${CONFIG_ENDPOINT:-$ENDPOINT_DEFAULT}}"
MAX_BYTES="${DCPRO_MAX_BYTES:-8388608}"
TMP_ROOT="$DATA/cloud_tmp"

mkdir -p "$DATA" "$OUTBOX" "$TMP_ROOT"
write_status() {
    tmp="$STATUS.tmp.$$"
    {
        echo 'DCPRO_GHOSTGUARD_CLOUD_V2'
        echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
        echo "STATUS=$1"
        echo "DETAIL=$2"
        echo "SENT=${SENT:-0}"
        echo "FAILED=${FAILED:-0}"
        echo "QUEUED=${QUEUED:-0}"
    } > "$tmp"
    mv "$tmp" "$STATUS"
}
cleanup() { rm -rf "$LOCK" "$TMP_ROOT/run.$$"; }
trap cleanup EXIT HUP INT TERM

if ! mkdir "$LOCK" 2>/dev/null; then
    stale=0
    if [ -f "$LOCK/PID" ]; then
        old_pid="$(sed -n '1p' "$LOCK/PID" 2>/dev/null | tr -cd '0-9')"
        if [ -z "$old_pid" ] || ! kill -0 "$old_pid" 2>/dev/null; then stale=1; fi
    else
        stale=1
    fi
    if [ "$stale" -eq 1 ]; then
        rm -rf "$LOCK"
        mkdir "$LOCK" 2>/dev/null || { write_status BUSY 'stale lock recovery failed'; exit 3; }
    else
        write_status BUSY 'another upload worker is active'
        exit 3
    fi
fi
printf '%s
' "$$" > "$LOCK/PID"
mkdir -p "$TMP_ROOT/run.$$"

case "$ENDPOINT" in
    https://script.google.com/macros/s/*/exec) : ;;
    http://127.0.0.1:*|http://localhost:*) [ "${DCPRO_ALLOW_TEST_ENDPOINT:-0}" = 1 ] || { write_status CONFIG_ERROR 'invalid endpoint'; exit 4; } ;;
    *) write_status CONFIG_ERROR 'endpoint must be Google Apps Script /exec'; exit 4 ;;
esac

[ -f "$TOKEN_FILE" ] || { write_status TOKEN_MISSING "$TOKEN_FILE"; exit 5; }
TOKEN="$(sed -n 's/^[[:space:]]*\(TOKEN\|UPLOAD_TOKEN\|DRIVE_TOKEN\)[[:space:]]*=[[:space:]]*//p' "$TOKEN_FILE" | head -n 1 | tr -d '\r\n[:space:]')"
[ -n "$TOKEN" ] || TOKEN="$(tr -d '\r\n[:space:]' < "$TOKEN_FILE")"
echo "$TOKEN" | grep -Eq '^[0-9A-Fa-f]{64}$' || { write_status TOKEN_INVALID 'token must be 64 hex characters'; exit 6; }

command -v curl >/dev/null 2>&1 || { write_status CURL_MISSING 'curl is required for TLS redirects'; exit 7; }
if command -v sha256sum >/dev/null 2>&1; then SHA='sha256sum'
elif command -v openssl >/dev/null 2>&1; then SHA='openssl dgst -sha256'
else write_status SHA256_MISSING 'sha256sum or openssl required'; exit 8; fi
if command -v base64 >/dev/null 2>&1; then B64='base64'
elif command -v openssl >/dev/null 2>&1; then B64='openssl base64 -A'
else write_status BASE64_MISSING 'base64 or openssl required'; exit 9; fi

json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/\\r/g; s/\t/\\t/g' | awk 'BEGIN{ORS=""}{if(NR>1)printf "\\n";printf "%s",$0}'; }
file_size() { wc -c < "$1" | tr -d '[:space:]'; }
sha_file() {
    if [ "$SHA" = sha256sum ]; then sha256sum "$1" | awk '{print $1}'
    else openssl dgst -sha256 "$1" | sed 's/^.*= //'; fi
}
base64_file() {
    if [ "$B64" = base64 ]; then base64 "$1" | tr -d '\r\n'
    else openssl base64 -A -in "$1"; fi
}

SENT=0 FAILED=0 QUEUED=0
found=0
for dir in "$OUTBOX"/*; do
    [ -d "$dir" ] || continue
    [ -f "$dir/.uploaded" ] && continue
    found=1; QUEUED=$((QUEUED + 1))
    name="$(basename "$dir")"
    serial="${name%%_*}"
    session="${name#*_}"
    if [ ! -f "$dir/UPLOAD_MANIFEST.txt" ]; then
        echo 'EMPTY_OR_LEGACY_OUTBOX=missing UPLOAD_MANIFEST.txt' > "$dir/UPLOAD_ERROR.txt"
        FAILED=$((FAILED+1)); continue
    fi
    has_payload=0
    for payload_file in "$dir"/*_SUMMARY.txt "$dir"/*_EVENTS.csv "$dir"/STALE_*.txt \
        "$dir"/KOReader_crash.log "$dir"/KOReader_extensions_crash.log "$dir"/GhostGuard_RUNTIME_FAULT.txt; do
        if [ -f "$payload_file" ]; then has_payload=1; break; fi
    done
    if [ "$has_payload" -ne 1 ]; then
        echo 'EMPTY_OUTBOX=no session summary/events/stale/crash diagnostic' > "$dir/UPLOAD_ERROR.txt"
        FAILED=$((FAILED+1)); continue
    fi
    archive="$TMP_ROOT/run.$$/DCPRO_GhostGuard_${serial}_${session}.tar.gz"
    (cd "$dir" && tar -czf "$archive" .) || { FAILED=$((FAILED+1)); continue; }
    if ! tar -tzf "$archive" 2>/dev/null | grep -qv '^\./$'; then
        echo 'EMPTY_ARCHIVE=tar contains no files' > "$dir/UPLOAD_ERROR.txt"
        rm -f "$archive"
        FAILED=$((FAILED+1)); continue
    fi
    size="$(file_size "$archive")"
    if [ "$size" -gt "$MAX_BYTES" ]; then
        echo "TOO_LARGE=$size" > "$dir/UPLOAD_ERROR.txt"
        FAILED=$((FAILED+1)); continue
    fi
    digest="$(sha_file "$archive")"
    encoded="$(base64_file "$archive")"
    filename="$(basename "$archive")"
    payload="$TMP_ROOT/run.$$/payload.json"
    # Includes legacy and explicit aliases. Extra JSON keys are harmless to
    # Apps Script and improve compatibility with older receiver deployments.
    cat > "$payload" <<EOF
{"token":"$TOKEN","uploadToken":"$TOKEN","serial":"$serial","device_id":"$serial","session":"$session","date":"$(date -u +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)","filename":"$filename","fileName":"$filename","mimeType":"application/gzip","mime_type":"application/gzip","sha256":"$digest","size":$size,"data":"$encoded","content_base64":"$encoded"}
EOF
    response="$TMP_ROOT/run.$$/response.txt"
    http="$(curl -L -sS --connect-timeout 20 --max-time 120 -o "$response" -w '%{http_code}' \
        -H 'Content-Type: application/json' --data-binary "@$payload" "$ENDPOINT" 2>/dev/null)"
    curl_rc=$?
    [ "$curl_rc" -eq 0 ] || http=000
    if [ "$http" = 200 ] && grep -Eq '"ok"[[:space:]]*:[[:space:]]*true|"success"[[:space:]]*:[[:space:]]*true|"duplicate"[[:space:]]*:[[:space:]]*true|"status"[[:space:]]*:[[:space:]]*"(ok|success|duplicate)"' "$response"; then
        printf 'UTC=%s\nSHA256=%s\nHTTP=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$digest" "$http" > "$dir/.uploaded"
        SENT=$((SENT+1)); QUEUED=$((QUEUED-1))
    else
        {
            echo "HTTP=$http"
            if [ -f "$response" ]; then
                sed 's/[[:cntrl:]]//g' "$response" | head -c 1024
                echo
            else
                echo "CURL_FAILED_WITHOUT_RESPONSE"
            fi
        } > "$dir/UPLOAD_ERROR.txt"
        FAILED=$((FAILED+1))
    fi
    rm -f "$payload" "$response" "$archive"
done
[ "$found" -eq 1 ] || { write_status NOTHING_TO_UPLOAD 'cloud_outbox is empty'; exit 0; }
if [ "$FAILED" -eq 0 ]; then write_status OK 'all queued sessions uploaded'; exit 0
else write_status PARTIAL 'failed sessions remain queued'; exit 10; fi
