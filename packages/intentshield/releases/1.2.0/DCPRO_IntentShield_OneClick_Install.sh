#!/bin/sh
# DCPRO IntentShield 1.2.0 Stable - network OneClick.
# Install KOReader through KPM; install verified ZenOS release; install local embedded IntentShield.
set -eu
ROOT=/mnt/us
LOG="$ROOT/GhostGuard_Reports/IntentGate/IntentShield_OneClick.log"
mkdir -p "$ROOT/documents" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
# Progress UI: stage count (not a guessed download percentage).
# FBInk is preferred; Kindle eips is a fallback. Neither is required to install.
FBINK=$(command -v fbink 2>/dev/null || :)
if [ -z "$FBINK" ]; then
    for b in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink /mnt/us/koreader/fbink /mnt/us/extensions/koreader/fbink; do
        if [ -x "$b" ]; then FBINK="$b"; break; fi
    done
fi
EIPS=$(command -v eips 2>/dev/null || :)
SCREEN_MODE=none
if [ -n "$FBINK" ] && "$FBINK" -c -S 2 -x 1 -y 1 -r 'DCPRO IntentShield' </dev/null >/dev/null 2>&1; then
    SCREEN_MODE=fbink
elif [ -n "$EIPS" ]; then
    "$EIPS" -c </dev/null >/dev/null 2>&1 || :
    SCREEN_MODE=eips
fi
line(){
    case "$SCREEN_MODE" in
        fbink) "$FBINK" -S 2 -x 1 -y "$1" -r "$2" </dev/null >/dev/null 2>&1 || :;;
        eips) "$EIPS" 1 "$1" "$(printf '%-44s' "$2")" </dev/null >/dev/null 2>&1 || :;;
    esac
    return 0
}
line 1 'DCPRO IntentShield'
line 2 '1.2.0 Stable + ZenFM'
# KOReader v2026.07.1 Kindle serial code mapping (positions 4-6).
model_from_code(){
    case "$1" in
        0PP|0T1|0T2|0T3|0T4|0T5|0T6|0T7|0TJ|0TK|0TL|0TM|0TN|102|103|16Q|16R|16S|16T|16U|16V) echo 'Kindle Paperwhite 4 (2018)';;
        10L|0WF|0WG|0WH|0WJ|0VB) echo 'Kindle Basic 2019 (10th gen)';;
        22D|25T|23A|2AQ|2AP|1XH|22C) echo 'Kindle Basic 2022';;
        A89|3L2|3L3|3L4|3L5|3L6|3KM) echo 'Kindle Basic 2024';;
        *) return 1;;
    esac
}
SERIAL=$(tr -d '\r\n' </proc/usid 2>/dev/null || :)
MODEL='Unsupported Kindle'
case "$SERIAL" in
    G???????????????)
        CODE=$(printf '%s' "$SERIAL" | cut -c4-6)
        MODEL=$(model_from_code "$CODE") || MODEL='Unsupported Kindle';;
esac
unset SERIAL
line 3 "$MODEL"
printf 'DETECTED MODEL: %s\n' "$MODEL"
line 4 '--------------------------------'
STEP=0
LABEL='Starting installer'
DONE=0
OWN_TMP=0
ERROR_MSG=''
KPM_WORKER=''
cleanup(){
    rc=$?
    trap - EXIT HUP INT TERM
    if [ -n "$KPM_WORKER" ]; then kpm_index_stop; fi
    if [ "$DONE" -ne 1 ]; then
        [ "$rc" -ne 0 ] || rc=1
        line 13 'INSTALL FAILED'
        line 14 "Step $STEP: $LABEL"
        line 15 "${ERROR_MSG:-See installer log for details}"
        line 16 'GhostGuard_Reports/IntentGate/'
        printf 'FAIL: step %s (%s), exit %s\n' "$STEP" "$LABEL" "$rc"
        [ "$SCREEN_MODE" = none ] || sleep 6
    fi
    if [ "$OWN_TMP" -eq 1 ] && [ -d "$T" ]; then rm -rf "$T"; fi
    exit "$rc"
}
trap cleanup EXIT
trap 'ERROR_MSG="Installation interrupted"; exit 130' HUP INT TERM
fail(){ ERROR_MSG="$*"; echo "FAIL: $*"; exit 1; }
stage(){
    STEP="$1"; LABEL="$2"
    bar=''; i=1
    while [ "$i" -le 9 ]; do
        if [ "$i" -lt "$STEP" ]; then bar="${bar}#"; elif [ "$i" -eq "$STEP" ]; then bar="${bar}>"; else bar="${bar}-"; fi
        i=$((i+1))
    done
    line 5 "[$bar] Step $STEP / 9"
    line 7 "$LABEL"
    line 9 'Working...'
    line 11 'Please keep Kindle powered on.'
    printf 'STEP %s/9: %s\n' "$STEP" "$LABEL"
}
# Poll the actual worker from the foreground. No heartbeat subprocess to kill/wait.
# A slow final sync is explicitly reported; do not pretend it completed or interrupt it.
run_busy(){
    download_file="$1"; shift
    "$@" &
    worker=$!
    elapsed=0
    while kill -0 "$worker" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed+1))
        if [ "$((elapsed % 5))" -eq 0 ]; then
            if [ -n "$download_file" ] && [ -f "$download_file" ]; then
                bytes=$(wc -c < "$download_file" 2>/dev/null || echo 0)
                kb=$((bytes/1024))
                line 9 "Working: ${elapsed}s | ${kb:-0} KB"
            else
                line 9 "Working: ${elapsed}s"
            fi
        fi
        if [ "$STEP" -eq 9 ] && [ "$elapsed" -eq 90 ] && [ "$download_file" = "" ]; then
            printf 'PENDING: sync still running after 90s (PID %s); do not reboot or unplug.\n' "$worker"
            line 7 'Storage still busy - not finished'
            line 11 'Do not reboot or disconnect.'
            line 13 'See log if this persists.'
        fi
    done
    status=0
    wait "$worker" || status=$?
    printf 'Worker exit: step %s, rc=%s, elapsed=%ss\n' "$STEP" "$status" "$elapsed"
    return "$status"
}
# Bounded metadata operations; never interrupt package installation or sync.
kpm_index_stop(){
    [ -n "$KPM_WORKER" ] || return 0
    if [ -f "$T/kpm-group.ready" ] && [ "$(cat "$T/kpm-group.ready")" = "$KPM_WORKER" ]; then
        kill -TERM "-$KPM_WORKER" 2>/dev/null || :
        sleep 3
        kill -KILL "-$KPM_WORKER" 2>/dev/null || :
    else
        kill -TERM "$KPM_WORKER" 2>/dev/null || :
        sleep 1
        kill -KILL "$KPM_WORKER" 2>/dev/null || :
    fi
    wait "$KPM_WORKER" 2>/dev/null || :
    KPM_WORKER=''
}
kpm_index_run(){
    limit="$1"; shift
    command -v setsid >/dev/null 2>&1 || { echo 'KPM timeout requires setsid'; return 125; }
    rm -f "$T/kpm-group.ready"
    setsid /bin/sh -c '
        ready=$1; shift
        ids=$(sed "s/^.*) //" /proc/$$/stat | awk "{print \$3,\$4}")
        [ "$ids" = "$$ $$" ] || exit 125
        printf "%s\n" "$$" > "$ready" || exit 125
        exec "$@"
    ' sh "$T/kpm-group.ready" "$@" &
    KPM_WORKER=$!
    elapsed=0
    while kill -0 "$KPM_WORKER" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed+1))
        if [ "$((elapsed % 5))" -eq 0 ]; then line 9 "Working: $elapsed / $limit sec"; fi
        if [ "$elapsed" -ge "$limit" ] && kill -0 "$KPM_WORKER" 2>/dev/null; then
            printf 'TIMEOUT: KPM metadata operation after %ss\n' "$elapsed"
            line 7 'KPM timeout - stopping'
            kpm_index_stop
            return 124
        fi
    done
    status=0
    wait "$KPM_WORKER" || status=$?
    KPM_WORKER=''
    rm -f "$T/kpm-group.ready"
    printf 'KPM metadata exit: rc=%s, elapsed=%ss\n' "$status" "$elapsed"
    return "$status"
}

stage 1 'Checking Kindle and tools'
[ "$MODEL" != 'Unsupported Kindle' ] || fail 'Unsupported Kindle model; no installation performed'
[ "$(id -u)" = 0 ] || fail "Run through root SH Integration"
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) fail "Exit KOReader first";; esac
done
command -v sha256sum >/dev/null || fail "sha256sum missing"
command -v unzip >/dev/null || fail "unzip missing"
command -v base64 >/dev/null || fail "base64 missing"
T="$ROOT/.intentshield-oneclick-$$"
mkdir "$T"
OWN_TMP=1
detect_ko(){
    KR=
    for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do
        if [ -f "$d/koreader.sh" ] && [ -d "$d/plugins" ]; then
            [ -z "$KR" ] || fail "Multiple KOReader roots"
            KR="$d"
        fi
    done
}
detect_ko
stage 2 'Checking KOReader and KPM'
if [ -z "$KR" ]; then
    KPM=
    for k in /var/local/kmc/bin/kpm /var/local/kmc/kindlehf/bin/kpm /var/local/kmc/kindlepw2/bin/kpm; do
        if [ -x "$k" ]; then KPM="$k"; break; fi
    done
    [ -n "$KPM" ] || fail "Install KPM first (;kpm)"
    if kpm_index_run 30 "$KPM" -y list-repo > "$T/kpm-repos.log" 2>&1; then cat "$T/kpm-repos.log"; else cat "$T/kpm-repos.log"; fail 'KPM list-repo failed'; fi
    repos=$(cat "$T/kpm-repos.log")
    case "$repos" in *kindlemodding*) ;; *) kpm_index_run 60 "$KPM" -y add-repo https://repo.kindlemodding.org/manifest.v2.json || fail 'KPM repository failed';; esac
    stage 3 'Updating KPM package index'
    if kpm_index_run 120 "$KPM" -y update; then :; else
        rc=$?
        case "$rc" in 124|125|126|127|1[3-9][0-9]|2[0-5][0-9]) fail 'KPM timeout/error; check Wi-Fi and KPM';;
        *) line 7 'KPM update failed - retrying once'; sleep 3; kpm_index_run 120 "$KPM" -y update || fail 'KPM update failed';; esac
    fi
    stage 4 'Downloading / installing KOReader'
    run_busy '' "$KPM" -y install koreader || fail "KOReader install"
    detect_ko
    [ -n "$KR" ] || fail "KOReader root not found"
else
    line 9 'KOReader already installed.'
    echo 'SKIP: KOReader already installed; KPM steps 3/4 skipped.'
fi
for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) fail "Exit KOReader first";; esac
done
# Compatibility checks use real installed versions, not the KPM package label.
version_at_least(){
    awk -v version="$1" -v major="$2" -v minor="$3" 'BEGIN {
        sub(/^v/,"",version); sub(/-[0-9]+-g[0-9a-f]+.*$/,"",version); n=split(version,v,".");
        if(n<2 || v[1]!~/^[0-9]+$/ || v[2]!~/^[0-9]+$/) exit 1;
        exit !((v[1]+0>major+0) || (v[1]+0==major+0 && v[2]+0>=minor+0))
    }'
}
lua_check(){
    check_file="$1"
    [ -x "$KR/luajit" ] || return 1
    (cd "$KR"; DCPRO_CHECK_FILE="$check_file" LD_LIBRARY_PATH="$KR/libs:$KR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$KR/luajit" -e 'assert(loadfile(os.getenv("DCPRO_CHECK_FILE")))')
}
# Each anchor must occur exactly once. Unknown layouts are never edited.
unique(){ [ "$(grep -Fxc "$2" "$1" || :)" = 1 ]; }
unique_fragment(){ [ "$(grep -Fc "$2" "$1" || :)" = 1 ]; }
prepare_gesture(){
    g="$1"; out="$2"
    [ -f "$g" ] || return 1
    if grep -Fq 'DCPRO_KOREADER_GESTURE_NIL_GUARD_V1' "$g"; then
        for mark in 'normalizeTouchCoordinates(self.current_tev, self.initial_tev)' 'DCPRO Gesture nil-guard dropped incomplete path frame' 'sane_touch_frame = normalizeTouchCoordinates'; do grep -Fq "$mark" "$g" || return 1; done
        cp "$g" "$out"; return
    fi
    [ "$(grep -c '^local Contact = {}' "$g" || :)" = 1 ] || return 1
    for anchor in 'function Contact:isTwoFingerTap(buddy_contact)' 'function Contact:getPath(simple, diagonal, initial_tev)' 'function Contact:isSwipe()' 'function GestureDetector:feedEvent(tevs)' '    initial_tev = initial_tev or self.initial_tev' '        local ges = contact.state(contact)'; do unique "$g" "$anchor" || return 1; done
    for anchor in 'local y_diff0 = math.abs(self.current_tev.y - self.initial_tev.y)' 'local y_diff = self.current_tev.y - initial_tev.y' 'function GestureDetector:dropContact(contact)'; do unique_fragment "$g" "$anchor" || return 1; done
    awk '
      /^local Contact = \{\}/ {
        print
        print "-- DCPRO_KOREADER_GESTURE_NIL_GUARD_V1"
        print "local function normalizeTouchCoordinates(current_tev, initial_tev)"
        print "    if not current_tev or not initial_tev then return false end"
        print "    if initial_tev.x == nil and current_tev.x ~= nil then initial_tev.x = current_tev.x end"
        print "    if initial_tev.y == nil and current_tev.y ~= nil then initial_tev.y = current_tev.y end"
        print "    if current_tev.x == nil and initial_tev.x ~= nil then current_tev.x = initial_tev.x end"
        print "    if current_tev.y == nil and initial_tev.y ~= nil then current_tev.y = initial_tev.y end"
        print "    return current_tev.x ~= nil and current_tev.y ~= nil and initial_tev.x ~= nil and initial_tev.y ~= nil"
        print "end"; next
      }
      /^function Contact:isTwoFingerTap\(buddy_contact\)$/ {
        print
        print "    if not buddy_contact or not normalizeTouchCoordinates(self.current_tev, self.initial_tev) or not normalizeTouchCoordinates(buddy_contact.current_tev, buddy_contact.initial_tev) or not self.current_tev.timev or not self.initial_tev.timev or not buddy_contact.current_tev.timev or not buddy_contact.initial_tev.timev then"
        print "        logger.warn(\"DCPRO Gesture nil-guard dropped incomplete two-finger tap frame\")"
        print "        return"
        print "    end"; next
      }
      /^function Contact:getPath\(simple, diagonal, initial_tev\)$/ { inpath=1; print; next }
      inpath && /^    initial_tev = initial_tev or self.initial_tev$/ {
        print
        print "    if not normalizeTouchCoordinates(self.current_tev, initial_tev) then"
        print "        logger.warn(\"DCPRO Gesture nil-guard dropped incomplete path frame\")"
        print "        return nil, 0"
        print "    end"; inpath=0; next
      }
      /^function Contact:isSwipe\(\)$/ {
        print
        print "    if not normalizeTouchCoordinates(self.current_tev, self.initial_tev) or not self.current_tev.timev or not self.initial_tev.timev then return end"; next
      }
      /^        local ges = contact.state\(contact\)$/ {
        print "        local sane_touch_frame = true"
        print "        if contact.initial_tev then sane_touch_frame = normalizeTouchCoordinates(contact.current_tev, contact.initial_tev) end"
        print "        local ges"
        print "        if sane_touch_frame then ges = contact.state(contact)"
        print "        elseif tev.id == -1 then self:dropContact(contact) end"; next
      }
      {print}
    ' "$g" > "$out" || return 1
    for mark in 'DCPRO_KOREADER_GESTURE_NIL_GUARD_V1' 'normalizeTouchCoordinates(self.current_tev, self.initial_tev)' 'DCPRO Gesture nil-guard dropped incomplete path frame' 'sane_touch_frame = normalizeTouchCoordinates'; do grep -Fq "$mark" "$out" || return 1; done
}
prepare_touchmenu(){
    g="$1"; out="$2"
    [ -f "$g" ] || return 1
    if grep -Fq 'DCPRO_KOREADER_TOUCHMENU_PAGE_GUARD_V1' "$g"; then
        [ "$(grep -Fc 'if self.page == nil or self.page_num == nil then' "$g" || :)" = 2 ] || return 1
        grep -Fq 'if nb == nil or self.page_num == nil then' "$g" || return 1
        cp "$g" "$out"; return
    fi
    for anchor in 'function TouchMenu:onNextPage()' 'function TouchMenu:onPrevPage()' 'function TouchMenu:onGotoPage(nb)'; do unique "$g" "$anchor" || return 1; done
    for anchor in 'return self:onGotoPage(self.page + 1)' 'return self:onGotoPage(self.page - 1)' 'if nb > self.page_num then'; do unique_fragment "$g" "$anchor" || return 1; done
    awk '
      /^function TouchMenu:onNextPage\(\)$/ { print "-- DCPRO_KOREADER_TOUCHMENU_PAGE_GUARD_V1"; print; print "    if self.page == nil or self.page_num == nil then return true end"; next }
      /^function TouchMenu:onPrevPage\(\)$/ { print; print "    if self.page == nil or self.page_num == nil then return true end"; next }
      /^function TouchMenu:onGotoPage\(nb\)$/ { print; print "    if nb == nil or self.page_num == nil then return true end"; next }
      {print}
    ' "$g" > "$out" || return 1
    [ "$(grep -Fc 'if self.page == nil or self.page_num == nil then' "$out" || :)" = 2 ] && grep -Fq 'if nb == nil or self.page_num == nil then' "$out"
}
apply_guards(){
    G="$KR/frontend/device/gesturedetector.lua"; M="$KR/frontend/ui/widget/touchmenu.lua"
    # Stage and syntax-check BOTH before modifying either. Back up actual bytes, including a previous version if necessary.
    prepare_gesture "$G" "$T/gesture.lua" || fail "GestureGuard: unrecognized KOReader source (not patched)"
    prepare_touchmenu "$M" "$T/touchmenu.lua" || fail "TouchMenuGuard: unrecognized KOReader source (not patched)"
    lua_check "$T/gesture.lua" && lua_check "$T/touchmenu.lua" || fail "KOReader LuaJIT syntax check failed (not patched)"
    if cmp -s "$G" "$T/gesture.lua" && cmp -s "$M" "$T/touchmenu.lua"; then echo 'PASS: KOReader guards already present'; return; fi
    GD="$ROOT/.dcpro_intentshield/core-backup-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$GD" || fail 'Create core backup'
    cp "$G" "$GD/gesturedetector.lua" && cp "$M" "$GD/touchmenu.lua" && cmp -s "$G" "$GD/gesturedetector.lua" && cmp -s "$M" "$GD/touchmenu.lua" || fail 'Core backup verification'
    printf '%s\n' "$KR" > "$GD/koreader-root.txt"
    printf '%s\n' "$KO_VERSION" > "$GD/version.txt"
    if ! mv -f "$T/gesture.lua" "$G" || ! mv -f "$T/touchmenu.lua" "$M"; then
        cp "$GD/gesturedetector.lua" "$G" && cp "$GD/touchmenu.lua" "$M" || fail "Core restore failed: $GD"
        fail 'Core guard commit failed; restored originals'
    fi
    echo "PASS: GestureGuard and TouchMenuGuard; backups $GD"
}
# GitHub REST pretty-printed JSON: exact asset name, digest and URL; reject ambiguity.
parse_zen_release(){
    awk '
      /^  "tag_name": / {x=$0; sub(/^  "tag_name": "/,"",x); sub(/",?$/,"",x); tag=x; tags++}
      /^  "(draft|prerelease)": / {if ($0 !~ /: false,?$/) bad=1; flags++}
      /^      "name": / {active=($0 ~ /^      "name": "zenos\.koplugin\.zip",?$/); if(active) names++}
      active && /^      "digest": / {x=$0; sub(/^      "digest": "sha256:/,"",x); sub(/",?$/,"",x); digest=x; hashes++}
      active && /^      "browser_download_url": / {x=$0; sub(/^      "browser_download_url": "/,"",x); sub(/",?$/,"",x); url=x; urls++}
      END { if(bad || flags!=2 || tags!=1 || names!=1 || hashes!=1 || urls!=1 || length(digest)!=64 || digest!~/^[0-9a-f]+$/ || tag!~/^v[0-9]+\.[0-9]+\.[0-9]+$/ || url!="https://github.com/xZenLabs/zen-os/releases/download/"tag"/zenos.koplugin.zip") exit 1; print tag; print digest; print url }
    ' "$1"
}
zen_version(){
    awk 'BEGIN {n=0} /^[[:space:]]*version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+",?[[:space:]]*$/ {v=$0; sub(/^[^"]*"/,"",v); sub(/".*/,"",v); n++} END {if(n!=1) exit 1; print v}' "$1/_meta.lua"
}
check_zen_capabilities(){
    z="$1"
    [ -f "$z/main.lua" ] && [ -f "$z/config/defaults.lua" ] && [ -f "$z/fonts/readerly/Readerly_R-Regular.ttf" ] && [ -f "$z/icons/settings_lightning_bolt.svg" ] && [ -f "$z/modules/menu/app_launcher/plugin_scan.lua" ] && grep -Fq '__menu_submenu' "$z/modules/menu/app_launcher/plugin_scan.lua"
}
KO_VERSION=$(head -n 1 "$KR/git-rev" 2>/dev/null) || fail "KOReader git-rev missing"
version_at_least "$KO_VERSION" 2026 3 || fail "ZenOS requires KOReader 2026.03 or newer"
echo "Actual KOReader version: $KO_VERSION"
stage 5 'Checking KOReader stability guards'
apply_guards
stage 6 'Checking / downloading ZenOS' 
P="$KR/plugins"
[ ! -d "$P/zen_ui.koplugin" ] || fail "Migrate old Zen UI using official Zen UI update before continuing"
[ ! -d "$P/projecttitle.koplugin" ] || fail "Disable Project: Title before continuing"
[ ! -d "$P/simpleui.koplugin" ] || fail "Disable legacy SimpleUI before continuing"
if [ ! -d "$P/zenos.koplugin" ]; then
    # Resolve latest stable at install time; no fixed version or fixed ZIP URL.
    API=https://api.github.com/repos/xZenLabs/zen-os/releases/latest
    if command -v curl >/dev/null; then
        run_busy '' curl -fLSs --connect-timeout 20 --max-time 120 -H 'Accept: application/vnd.github+json' "$API" -o "$T/zen-release.json" || fail 'ZenOS release metadata'
    else
        run_busy '' wget -O "$T/zen-release.json" "$API" || fail 'ZenOS release metadata'
    fi
    parse_zen_release "$T/zen-release.json" > "$T/zen-release.txt" || fail 'ZenOS release metadata / SHA256 unavailable'
    ZTAG=$(sed -n '1p' "$T/zen-release.txt"); ZSHA=$(sed -n '2p' "$T/zen-release.txt"); URL=$(sed -n '3p' "$T/zen-release.txt")
    version_at_least "$ZTAG" 4 3 || fail 'ZenOS stable release below 4.3'
    echo "Selected ZenOS stable: $ZTAG"
    if command -v curl >/dev/null; then
        run_busy "$T/zen.zip" curl -fLSs --connect-timeout 20 --max-time 900 "$URL" -o "$T/zen.zip" || fail "ZenOS download"
    else
        run_busy "$T/zen.zip" wget -O "$T/zen.zip" "$URL" || fail "ZenOS download"
    fi
    stage 7 'Verifying / installing ZenOS'
    printf '%s  %s\n' "$ZSHA" "$T/zen.zip" | sha256sum -c - || fail 'ZenOS checksum'
    run_busy '' unzip -q "$T/zen.zip" -d "$T/zen" || fail "ZenOS extraction"
    Z="$T/zen/zenos.koplugin"
    check_zen_capabilities "$Z" || fail 'ZenOS capability mismatch; existing files not replaced'
    ZVER=$(zen_version "$Z") || fail 'ZenOS _meta version missing'
    [ "v$ZVER" = "$ZTAG" ] || fail 'ZenOS version differs from release tag'
    [ "$ZVER" = 4.3.2 ] || fail "1.2.0 Stable requires ZenOS 4.3.2 for fresh installation"
    [ -f "$Z/icons/zenfm.svg" ] || fail "ZenFM icon missing"
    D="$Z/config/defaults.lua"
    # Exact old default schema only. Do not silently write partial settings on future schemas.
    for anchor in 'local library_font_default = FontLanguage.supportsBundledFonts()' '    and LibraryFontPath.BUNDLED_DEFAULT or "default"' '    navbar = {' '            "books", "authors", "series", "languages", "home", "continue", "favorites",' '    library_font = {' '        font_face = library_font_default,' '        font_size = 18,'; do unique "$D" "$anchor" || fail 'ZenOS defaults schema changed; not patched'; done
    if grep -Fq 'custom_tabs =' "$D"; then fail 'ZenOS custom tab defaults changed; not patched'; fi
    echo "Verified ZenOS $ZVER and Navbar schema"
    # Fresh-install defaults only; no modifications to existing user preferences.
    awk '
      /local library_font_default = FontLanguage.supportsBundledFonts\(\)/ {print "local library_font_default = FontLanguage.supportsBundledFonts()"; getline; print "    and \"fonts/readerly/Readerly_R-Regular.ttf\" or \"default\""; next}
      /^    navbar = \{/ {n=1; print; print "        custom_tabs = {{id = \"ct_1\", type = \"plugin\", label = \"DCPRO IntentShield™\", plugin_title = \"DCPRO IntentShield™\", icon = \"settings_lightning_bolt\", plugin = {key = \"dcprointentgate\", method = \"__menu_submenu\"}}, {id = \"ct_2\", type = \"plugin\", label = \"ZenFM\", plugin_title = \"ZenFM\", icon = \"zenfm\", plugin = {key = \"zenfm\", method = \"__menu_submenu\"}}},"; print "        next_custom_id = 2,"; next}
      n && /show_tabs = \{/ {print; print "            ct_1 = true,"; print "            ct_2 = true,"; next}
      n && /^( +)(continue|favorites|authors|series) = true,/ {sub(/true/,"false"); print; next}
      n && /"books", "authors", "series", "languages", "home", "continue", "favorites",/ {print "            \"books\", \"home\", \"ct_1\", \"ct_2\","; next}
      n && /^    \},/ {n=0}
      {print}
    ' "$Z/config/defaults.lua" > "$Z/config/defaults.lua.dcpro"
    grep -Fq 'key = "dcprointentgate"' "$Z/config/defaults.lua.dcpro" || fail "Navbar anchor"
    grep -Fq 'fonts/readerly/Readerly_R-Regular.ttf' "$Z/config/defaults.lua.dcpro" || fail "Font anchor"
    grep -Fq '"books", "home", "ct_1", "ct_2",' "$Z/config/defaults.lua.dcpro" || fail 'Navbar order anchor'
    lua_check "$Z/config/defaults.lua.dcpro" || fail 'ZenOS defaults syntax check'
    mv "$Z/config/defaults.lua.dcpro" "$Z/config/defaults.lua"
    mv "$Z" "$P/zenos.koplugin" || fail "ZenOS install"
    DCPRO_FRESH_ZEN=1
    Z="$P/zenos.koplugin"
else
    Z="$P/zenos.koplugin"
    ZVER=$(zen_version "$Z") || fail 'Existing ZenOS version unknown'
    version_at_least "$ZVER" 4 3 || fail 'Existing ZenOS below 4.3; upgrade using upstream before retry'
    check_zen_capabilities "$Z" || fail 'Existing ZenOS capability mismatch; not overwritten'
    echo "Existing ZenOS $ZVER preserved; configure Navbar/font through Zen Settings if desired"
fi
# ZenFM addon: pinned upstream bundle, no daemon startup; no modification of IntentShield.
install_zenfm(){
    ZF="$P/zenfm.koplugin"
    [ -f "$Z/icons/zenfm.svg" ] && [ -f "$Z/modules/menu/app_launcher/plugin_scan.lua" ] && grep -Fq '__menu_submenu' "$Z/modules/menu/app_launcher/plugin_scan.lua" || fail 'ZenOS navbar capability missing'
    [ ! -L "$ZF" ] || fail 'Unexpected ZenFM symlink'
    if [ -d "$ZF" ]; then
        [ -f "$ZF/main.lua" ] && [ -f "$ZF/_meta.lua" ] || fail 'Existing ZenFM incomplete; not overwritten'
        echo 'SKIP: existing ZenFM retained (including settings).'
    else
        [ ! -e "$ZF" ] || fail 'Unexpected ZenFM path'
        command -v curl >/dev/null 2>&1 || fail 'ZenFM download requires curl'
        mkdir "$T/zenfm"
        run_busy "$T/zenfm.zip" curl -fLSs --connect-timeout 20 --max-time 300 'https://github.com/xZenLabs/zen-fm/releases/download/v1.2.2/ZenFM-koreader-ereader-1.2.2.zip' -o "$T/zenfm.zip" || fail 'ZenFM download; check Wi-Fi'
        printf '%s  %s\n' '9e3add7810da6dacda1dc4b448872073060d7297a5e6a1a00332f72e67305bdd' "$T/zenfm.zip" | sha256sum -c - || fail 'ZenFM SHA256 mismatch'
        unzip -q "$T/zenfm.zip" -d "$T/zenfm" || fail 'ZenFM extraction'
        F="$T/zenfm/zenfm.koplugin"
        for file in main.lua _meta.lua zenfm_daemon.lua zenfm_settings.lua backend/zenfm-hf backend/zenfm-sf supervisor.sh LICENSE; do [ -f "$F/$file" ] || fail "ZenFM missing $file"; done
        grep -Eq 'version[[:space:]]*=[[:space:]]*"1\.2\.2"' "$F/_meta.lua" || fail 'ZenFM version mismatch'
        lua_check "$F/main.lua" && lua_check "$F/_meta.lua" || fail 'ZenFM Lua syntax'
        chmod +x "$F/backend/zenfm-hf" "$F/backend/zenfm-sf" "$F/supervisor.sh" "$F/log-prefix.sh" || fail 'ZenFM executable permissions'
        mv "$F" "$ZF" || fail 'ZenFM install'
        echo 'PASS: ZenFM 1.2.2 official archive verified and installed'
        # Only seed a new state file; never overwrite credentials or existing settings.
        S="$KR/settings/ZenFM"
        if [ ! -e "$S" ] && [ ! -L "$S" ]; then
            mkdir -p "$S" || fail 'ZenFM settings directory'
            (umask 077; set -C; cat > "$S/settings.lua" <<'EOF'
return { settings_version=4, port=54321, insecure_http=false, advanced_root=false,
 custom_root="/mnt/us/documents", auto_stop_minutes=5, auto_stop_last_minutes=5,
 show_qr_code=true, beta_updates=false }
EOF
            ) || fail 'ZenFM initial settings'
        else
            echo 'SKIP: existing ZenFM state preserved.'
        fi
    fi
}
pin_zenfm(){
    # Only edit the verified 4.3.2 settings schema. On unknown layout, leave preferences untouched.
    CFG="$KR/settings/ZenOS/config.lua"
    if [ "$ZVER" != 4.3.2 ]; then echo 'SKIP: unsupported ZenOS version for navbar; add manually'; return 0; fi
    if [ ! -f "$CFG" ]; then
        if [ "${DCPRO_FRESH_ZEN:-0}" = 1 ]; then echo 'PASS: ZenFM in fresh defaults'; return 0; fi
        echo 'SKIP: ZenOS config not initialized; add tab manually after first launch'; return 0
    fi
    if [ -L "$CFG" ]; then echo 'SKIP: config symlink; add tab manually'; return 0; fi
    cat > "$T/navbar.lua" <<'DCPRO_NAV_LUA'
-- Offline migration of ZenOS 4.3.2 persisted settings. No modules or global APIs in config chunk.
local src,dst=assert(arg[1]),assert(arg[2])
local f=assert(io.open(src,'rb')); local data=f:read('*a'); f:close()
assert(#data<4194304 and data:byte(1)~=27,'unexpected config')
local loader=loadstring or load
local chunk,err
if setfenv then chunk,err=loader(data,'@config'); assert(chunk,err); setfenv(chunk,{})
else chunk,err=load(data,'@config','t',{}); assert(chunk,err) end
local ticks=0
debug.sethook(function() ticks=ticks+1; if ticks>1000 then error('config instruction limit') end end,'',1000)
local ok,cfg=pcall(chunk); debug.sethook(); assert(ok and type(cfg)=='table','invalid config')
local n=cfg.navbar; assert(type(n)=='table' and type(n.tab_order)=='table' and type(n.show_tabs)=='table','unsupported navbar schema')
assert(n.layout_version==2,'legacy navbar: open ZenOS once first')
if cfg.features and cfg.features.navbar==false then print('SKIP: navbar disabled'); return end
n.custom_tabs=n.custom_tabs or {}; assert(type(n.custom_tabs)=='table')
local ids,order={},{}; local max=tonumber(n.next_custom_id) or 0
assert(max>=0 and max<1000000 and max%1==0)
local zen
for _,v in ipairs(n.custom_tabs) do
  assert(type(v)=='table' and type(v.id)=='string' and not ids[v.id],'invalid custom tab')
  ids[v.id]=true; max=math.max(max,tonumber(v.id:match('^ct_(%d+)$')) or 0)
  if v.type=='plugin' and type(v.plugin)=='table' and v.plugin.key=='zenfm' then zen=zen or v end
end
local enabled=0
for _,id in ipairs(n.tab_order) do
  assert(type(id)=='string' and not order[id],'invalid tab order'); order[id]=true
  if n.show_tabs[id]==true then enabled=enabled+1 end
end
if zen and order[zen.id] and n.show_tabs[zen.id]==true then print('PASS: ZenFM already visible'); return end
if enabled>=7 then print('SKIP: seven visible tabs; use Zen Settings to free a slot'); return end
if not zen then
  repeat max=max+1 until not ids['ct_'..max] and not order['ct_'..max] and n.show_tabs['ct_'..max]==nil
  zen={id='ct_'..max,type='plugin',label='ZenFM',plugin_title='ZenFM',icon='zenfm',plugin={key='zenfm',method='__menu_submenu'}}
  n.custom_tabs[#n.custom_tabs+1]=zen; n.next_custom_id=max
end
if not order[zen.id] then n.tab_order[#n.tab_order+1]=zen.id end
n.show_tabs[zen.id]=true
-- Serialize data only, not functions or metatables; keep every unrelated setting.
local seen={}
local function dump(v,depth)
  assert(depth<100,'config too deep')
  local t=type(v)
  if t=='string' then return string.format('%q',v) end
  if t=='boolean' then return tostring(v) end
  if t=='number' then assert(v==v and math.abs(v)<math.huge); return string.format('%.17g',v) end
  assert(t=='table' and not seen[v] and not getmetatable(v),'unsupported config value')
  seen[v]=true; local keys={}
  for k in pairs(v) do assert(type(k)=='string' or type(k)=='number' or type(k)=='boolean'); keys[#keys+1]=k end
  table.sort(keys,function(a,b) if type(a)==type(b) and type(a)~='boolean' then return a<b end; return type(a)..tostring(a)<type(b)..tostring(b) end)
  local parts={'{\n'}
  for _,k in ipairs(keys) do parts[#parts+1]=string.rep(' ',depth+1)..'['..dump(k,depth+1)..']='..dump(v[k],depth+1)..',\n' end
  parts[#parts+1]=string.rep(' ',depth)..'}'; seen[v]=nil; return table.concat(parts)
end
local serialized='-- ZenOS settings: DCPRO ZenFM navbar migration\nreturn '..dump(cfg,0)..'\n'
local out=assert(io.open(dst,'wb')); assert(out:write(serialized)); assert(out:close()); print('PASS: ZenFM navbar appended')
DCPRO_NAV_LUA
    if (cd "$KR"; LD_LIBRARY_PATH="$KR/libs:$KR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$KR/luajit" "$T/navbar.lua" "$CFG" "$T/navbar.new"); then
        if [ -f "$T/navbar.new" ]; then
            lua_check "$T/navbar.new" || fail 'ZenOS navbar syntax check'
            backup="$ROOT/.dcpro_intentshield/zenos-navbar-$(date +%Y%m%d-%H%M%S)-$$.lua.bak"
            mkdir -p "$ROOT/.dcpro_intentshield"
            (umask 077; cp "$CFG" "$backup") && cmp -s "$CFG" "$backup" || fail 'ZenOS settings backup'
            mv "$T/navbar.new" "$CFG" || fail 'ZenOS navbar commit'
            echo "PASS: navbar backup $backup"
        fi
    else
        echo 'WARN: navbar migration refused; existing settings untouched; add ZenFM manually'
    fi
}

for f in /proc/[0-9]*/cmdline; do
    [ -r "$f" ] || continue
    v=$(tr '\000' ' ' < "$f" 2>/dev/null || :)
    case "$v" in *luajit*reader.lua*) fail "Exit KOReader first";; esac
done
stage 8 'Installing DCPRO IntentShield'
if [ -d "$P/dcghostguardpro.koplugin" ]; then
    echo 'WARN: legacy GhostGuard present; disable it before enabling IntentShield Global Shield.'
fi
# Payload is appended by build_oneclick.py. No network download of IntentShield itself.
sed '1,/^__DCPRO_PAYLOAD_BELOW__$/d' "$0" | base64 -d > "$T/payload.zip"
unzip -q "$T/payload.zip" -d "$T/payload"
B="$T/payload/COPY_TO_KINDLE_ROOT"
TOOLS="$ROOT/.dcpro_intentshield/tools"
SRC_TOOLS="$B/.dcpro_intentshield/tools"
[ -f "$SRC_TOOLS/GhostGuard_IntentGate_INSTALL.tool" ] || fail "Invalid embedded payload"
# Store technical scripts outside the visible library, with a non-SH suffix.
mkdir -p "$ROOT/GhostGuardIntentTrial" "$TOOLS"
cp -R "$B/GhostGuardIntentTrial/." "$ROOT/GhostGuardIntentTrial/"
for f in "$SRC_TOOLS/"*.tool; do cp "$f" "$TOOLS/"; cmp "$f" "$TOOLS/$(basename "$f")"; done
run_busy '' /bin/sh "$TOOLS/GhostGuard_IntentGate_INSTALL.tool" || fail "IntentShield install"
# Archive only the eight known historical launcher filenames, after install succeeds.
ARCHIVE="$ROOT/.dcpro_intentshield/legacy-documents-$(date +%Y%m%d-%H%M%S)-$$"
for name in GhostGuard_IntentGate_INSTALL GhostGuard_IntentGate_REMOVE GhostGuard_IntentGate_ROLLBACK IntentShield_BOOT_PROBE IntentShield_DISABLE_AUTOBOOT IntentShield_ENABLE_AUTOBOOT IntentShield_REPLACE_LEGACY IntentShield_RESTORE_LEGACY; do
    old="$ROOT/documents/$name.sh"
    if [ -f "$old" ]; then
        mkdir -p "$ARCHIVE"
        mv "$old" "$ARCHIVE/$name.sh.bak" || fail "Archive old launcher: $name"
        echo "Archived old launcher: $name"
    fi
done
stage 9 'Verifying installed files'
(cd "$P/dcprointentgate.koplugin" && sha256sum -c "$ROOT/GhostGuardIntentTrial/SHA256SUMS") || fail "Installed plugin checksum mismatch"
echo 'PASS: installed plugin files verified'
line 7 'Preparing Smart Update'
# No unknown launcher modifications; preserve a backup. The update hook runs only before reader.lua.
cp "$SRC_TOOLS/IntentShield_UPDATE_RC.pub" "$TOOLS/IntentShield_UPDATE_RC.pub" || fail 'Update public key copy'
if grep -Fq 'DCPRO_SMART_UPDATE_HOOK_V1' "$KR/koreader.sh"; then
    echo 'Smart Update hook already present; retained'
elif [ "$(grep -Fxc '    ./reader.lua "$@" >>crash.log 2>&1' "$KR/koreader.sh" || :)" = 1 ]; then
    cp "$KR/koreader.sh" "$ROOT/.dcpro_intentshield/koreader.sh.pre-smart-update-$(date +%Y%m%d-%H%M%S)-$$" || fail 'Launcher backup'
    awk '
      $0 == "    ./reader.lua \"$@\" >>crash.log 2>&1" {
        print "    # DCPRO_SMART_UPDATE_HOOK_V1"
        print "    if [ -x /mnt/us/.dcpro_intentshield/tools/IntentShield_UPDATE.tool ]; then"
        print "        /bin/sh /mnt/us/.dcpro_intentshield/tools/IntentShield_UPDATE.tool apply \"$(pwd -P)\" || :"
        print "    fi"
      } {print}
    ' "$KR/koreader.sh" > "$T/koreader.new"
    grep -Fq 'DCPRO_SMART_UPDATE_HOOK_V1' "$T/koreader.new" && sh -n "$T/koreader.new" || fail 'Launcher hook verification'
    chmod +x "$T/koreader.new"; mv "$T/koreader.new" "$KR/koreader.sh" || fail 'Launcher hook install'
else
    echo 'WARN: unknown launcher; Smart Update unavailable until compatible OneClick install'
fi
chmod +x "$TOOLS/IntentShield_UPDATE.tool" || fail 'Update tool permissions'
line 7 'Installing / checking ZenFM' 
install_zenfm
line 7 'Pinning ZenFM in navigation'
pin_zenfm
BOOT_STATUS='Auto Boot: off'
# Do not alter the Global Shield rescue marker. Disable only system Auto Boot.
if [ -L "$ROOT/DISABLE_INTENTSHIELD_BOOT" ] || [ -L "$ROOT/ENABLE_INTENTSHIELD_BOOT" ]; then fail 'Unexpected boot marker type'; fi
if [ -e "$ROOT/DISABLE_INTENTSHIELD_BOOT" ] && [ ! -f "$ROOT/DISABLE_INTENTSHIELD_BOOT" ]; then fail 'Unexpected boot marker type'; fi
if [ -e "$ROOT/ENABLE_INTENTSHIELD_BOOT" ] && [ ! -f "$ROOT/ENABLE_INTENTSHIELD_BOOT" ]; then fail 'Unexpected boot marker type'; fi
touch "$ROOT/DISABLE_INTENTSHIELD_BOOT" || fail 'Disable Auto Boot'
rm -f "$ROOT/ENABLE_INTENTSHIELD_BOOT" || fail 'Disable Auto Boot marker'
# Delete only our temporary installer staging directory before the final flush.
# Existing plugin backups and recovery markers remain untouched.
[ "$OWN_TMP" -eq 1 ] && [ -d "$T" ] || fail "Temporary installer path missing"
rm -rf "$T"
OWN_TMP=0
line 7 'Saving changes to storage'
echo "START final sync: $(date)"
run_busy '' sync || fail "Saving changes"
echo "END final sync: $(date)"
# Finalization is parsed as one function before it unlinks the running script.
# Do not source this installer. Only delete the exact running SH in documents.
remove_running_installer(){
    original=$1
    dir=$(CDPATH='' cd -P "$(dirname "$original")" && pwd -P) || return 1
    docs=$(CDPATH='' cd -P "$ROOT/documents" && pwd -P) || return 1
    name=$(basename "$original")
    [ "$dir" = "$docs" ] || return 1
    case "$name" in *.sh) ;; *) return 1;; esac
    path="$dir/$name"
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    grep -Fq '# DCPRO IntentShield 1.2.0 Stable - network OneClick.' "$path" || return 1
    grep -Fxq '__DCPRO_PAYLOAD_BELOW__' "$path" || return 1
    rm -f "$path" && [ ! -e "$path" ] || return 1
    printf 'Removed completed installer: %s\n' "$path"
}
launch_koreader(){
    # Independent session where available; no restart, framework-stop or respawn.
    # Wait briefly for the SH Integration UI to finish before starting KOReader.
    launch_log="$ROOT/GhostGuard_Reports/IntentGate/launch.log"
    launcher='sleep 4
        kr=$1
        printf "START KOReader: %s\n" "$(date)"
        cd "$kr" || exit 1
        for f in /proc/[0-9]*/comm; do
            [ -r "$f" ] || continue
            IFS= read -r comm < "$f" || continue
            case "$comm" in luajit*)
                cmd=$(tr "\000" " " < "${f%/comm}/cmdline" 2>/dev/null || :)
                case "$cmd" in *reader.lua*) echo "SKIP: KOReader already running"; exit 0;; esac;;
            esac
        done
        unset KOREADER_DIR
        rc=0
        /bin/sh "$kr/koreader.sh" || rc=$?
        printf "END KOReader launcher: rc=%s (%s)\n" "$rc" "$(date)"
        exit "$rc"'
    if command -v setsid >/dev/null 2>&1; then
        setsid /bin/sh -c "$launcher" dcpro-launch "$KR" </dev/null >>"$launch_log" 2>&1 &
    elif command -v nohup >/dev/null 2>&1; then
        nohup /bin/sh -c "$launcher" dcpro-launch "$KR" </dev/null >>"$launch_log" 2>&1 &
    else
        (trap '' HUP; exec /bin/sh -c "$launcher" dcpro-launch "$KR") </dev/null >>"$launch_log" 2>&1 &
    fi
    printf 'KOReader launch scheduled: PID %s; see launch.log\n' "$!"
}
# Opt in to the existing licensed Global Shield startup path, not system Auto Boot.
# The plugin checks the RSA v4 license, device, orientation and API compatibility
# at actual startup. A USB rescue marker or legacy installation takes precedence.
configure_auto_shield(){
    AUTO_STATUS='Auto Shield: check / sync online'
    marker="$ROOT/ENABLE_INTENTSHIELD_GLOBAL"
    if [ -e "$ROOT/DISABLE_INTENTGATE" ]; then
        echo 'AUTO SHIELD: skipped; USB recovery marker present; left all markers unchanged.'
        AUTO_STATUS='Auto Shield: USB recovery'
        return 0
    fi
    if [ -d "$KR/plugins/dcghostguardpro.koplugin" ] || [ -e "$ROOT/ENABLE_GHOSTGUARD_ZEN_BOOT" ]; then
        echo 'AUTO SHIELD: skipped new opt-in; legacy GhostGuard present; existing markers unchanged.'
        AUTO_STATUS='Auto Shield: legacy detected'
        return 0
    fi
    if [ -L "$marker" ] || { [ -e "$marker" ] && [ ! -f "$marker" ]; }; then
        echo 'AUTO SHIELD: refused unexpected marker type.'
        AUTO_STATUS='Auto Shield: marker error'
        return 0
    fi
    if [ ! -f "$marker" ]; then
        if ! (umask 077; set -C; : > "$marker"); then
            echo 'AUTO SHIELD: marker creation failed; use IntentShield menu.'
            AUTO_STATUS='Auto Shield: enable manually'
            return 0
        fi
    fi
    echo 'AUTO SHIELD: enabled request; runtime license/device validation required; Auto Boot unchanged.'
    return 0
}
finish_install(){
    # This stage is reached only after plugin checksum verification and successful sync.
    DONE=1
    echo 'SUCCESS: installation verified; Auto Boot disabled.'
    line 5 '[#########] 9 / 9 COMPLETE'
    line 7 'INSTALL SUCCESSFUL'
    if [ ! -r "$KR/koreader.sh" ] || [ ! -f "$KR/plugins/zenos.koplugin/main.lua" ]; then
        echo 'WARN: launch preflight failed; installer kept.'
        line 9 'Open KOReader manually.'
        line 11 'Installer kept; see log.'
        [ "$SCREEN_MODE" = none ] || sleep 5
        return 0
    fi
    configure_auto_shield
    if remove_running_installer "$0"; then
        line 9 'Installer removed.'
    else
        echo 'WARN: installer not removed (not a regular SH in documents, or deletion failed).'
        line 9 'Remove installer manually.'
    fi
    line 11 'Open KOReader manually.'
    line 13 "$AUTO_STATUS"
    line 15 "$BOOT_STATUS"
    echo "SKIP: automatic KOReader launch disabled in 1.2.0 Stable."
    return 0
}
finish_install
exit 0
__DCPRO_PAYLOAD_BELOW__
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
T9gYuN0Du+WyjK2R/UTHNKyZVUUeZSwQw2m53oiqaAyRr4QECDiOLCqu6f0kMta76nQ910951rF7
+xrrmnNAKwIulPpViLfmyIaXSZA3gjtSnysookQwQA0qN2QKu5zrF6BrPIGfRkK6u6vL/nXKlWle
CJUbqDDVGU+Z4DdxAzoNDxx9FmMfinKQnnCQOjtVKZTMR1/7NQI3TZyVAMpDNC6YG7q3zW/NtMm8
5m3zU3N56TUaFIs8w48Hlrmqq0uLakEbmJASvOazai+gpVBdIxzjnOuvyHJZ+Q5nwOurDhzWQ47z
kWYJx+rh5ZCD5o6X6bkHVXAoRARflgFYBVyWzW3d98t0WsT8kDH5A1BLAwQUAAAACADSK3xdEdrZ
1ncAAACUAAAASgAAAENPUFlfVE9fS0lORExFX1JPT1QvLmRjcHJvX2ludGVudHNoaWVsZC90b29s
cy9JbnRlbnRTaGllbGRfQk9PVF9QUk9CRS50b29sLc1LDsIwDATQfU5h1DX1MSo2LBAXcBujREqc
YjuquD3hs56ZN9MJ1yxoKUxwbaCtOTxyYXuZc4VDs7PNcGOKsHVVlk+u9SBlIIlQqMuWWGFXVn72
bN9F+LOAVRy74ZKa+dJJ40V8KHfNVHAdf+cfMY/yrm3l8AZQSwMEFAAAAAgA0it8XaW3n29tAQAA
owIAAFAAAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50
ZW50U2hpZWxkX0RJU0FCTEVfQVVUT0JPT1QudG9vbI1S32vCMBB+z19xy4ZuDzXbHicKiqWriIJ2
MBhDYnOuwTYpSeom+McvVfwBk21HXvLdl+++u8v1FVtIxWxGLDoIsCLTySTpsEI5VllSrIQ0EJRA
b2qcRZm2Lqq4EfMplto4y2LlULmIO6QEvzCFbvc/ZLbQ2gVSWcfzvJXrDwqP3cYDcbpKs0O5QTzr
9UfhPB4n4TiZPcfhaDDv+wy9zIh6SUiJKSBYHgjh+A+FS4RoNOn3RpQMOwxdyqrSuzSOibQ02nuu
e7CZxFwEdRetVKslkUt485q3UkBQ3VHowD28Q6Ph0Z2bId1f06KEwO6BH4Pazycxkue/VqM7JV0U
XPlya/DrMj4HXSZwzVSV521wGSoCPryzQ958nuF1OMNLaB7T+kxhtw/YbuGpCeFrnBzfHOY7pO2T
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
x5B+8wEAAHECAABIAAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rv
b2xzL0ludGVudFNoaWVsZF9VUERBVEVfUkMucHViZZK5cqNAAAVzvsI55UICSYhggwEGGE6JGzIO
gzDHcCP4+rU33Y5e9Uv78/MHHsrI/Hh4vI6EDw1Gv+6TMBDi8Tcw+bIeXnUlc9uJB08oAWAJILqD
378qtZ8NQWOsHh6xjXTHXRTX80amIBJLHdMBDzJ1VWLQFHVF62r15BWs9VIfu1AxI9+pk+xxz2cR
7Zh8fZdBaqKwEie4U4Rw42KsTAHTyrrtPpxOSjbI8puzJXeJptKi3oV0o/3NUS25XxbfGQFebhzb
3mfma5OIPKS35FwXMTqKTnvtNtxU7J9KvxJr1YVSf+yzdn3lXlZX4+URH/gt7rekQSuZCbW1EAHM
Y3EJW5M9ibQAkBn16modh1HbglG+7cd7FLIb2+KI64J+JM9bc5a+63lmVESG4Uhwh8xunda3b/1i
XvNkJGcVMvnadbfJo/xCevIGbMNyiUw9emlnXV45Za+s1Pti1Xe8EfsauI51vxkkPeVAEyfSpg99
LgoePTE9LsJ5gMoy8CiV3IYzrrm9BGyTTiuHjLxtOoI7ZcMFmn5wcJc0Z+Orq6Z6URSDdp73qfly
6x4XaW2cUpsew41GncRSURqcT1ddEqWY8FaU4Tm6lPleNkz1krQjFq25ycRdWxvPepD3SZKp6EJp
DCgNHgD4h/iXEDTF/6r6C1BLAwQUAAAACADSK3xdpnBVC4QAAACwAAAAOQAAAENPUFlfVE9fS0lO
RExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL0JPT1RfU0hBMjU2U1VNUxXN2w2DMAwAwP9O
wQIgP2MyTnBsgYSgKnT/0gXuhLR2oJpWipF5N2XoUq00xM4R7kqyKHiLWhHBBEGCKqYU02UYlvO8
x719D1+na30RtFnhUQkjugkzZqZlmHMtMznSDGnaWUOgSFiNfNgCzEW5DUP39+cct+OO477WLfY+
/o/JzyNfP1BLAwQUAAAACABlLHxd4OlEgE0EAAB/BwAANAAAAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL1NIQTI1NlNVTVNllVtuWzkQRP+9Cm0gDtkPNrkao9lsOsLY
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
5qRJ5XDeg6r8B6F7shzBb3vrPTVfn9TsvSwpT+wylKCToUgeJQF7WofVS17HWJ6N+L045aBpZmQG
bWaPzDjs/w+gVNmyBudd4vHcQoEyYaGK1+KksD6vqkKE8m9QSwMEFAAAAAgA0it8XRd7Ih74AAAA
rwEAAEYAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byby1p
bnRlbnRzaGllbGQtYm9vdC5jb25mlZDBbsIwEETv+YppihCoCoYjRT21FeqJqvRUxMHEm9qqY0f2
hqQSH1+T9AfwxbMe+83I93jtGwqmJsfSPuKcdPULWXIrLSLLwG0DOicb3iHN38SoTKg7GWiRKYpl
MA2bZOYvz+8fO7w5Trf32pBV6Q0VUXvGF7ndHla2rtQU8mxAX5GDIIUqyJo6H36ykZghLfO0HPZO
G0s4IJ+YHIVlrJc4YjpNR3coKojasWij2GofedvKoMYWn8FIK07eczFGL6LGcQPlB+wYMZnNzMNq
Pt8gWqIGq8FTqfogDrcH4HIB9YYxtqeeSoiTcSKZN5GuY0ZO4f9P/gBQSwMEFAAAAAgAIix8Xckf
XieFAAAAsgAAAEwAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4vX21ldGEubHVhNYzBCsIwEETv/YqlZynq3ZMF8aS0X7BJ
VrMQNyHdCiL+uzGSOcxhZt5k0jULvDsoEnwQHKB3NuXIoiR6R6V+U9vbGkJbjMfrdIFzncyeKTjY
DfthC7OiCY1wtNjMSTnKDzqFaDAA2hosfwzFAYujRMVEIRM6yq01Lxij9ZHVr08ut5/uC1BLAwQU
AAAACADSK3xdjTE3CTgEAAB0DQAAVQAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZElu
dGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9kZXZpY2VfcHJvZmlsZS5sdWGdVm1v
2zYQ/u5fwS9DJUw25NqZi6QckKzDWgzuhi1DPwRBwEgnm6tCGiTlLDCc376jREqULTfZHEAR3557
7u65o8Zj8gG2PAPCylI+llwbwkROMik0qC0zfAvkTyEfx0aOr582ML4iLGcbA2pCPksC2xy2hIu/
ITNcismolBkryZLu9qPl5EHmUGq6+5WLvIQrpnk2o7sf0jR5l6b7JJie0900XbxNpvP5u97C2cDC
72wD6suaG+gd24+KStQ0yHKyZSXPo7z2LR4R/DXMcupp3TSLzej2wq1r6qZ1pgBEfVKBqZQgeR0Z
3TzPV2D+kIZZc0tEiGJK027pC8/N2s7lN9Pbbvoj8NXaNPNvb0cg8pCzgMdfmIHIPpKGRlIwbfr8
mcbMmGjYjdj7saIWxUJGlkJi7QVgvCDhuWf6JszRGyIVEdL4PVxsKjM0N9EojbuNkkZmsiRmDcJH
a0Wsd9bWeFwriFQaNDGKZV+5WJFPHzCSmuhSmiakV9ef765/++unj+epXSi4QDcUlMA0TDzQtWJC
l+gZkaJ8IvLeqhRqvRqWGX1BBGxBoSILfDKiDVOGFEo+4BapcgQ1oCdBQC/pLpMK6CrhOUp1nwj4
x1hWNE00Ws8M5FTwMnFUaMFKjenhOmMqdyMh1QMr3cBGma4m9l9yj0a+gtu2r822Cb88V6DB2NhE
TVbsD20WE8uoWY0wo/VUw84NOo5uImTqpnp83VyPdW3SJylgVQDkkUnM0ybJUBwJllJHD4XTMKg9
bjLeBFJWhnbkh0AcCR+TdrOfufDaQaiWmDOKQL7ALB6ls8Z2D9GoClqQ3f4Qo95bMtfizPtu/N+g
2nPUHMG7871SOGZSezMLvDlb1AOMEqXjaX263e+kf4nSfkRRayaAbPBRnhOXT7ufsId7vqpkpX0x
JEQ/cpOtSYGVW1RIBbAS2IPXf+hOKMWLMMOHgWhPvuTRfBFE1evuhQTVINMwybP0OBa4sY5TGhjw
YrcGCHZF8JsatHDPCVo9LkHXP+1yD7RWVBeDyKV1Zrume58H74v4NTROKOVERN6n1gC+fDd97gXn
NdEPfcJWc4Mwt9R2k2Nr4VbfiH6cTf+HQa++zmIP9LDZ9UbfT4+gsEiW2E6QCMMeglUSXDZ4I9RT
m/UT3nDYrlyRkJWS1YZw3dXP5GVvTzl72sOwKc6S+SLp+e1rrr/rbNHvvYcabMHb7t8DHcT0lv2R
Dt1VzUsijgfl18N8bnVzzKB3IfS8Ce2HjX64AxxV9MmkBT1SDPS6b6vTts67xObcCmjDuNKRD3JM
cnkqxHjgZE7H03jQ1jeu0RT/XnODDmpv0F8087KuhigMdsNXsuq3VA/gZi8PP4eNrLL1z1sQxn3H
t+KJw3NRoJjIS6YV7CyO7SA6ljVeUJ2sT/fpzmELE34008OP5vYOOLjC4tozR3c5+hdQSwMEFAAA
AAgA0it8XUnHXHN6BAAAiggAAFQAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
bnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ2VzdHVyZV9ndWlkZS5sdWGFVc9v2zYU
vueveFAvcurIdVoMmzMVSJqgNRakw+KuA7LAoCVa4iKRrkQ5KQIDA3LYqcCC7lLssATBMGRF0GHd
ZfZhBwX9P7S/ZI+kZCtbi/kgi3y/vu/j49PKCnye0JRySSQTHASPnneA0zFNgPFvqCcB37lMQSTg
hYQHFEaJkGhQ7imGUWcpEh6J4EnXTeizjCXUtjLWylhMOAloYjVKh006Zh5dOPl6PTdvZFIKvslI
JIIbmQ6ZH1DZGmi7r+3zoG6MJZ5qh/fFMGU27/OQRAjp+nSQBQ5uMz4Udrtp7VoNJxVZ4tFOmg3s
1UYnJtILbct2lluNefDDjPnUPZ6UyxGmT93jJTi2tovplQSZoEZWE6wvs2J2KoEHuMbd/JzB9Wkx
O4HUbOgnK6Z/jdZgbHxHYTG9qNyeZeQ5RMUU42y188Irs+h449pwrElT1V4nMM7PIKY8q9X28zMG
spi9hji/HIH/7rdi9iODKP+Vg80Doczt1j2Tt1HWjYvZT7BOmurlZw8R4LMJAyEOYpIc6DJByLAX
8ilwhJ+BJAOMzS9goBRwoKquMWsMAStmb0hJulZG4a0o9BJisF6fovcJr/HAWpcCkmL2kgFH4ghL
amGUvwPbio/mgJ1bzK6IWZQGo1QHgf9ZFn/hOfCIMAi1Hrh5pMrwoKPF8NSCGawOPCimv2Cb5+de
COPrE644XnCtQh2s4e8h14rOgxALcSPif9pBhd8got1aPJ8iWV3R0+H/0tIopwC+4uATHhpgDnwW
5n9gWgyansfo9u6cwwEe0m7IaOSX51LpXEzfSE1DwLiYfafB5WcCulziRS9D7sMm0sOcC0fc+wrL
aeBXfFE0/50DXgKZJRRkKPJzbIEdxYQHiPQlV+Bf65ZleB5rsJ5JAV/QNIspBr/FGMVKYzT9rlSf
XWaA+6/gye5GBza7u+sb21v97k5va6f3cL23pSW8ub37qLu1vdnfePy4p7lOloYZN2NKX1onDcWh
zbhPjxpLsLi+rr7De9qwvwZsCFxIbUFolENCkRoHyv0qKvUSSrlrxpljVpUNZ40MXRwdoTOMhEhs
Y+7gpHmqTHZj+Y7z0cdzBCFlQSjrATrD8mrr7gIl89zanOtweng8ZBFOUpxkjmMFil7LchzNATec
kZpBBop+Nssy5q+JBPtD4WUpGWAWmWR0UtUy47VazRWMxZjanB7JvhIGkeG073iRSKltItSWkq5y
Mdqhk9rpMe/ArnLZjfp5LHIqhRtG5prWiThU01bl1uzut8tTEYd7t/Bxu73vHktM4uIE0RcarxsG
RgPiHbi1mpqBTrHS1mUmpsx7El1/n79VAn4wDWeRSbHA9ekt3UYfBqdH/f9Bu30DmlHWrX8X9dlL
JvHYrIflpdNqQu34VSsYOLiAv7/9QRnVeq+9jztf82q5uo8jAX86YZ9ELOCu5eEUwI+2aZ/+kHhS
JO4d55N7TZ+lMUtN0wxJlFIT3Se+T/2++crixxDbddI0H2tcoQwT1Ak7QZ931S2KYHmzNP6lfwBQ
SwMEFAAAAAgA0it8XdN/vCuyBAAA+wsAAFYAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
cmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ2VzdHVyZV9wcm9maWxlLmx1
YYVWUW/bNhB+z68gAgyyA1lRkrrN3MjAmrRDsG4xlgAD9mLQ0tliI5MqSVkWgvS370iZtiRrqR8M
8cj7+B2/uyNHI/I30AQkWYHShQSSS7FkGUyIhBjYBhQRPKtILNZ5BhoSn9A4hhy/yD3XwPVjyiBL
iNJSPIMKTjIR04zMSEReXk+WBY81E5zMAmo/BhuflD5JhycEf2xJuNBkExh4qtkiA6JT4Lg5kuGE
s8w/XVENcwnfIMZNTwnwxPrW+yRbP6miNdVpQBdqsAmS7dBvDqthY7XCP4jK84vww6UjsAmqcBql
Z2Fw/Z5QnqBhG05LHF+O3fiiPU6qm2h0FYZnFs8ak2oaXZ0lW0vfQpvfLgxv9ttfn7961uzoj0Zk
JkGB3AD5BJqSKyeB+khokpAiH2Ww1GQpJCmFTBRh3KATa01ptgwc0J0oeb3YUjEjyVYpDjOJ6lbG
/9m5L4TWYk2+F1RqkHuMh5bKTs6D2IvKegsEZhyPMs6oUmzJMHUopg1kaEf5gsZpF/nc0oiMKtPo
1+Z57Q7R2dpeJhTr1FjR57WX5yYy+oybeYGHMK9DjXo3PzJVF3UWfBg3U3PggsDIHTXz2cAfHqds
wrB6TLrPhcTUXeHXIXEROdmeYyBh8H5sscxoehGMx31IdCXwvOcSy0O0QDYBB31z8c6FgUjWNL26
dKYeOKUpj6EDlBQWnt9cYlaHYY/fbkHHD7OEmsPBUK6vj73cNAelOp6NmrO8K9TQjMMeGEhWcHSK
rrTu7m+fPHJizI1mI3LgM8ohG0jb3nzyeYO9auiy/V/gD4/kXXAVbAlssY1heemUKcIxTKzIPx52
bRGMGymZTjFNsISYZphdmi4CF0u9QaDTYr3glGU2nXSVw6A7Ewj+mIpyRlfwSYoSa38YRZ5j7XVb
h3GepIiWgSU/sP8TDuXA6+B4vkepNxx2G4+WBbS6zoHvGnhxRNUYdyzr+G8Fx0aQqTeJ2q0aCJM+
hMGwRaTl9VaU6L9kqz8R1sTXkTkT4rnI9xrj3fI7YEE6le93ci2wv06IRqFHC6qwmUlYZqKk5rpZ
IER9x33EgidaFHF6ngq80Rj/Vhdx0GwIuzgxpIzxlUnehjURcbE2CdM2bxiU3ZXMQlNZtfJ9STMF
/mnBVZHnAht0MneYrQJqiuYWBCvQ/+BF8UWK9UwoZvCHP5q6IYWmo6EVqFgC8CdhsulJUq7wvlm3
3PZKd9wPIWDKfLVKmO3bW/YER3M2XzO8PPiqe5trRwDfGblQUY7G7Od0/cYK32SASZ+XbWSuBr+K
THfxyyj00yh8bT08Gvv1Md1Pz0FKIVsKGHek2OcmCq1YAvMcOXYjFM++uczbkb2loN9ZY87FN3Xd
CkQ89xExO83NcR/Tt0KWO7m0qYRDehhz4Oawh6NQnkvf/dwEH1lxOvB+efSGfXtzMTfLTpsPnlsJ
dy5UtRBbgg3XPVHwdVJri48Q9MM3hrZvz6Nabb4wEANUZDlZPNPPXvbDV0uaZQ0Hc+qYW/jIKjLd
EaE/nf2jaX9/Bn4dq2XRkqPepu9YDjD/I0xN7UdkJP4JQAIx9qDmm7jR9v3Tujnixfm9wIclLrPd
c7dkdvIfUEsDBBQAAAAIAGQsfF28EWI9PRgAAFtQAABUAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9H
aG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2dsb2JhbF9zaGll
bGQubHVhrTxrc9s4kt/nV/DDpSjN0LSc3czW2cNUKbGSqMaxXZaS1NzuFosSIZlritTyIdmXSn77
dTceBEBISebWNaNQeDQajX6jqZMTb1o0rGhm9xnLU+8sHHnrvFwkuZcsm6wsvHXSsNC7Lj22S9nO
y4p/Meo4XVfJIvwpL5cw9sPUi7yK/bvNKjbw2+y0zTZJkaxZ5Q/FkEu2y5ZMH5ZSixow2QEaFhiG
bWrEW1ZurAFraGJN9aTGzLMNs8Y00KT6X11avYsszVRvvqr17jxb1Kfw8VBWLElZdQL9amxVlk2U
skW7DtesyYpVOTgL/Jk/DOuyrZbsvG4Xg+fD803SLO8H/iD8+XTYbQWoGqXlKsvZAAGFoZ/ROcRE
77xNLMLV1mhOvHhbUasx4Za3WRPWrG7ayj3jCkAVtT0j5619jGbR5zUrolGALLJj0SrJaxaI4ZEA
9kWiP51F/ummaE7b+hS+jF9dTeLp9XxyPX87nk98MWz8YX7TjZtca8Nm76aTq8v47dXNq/GVHH83
ub25m3cz3t6XdfO2Tao0vmPbsmrqU87YSGk5adUWnKnZY1Y39WA7hLMGqhR48GHSNFW2aBuGHV+j
Iss9VqQ/nZx4v9/c0fkD92/bBmnhAbi89og/x+m/2rp5V5YP3oKtgFW8rKlh6H22yBqWek3ZLu+9
+6RIc1aFNioEcioHD4Y/efAnsOJHH9IQD+YbDWGcLOqY7WIBmTD+CTG2VliWRQMndbNlxQDPki+R
rbyibEi8veaeFXJNOkzauBhFx5+lNSFQsMdmIFuGxsSmart5QAYvDpAK3jbJqnrAJy2ROtBFaIR1
XgKh4OvnL0MvLXGxOlw6gSrAOpauzbI82dYsfV8P6iapGrVX+kZbaJ62bIBqImzKeFMPo8iXs31j
7W4MH16U+8HwhIO18TlA+npZMVbc/O461jrcJXmWDvi3oWs6sKg4Ld7RRIAQoCI3RVtpcAdFu1mA
sjVp9/KMnT2nPYMOug9XeVlWMBwprjf8fMZ+Heon3nAwfM0kWERNyeEPmrBmS5zfhM0uhudhoPW1
eid+GV4guIRQWBi4JbjoLwt1tPi/2vbsPC/XgzwrOlatWb4KUTnpqJUPwS7aoiQOVH+4r0COAvU9
QDCgzP5R+BwbZHqQVEATn3YcHg2HReNVAnPSyGA7oQRegQL12Ao4u/HSLFkXoHCyJagS1DYBcHrK
QMJSNGLlygM12zDBBA3KGNJglbR5wzVBVqxDfccczKzdbJLqaQDmpi6LYAunZEgrNhh0lKcmGCcr
kjzCQedrtD7+M9zUf/mBH88+vH8/vvsjbB7RnmosxTbbiOYBkcJms/V1eFFWhiXqDRwW+HvfwGZ1
BBU4m704m5U4k1XQJIsclUCxTJrBZxqNf77lgjwHJ2RGY/2gG/S+TFl+7vkhyGQNmrpYC9EJN9gz
1IZOipQGlnWYAu2BDn+cPNucPEu9Z+/On70/fwZWWht+R9Q2QfMTMEYle67va3Mk8U4FncBSI33C
a653XcOFSq57c14B9R7AZhQJWlZPGG0XiIUYaUO4zOotehzQxT0412TR05s8bpvSu2N1C04UjKxr
GDV0zYdxcUXjIhIWHchVufZYVZWVY6ImY715r8sWiIuGAJlrAwcAW/fWaNiFDU2Wy7ZKlk+hH3i+
/yUgqda5eZmXoPyDpeI8aghWim1B8lEQ9/TJR/NHYmWFi9QTdVixItkwzv8kJsLoUdem3PGuTn0y
tJ6uTqFFro2D9bK6zBPuB8DOGfiarAKOzZ9AqpBuS+5A4JogqjV+e5XUoHaej54/B32yyfKnEOHO
YUAlOdS7L8VGcV5ZZWvEHL10MveAWwKGmfoKWIr7q6i1gGjlvuMcQ0NxVBnfwEBRVJfBr5H/e4bO
COH4V/+IfiAXJtL9mQvRs06jzuHhno70XVOGOrWsDAeGRIAs4ToNV4ylFEiAA6eZdW1EWpVbKZnu
QXzNZc6SCu1+2doDDVZBtiZ75V+P59OPk6At6naLypylcbLN0OxwCnD+sLSk5FQBfDCEDZ3rOA7Q
bCFG5wZGA+IqQx3DkStjZmCEE4t2CwK7AqucdhjZ2AhGiXRCymMp9wWrIoStzdhXyXYLzQp9eULB
qgKxqYMwDIe6VBGUkMcNQpCoheu7mM+KBo5Grqt+OVO4f/6i0Mc/0Sr3cBgTOYn0kVhCDoadXxgd
iiTyweyW+xf/ElydeLLjon8oQpzgNGznByUf/GRD0JRouLBWnjrXZQYCkQNdk4G/hwF1OT3Mh73d
uyj57TMAX/rAIfR6JP2l+61REWi4lX7UA2NbYa6G3boYw8oH5CtlGWVIK5rQqwMDpq2OWlT7Citp
3yC2bAghTTQ1BDSHUxjQXsTFgQKB+UmB3j4HpYImvYXovOsdXmhDVbyqA9mURdaUh8GIfglIfHWC
2icP7CAc7JRA8NkNQXAf8uiHacjD1imylM6qOo86h9EoZdMMTtLYQSCjs44a55SwfpDRiezk+jJw
OIfgMQdgcyPokk4gNknnTrXLBuwUblssPTs1SHTgGGF9VZf4DgS2g51V3tb3XbDjGMEdIH2EeuZk
0iYYMQjNCYQACXbF7piCkgvPblJHbskhbh6TBkbQAQIDXLRmzbzcboCqH7M6A3f/U5ZC28CwajDW
cCNgmUDnLpGMg6hn+ZCsGXiYScrSv/vACfUpT9uJf9rM/ydYj4hzYAXaDCKzYsmjaXChbtAXQqco
R+PE56DVwWwOe4RDgLZ1Bj5YBR4SRIDAGhdeAQ5XhY4p24IFhuc8eQK/SWxALpWWS5D0gvs0A9x+
RKD5U8iBWemUchtUdpoBGx26LhU+/2AX0DRCPXjILAdBU3BOzwyG2dkoRJKmiXRWnFbCddTlY/b7
9DagqbFKezm8DCliQqE6oYi+mPP8ESB5UnNy7sKmPlFNv70Y4Z8TNnrWcZ5tsuagC9SUD2AVPn+x
VD81KwdVsxuy7d8tayGm6fJEBBN4HBNm82z5oBlY3R+ScL5Ga/SFKmPZr3xdmav41vEpNagZLNWh
onKIzHo+pxrVjQRvPnmKumwa36A58j/KL3ECgwUfO45HW5NQo6Onp5dnh84bxDtngpMC2kC8Ia1K
835ojeisv8bt5O5NHywqcJQ8bCAJ7IHnBAYuCbg/balIDQuRpr6czoaKCVRGkbfskUm2+Fx9jYTO
ctFCrBEvwZ6undJpsBCKUoSSpblFaJL0L7+c9ebxBcev59Ob60AQAAkCjwhMPCo7ugsfz4b9xqez
oYslF2zdFraIadQiqkf+7fjtxIrRLNaOXl2C5cy2l1nFU3TT1fsMExYs/TC9Sp7ArwUs0sffRsQB
/h5sNYWHPlhD0B2wCG/C3jPsODnrrYXan44j3GWM5xu07yAfYCtqFmMb6ruyUieXRidp71Twj88/
5x4ROUMD+gQlsx/4b8um/Aig71juB6lFQUxLdCR6P7n+oILzYzBn9+X+PSta/yi42/H15OoAycVl
FGURb5OC5QNhnXiUfgTq5fT1/Og5gjJblW2RCidFaDW5YF6WD62yhbsALw+HPUgd0+Jy8d1k9uFq
juw4kAkUy+cjNuCwY/aIVp/MVB9yL9VMuDplM82IC8HpimFgjKRCCe3xgEmf2eRqcpBC4M5MYDVM
6eAVE6ZXcYXcuweP+H/RH8092BiYl4CQS7zt/VOdkQlMtmEPHliyGtDpMx13Y/3g8xp9WZjrB9uy
jpDaOOLzY4RCHjxFKNbBPhoF99HoS4AhiybKX47y1+z13c3VIQb7TszqfbZlLtxGHLdRhxtAi79n
D6lUH9CePkllUYBDfM+1RQ2K5B5kMeN+ZkSXLsmiRuXyNPwmDZxmo95iDNTZZVKKPVVIowgfejps
vqTFFRaMRh+3YEa0fzDz9GaMciShG/odHJChuJ74+z+qfxT/BPXvgQSJHAnF7b7Ci65MNFmg5e2E
SbLnx88OurvSLcHgXLmehzxLlaPWdsXRWtMFMz4f9CCTYBEsuxszFmJOUbsmw/uP1GzYJXlroi5v
CCntzffGmwIAP3RiL9Oqwp2KnPfK5LGpe2k7jel0HHViHnXqpte3H+aB4f/3J0XGLbEQcwdsumuG
ZfW7a5V6GTpQN1fR0jc6ciLuT2PKiPpmPlCFpm63DMsAGINYtIJAE1koWVZlXWNSHZqKOiOfCO8B
l3lL4c0e6VOU3o4Ht96eolvh1IUS6FjuEUQ1KQqCrEH0ltBY4o0jFwh5GQB6SQBUwSag/jWSCanj
p2ulqrQ8FvyvH/0R+nsqt4F+pet0TcJGdJut7mAbaReXPSlbJGkMMu0QMZlmieSD8EH5EvcwTyAc
JVHEFfJCPoiEBZYvxVVbvIz+wtvdW9TT4q1IOmHHOWY3B01AYm5mjqjCQV7L/Qj5nbKWsvqpWMbA
vWvWcxsuJ7M/rl9D8JEAo4BCA5Zu4d88BraIxb2dEkADknlE+Oe4nMBL+x79NOp+SzyPkduV8j3Y
8UOJbJnCEXen2wT864qqvyoIY/BybC0v4rHyRNzLi8swIB/qWpZ2vo+8UgRV0b+lcWH7/0ibd0d7
N3l983Fy90cgk9+wpQAWj8sFbGfH1CHUEDsASHADIt28Er5DE7J2DtHIIZumEPfl+jBTfENHu3RE
L93tyvKZ+O3B4RK05PEvpg4/ZWlzPxgGvY53LFvfmwnHGj5YtD89G/3tOTXz+iQsZ/QyXqAEp4JF
SCbdVCrX+KYFvlL2Zddv0Yt+NoKfTAhrggc48F/fXM8hRA6epcGzmj7hv/BsJT/+wp/8AENm+BA5
WHAa24ruiuFxW4JTj53pI348wQeskuDG4XGTPNYN2w5Nz02QegfIbsCWkE3SLyMUiwysBnn1xi+3
ewzlWqTzMiSXfMPIK/4QOT0NR97wOBIPT/Lh8Uy2nPVDA2ERVLRjON+Pw5fR859Nd9wxGyL0xnLa
QY39bEIy5oEKegOnDJqJActtmQeLs3O6/gGYYNoRJEVZPPjCAjmG1UM8jQxGHqtetOIhMxID4iKA
rqRLx+vF6Gdic0Wv34Dh/6poxb85QygrHF3RDmK+gxh3YN1hyz93hCLybfv7Jxt3kd/oBkQyWOdN
g10Akj7kbIbdPobDPIL3XVk6+0z/WyeBTSCjE9lOC4VlE1H3OI0sYb69u3kzvZoIYX4cRfDwRJ+P
Z/RMnwVrIpJuKaQRirmQcFFoDUIGe6bAsUCaBxScUmhK4ScFn7sQQGnC/o2YEXW2KCVUGsm+LBDr
OwNwjURHAHD7LRJviL9ITThBKgau3Gw8ksd0ZEGewDoOHo+zOgwEr5FkYqEX4CoT2btTTqoGtCMo
rBTOrSuCMh1BR47e8LrkOHLLtlnar78NfFFF7eEYqqKtyjWsVfuWaRRV1ymJk5gUgh+zfBhQfZVu
ZOXYI+uZJVsA0ygMPZ6PdkAVCo1KdCAw6nS6qP233QCj4FnW4xhFz/IKbmJWXrsreRzXxwcHqiSS
e4TM0/QrgawtG9tUhePj22nv6Mo8jcyC7nQJxxzzdB06UTEcQ6IKCWA8cTb8G1KBjCigkV9ljoJe
34iJVzXWxgr3zUOaVYMjNfOo6LuBvMbe8KMatol4cxj6p2aJ5bPNszR+9u7Zeyyv1CbR7TDOhCmi
ih9zLHqhqXRL9/d4+y6r8/GimcoBI6rPMODA0oUFzy6GVcWrODHwE60AeOU6OYABYUCyS7Kcak+t
qFO76saPrudg6sHl+DpjMr1H96zMYhdRHDVSdRagzdJyHdNdzajDh+72Vxe9omZ9lWO1L6g3ZEFI
UrTAS+VqZcwWWTQL766YRcLTqkR7FaNijFCmkfhXAoMQf3Rh+eCyQYTY6ru8m5LfiR5WsY5MqEF8
jC+EDPBDRA4BoTzUciDdXDshpnlK8/HdPNALl6luGV8PAN4JOFsGVBUZHSxZxkyrdOojs1aWqEED
dModK8Qd9pOfVOGQ53Y6wghLDyjULtaNA7brJZhnhpFzXC7PQpmVDWYI4MLOFc/0RDGM7eWIYYqo
4vKhW08E9/LRF9Z2icGMOJf6VTGQwy6oMkc5xpjRwehVPG4CZuTDFWXUuyYMLwx5OTs1MrF4Bc1l
Ie8pBFUUd6snreTxWL2jwkMOOlg7pRcrEkO7Knv7pQ4dDWSZmLukwZF6pwIHCedg7cL3XHg7NvXV
rBuTmf4jWXyBv8rj26qOqyc3hoiS6WZx9dFbRL49lxX0ms+PrvMn02Rfv50mM/WYqEbFgnG9NsC1
yp8tzNQk1cqtgT8VgQOBKTqTh+wMBGUP5ckatnMonP39Sd8o4rWXe++W8YTpB8jzaTx//e7y5m3A
cWEpGWZV8KcQ1Or+6P7WTMk5E2Rc+9Ne+nrd3COONJ0AiYHROnSS+tDbU+QgGjVLF50i779X1S81
PPYylRACmiTE0Ezny7U2dWS9ssdSDnvD3zjc1IdvLzl4fnW5qfu2Ae+GRZ3qtBg8D3TtZSvLb40k
MpJVfqkhI2pvtcQw1mHD+VvqTqNJw1PAhxSC3MSFhZOMOrtVey8hktWzQ9YW73Tl/R93uXiTbiZd
kavu1dm+RqeJpP8mvS+xSbGGH3RBqH7Z1xUT63MIVCynDl0ReFnwt5Pc++FvhRobQpz79Yb4hjfY
XXzdaTDsxeXaHpUxUxjbiXXd6z1gNDWt88Ai+xJB1ktf6PWAEdUDSgx0s6hTDbMRI07ib/D+i0Ct
1TG+eCWJXvoa48nj/ZZIRWbFCutaPTJeMnPgrapyA411uwRnul61OYRn+wJLbtVLSIQrUrvO1gVL
Rc1sxYvptiVAesIkTbbKAL64fIFTwkxTQ8qs94Y0nuEVyPymXnPc4SFS6hJbHeUE9Pb9WXD2YjQy
7vIegpVQbSI6DLpwlphFbJUiSgoaVfjNC4JW33h7YnVObzsOjr57CBgGgHggXktdnVOZtn4p5OB9
RG/MX9Ay3ycW7IGv0A+dPGNwcqdvzHYlRmpvRrfm1VpvNetDxariFwTC8DRd0gt8VDixrcrwodzm
LTgN/sG59o8AvH13M5u//TC+u4z/Z3Idv7q5mfffmUHazFAePnLWSge9aMikn/ImDifhrHwCScL3
pNm4yPBUt2Bd/2r6enI9m8R3kzcfZpPLXpats43m0vjGYFmc0Pt09MrfgjWJyJ7V5wR/k9CNQv4k
rw34S314w5V4Cyw6QxcYE0mhthuEEx17d88UGmGZwV9pwJjrzgH18JcFCDc8zV/JWRsFSA1sPPya
Gtf8uA2CI6O8Q75yT6dLzasITXF5PLm7u7kz3z4VrsUhQh+ATH0SuIDBi/jVZn0e68c31xeXk49w
zvGryXwc/zqaXaBEUk3h+0l88+YNT453w43ua594Uu7AxSic+MOhIfzSjYtc1p9YXmj2vkSY1lGr
Mv8RUbGMp0sSzQL2nkXuA9JyG0mDr9DKN6VfRs8twSIaYjFEfDV9P51feC0cqkyeb6h0tRdigVBd
8peMeQhdeJ+ykzcZFVFzxwAkp2DNvqwexIseuuhAD0gEXulwMRA/FxPgr8mIWafdr99oNKeJKqMM
38Ksfl0WBQUWjsSy2uT1ZP7p5u73eHw7jT9cjz+Op1eoGr9rs/KG/wHjE76UwNtCAHdkoLvsPHs1
1ULs03g6jz9N30wPLryChdtGqQxFq9UqO8V26xcFNPpgbwih1bSYtYvbqkSPw52bp5FZ3Q27LAt2
5JXdjnmIcX6Aqv2cksGk0UHGFSUDnZrChUnSPTGwe9tLn235LiB8gpAu6gSOhIyI9UBylfYOxFve
AffGlDnDQbpJN3DlldHS8zMDVgKOQap8f9zoFm3U79BmdjNHaqi8INt2yEMHUuARyx8+gWZo+S0a
2RwKcjO546SO38ARWzoVwRyoM5PqLoL/9euMMs9rkW+3PFXscrzfIwF9jQ4pT01Q0afAowIW1o/a
Zm9khV7aTUzu5zxsctzeXF1xI3lBPzSAv42j7qrEjxhx40usY121CuRBjVJhA70yVy4fZOiAFSP4
Gx9tVWEV8jIBtDxyiqv6UIaCShxhW33UObnp03rhBKbxzuhvL6xT5+J1dfPpQr7HxyONGmSbErH9
4nozXjpD4chd23buwOQXPekFRLpjdC78t5CIJMkKaAGnleVYVlfj77ZkNawtXycEUw42iL93mPFC
tbYOe3xlmFIZkVu2u3O1XIbZLtV0E8Eut9aD5/+YTyEbaL5Ewi0tjnFdKsPO5Dh0omt+5+11smhc
aKhJ0p8in/dgKbzDQek7pXTNcbS0fZM8LZhJ6Q57XdwP00iM6ijUd3X75/Pnkij4v8Bj9tP/AVBL
AwQUAAAACADSK3xdy2Dh/fMKAADpDAAATgAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFy
ZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS8xLnBuZ72XezgT+h/H
1UkXktNxS4rzy6Kay69yScJRoVVSSYpGFzExk83EjFpH/ZAwJzuhuSXExhgzbE43WsMm02qa5ZYx
c9may5gdnUvnnF/n9Pz++n3/+jzf7/f9+Tyf9/N8Xs/3m3j0iJuG2no1FRUVDdCB/cdVVJayVVSW
vFu5uKFSSlQNV1FZXQna73ziCk/Mjy/vGjzXMsmiXp3XrQzf7AVf9ThQjwzNecSe6f8mc4GEJPke
h9g7J3+3lrs5bKvVi6P2toUXCMMHzbXmt0eGhXQ+TWSbbDqOO/vy1PEH2VLetSLaUiD1qmfJ9Wqn
ugR4qvmm59TpOQXdT/mfFfQeaWyuLQs9Rhua5Ixck0Dg6l9brVy/TAPjyv4Wsg6y3Ptcmmer9Bh4
0Og8gRjoru7Tjq29+aoadT7BJlI3GEjGA1FBvNasAlVo+9uNztfzzJ3HUvNkZ/j2AcxreeZOY+l5
zuyJnh+kboLxmVDexQfACO+HpL0i6o6o/LbD23zY7zvu/VIwZfHet5CP4WKSX0PM8t/CbefCXVoU
h0n4sOLjBPbmEWo4y5stP0pePHz2Fsvbr15/GC2cDfCSNWxQI+39L/kvzXwM11pp53oKirzacLH2
MugtjA3XdSvka7K46Jga74z3TPLeYvrv4t8UfxXfWRQPcij4lGPs97wtqhqYWprVQWfvK8R78pNW
JyH/2MWNTZdHGr5ujO1WAz/AA2MwvuxB8b6ORX+9Oob11X068LAlu2QpOr9WMob8yf7fUuaX5Mgt
zMdlhKAL2mSqzcHF1FDLlONsHXzI4iak/B99W6bh0seJCrb7s9K3lpYTrGUu/KZN1orVFnMoBRkc
bEAgfygMiNjKebvUGVcZBFavPyOqLhDnH6rhVybqIhJjMuGy2g0ONcsNPtzS4SH7FUZ7wexiSKgD
yEQsxJcMLbHC+HRlTIFvvxe70t4Zl6ySI6AEMKW/Wgz1xeqF5dhEjHoJhtGVc7zJJ5aobaA1FY2Q
Uy04zZRcxHyBrGn60Vq9tvjtw/CujJru20Slp4/+PgKrSfslbCb0AvPyJb9cOhAUEYwN7WmUvAe8
cVAUMzSdqMNJAb28gZqGWmuzOE3WIYmEyUJa+3c1dWuUs0ES2lTKihGcaacRevDsdFYHE4UNUHzv
vqKW5Vi1IzpG/NyL33DSqWF6RkfwwhtpOBoz0Xd/eJuDwTFlBfsJF5wGeIMN6BuaNkONaYGaiTBW
yVzuFcfoXVEWR3Qbafd7seconIjeBGnPZS9mF4F9UhjYmTqV4613RN+vzJzZDrjbgQ/g3KcxUiV3
AbNnnujkOs6Uxitc4tq8FEfJauVs9xhUXHAzvbBp148ALSwgaOORKc0wD+x249v+k88ulxHtInqt
4x1Js9uEyjwUd7ZhGjwXlOFWy6fUDVNYPaQGBwbd1mAqGj5k+Lp+skzQs7uW5XVdwgTYzTTP7Nwz
dkOK3Ol1ljkpihwMMTLkZ5pmGykPGHpgW+SOu+VJOv48En3cq19yHltuXx6EKlnQrDeOmp9/V0sV
ZRnlZvueHO+pDgx+ss+7pzpSme1ryEqne4N3zDNgstG48HOimHbXsizzFljlwCRq3H15G6pkePK0
1NCHvGVWEW8QMZqPi0sDUCc05X7WfQ9Q9ImEACTQX0wmXU43rIxuYq5ytiTs1gJ+uKVhZI9qLQ8K
pPXbvnrrICtXz3Rkw9tJbnETRal4h0Be0pCbLVjGpUStvouYMyYQLvT/JLja2J3IrcejlIGU8PmQ
IctT/KxUq6LgkPg+dzfPFgP111KSS31cvW1zZn/AW7uR/o0N+FN4u69q0ppzidqy55TxYoqFcAwG
AL1v2/CTNUc+WK2bsFr+Kl8gwGuCmyDfWYYn6X5gZNVVrcytMvD3NBvGSJYqbxSI3P3P/UuIMRUD
zZxxVRAH9frQECuMRZurzyuMRecmQpBzN/LTFObHR1eMv5T4CWJsXJ2zQwq1rVbypl5uUQX3Uqf8
BEnNar8jZeVnM38UcASNy/T8GyVyxLfjVP5nA/6JU0lPS8f3TkigQMTdGKJwVZgzjqLpor7e2dul
OMgM4oKiq77j2H6JUgURIw3kRu7f8I3GpRR8kYyJXyAj4hFnpHbdSaGkpOi9ycr6/Q6m1iD1+tjT
xkLJD+UQZ1zIxZPkvEN5vQYbbF5iLPZ1RBoEO+OQ6RaMtDXu9lHFeTr8h1A3D8KjGzsnloShZ3NZ
eh+C4yK9ynSQWj4e+brDRF6OlvLa0MIUjLi7LXV73YidcsRIhtHlT/Bv73T6niQD3CUXovr0Z1nK
8Uj4AsdQrhBSf2pgV4Xet5y7tKNK1AHwSN1lJuwco0aJjn0XLHOVlxBqRMjYWhr0kORxSqfrbdqI
PU0T6W8fN3PRYzOj946ehmhGkj+ZERfJAHtKPWp8xOn93LASPm/uqXKIQJHwy1pWz93LVy7I840Z
mR7x4a85CRW8iBPoFV2P73WKOqM2gyzcsW3Z3j05gIZipdVsr6ktON3sTHYjklsrTySKrecJAvy/
h27rgBaM9Sj8PYBpczssIlLBNQF+KLVgF83RW/Sn/0fAvVZl+jFGY2gLLRrcqfUdk8nKUSqUnSRG
NaHDMnsyjAQnmnpbYI31MUk68oA70kbwoaaqjfQxDICRCdByagp6A889sAOJRrnylU+ljCdU+OWq
d+LNpvW1j76SOVHNZws1EcTZsljpRJ8XY4ChPpoP5MND3Mehkq4EzxvcS8yqnaBAsqm+dTBMUhhr
AnKMehxi0JgWDYqQDfCdmJlvEQ9Zlyrx0HwPd1iGZdvrqA96KzIC9mIHyp8wFh6JQTsCn64iQsmW
Q5tB7UoQK9rh7kDDBvJMGaYHMdYTJX6luCkShC6Iq5WwKOwoSrqMu+aFZcaAWAFqHggCYe/pZ5De
WAinC6b397pmCzu5dyrQVxC++NC4eePoPSBDUfXGXZxp1i1mMkjC6QY5Zt3EBkg9THJymdIojOOd
AlmsfHdEC0szLLuBODtJpV6UjTmEZNrs4fihFu4Yp8QH8p7LymKm5p/MA6j0KVm3v2h2bLTVI2wD
QvAYCluYVtiulN9PHhtdXKGr8/wOo13ZRlERoG7akEbTACm6LZWVNd1cAO+G1UWMpl3QTKl7OEdZ
3mVotxB0A02iB5yZe1vmlDbwcvAmTLRu+maFckwy0FfBXVjApmfoIVbJf8CRz9MzCyeDriusMPoG
jsipH0+zWmNaYOVU1MhpPTN03lBOv6bDTClcPiZRSoAZNxDzz5xMQGFKHNBNkwZ59mAtSBdGD3zM
Lk1+tWaiItk38GCnxTi46fY2IbiExhU3o6jbx1NrpHrlYYPmk4XjS5UpRA3hsT/Autbq2bgdX3AA
25q9FdL+FFnYFbZRrhDPsmXJmyBqTXtM79ZVOTk+zNXWjRONK19vEe7QWWQlDl7kyk7woBIXwxKI
nToPue8XCOWYFNMPMVFo0Zt1qlDi4gvnW0j3oUJtRMIQD4UGrgd+9jL6hLF96btkYJ8jf6cshblc
SPiMWZ/Qu+WbYrr6IyaFwL44Qi0wrVMF9zhqm0OWgXXu4Ul5OuJZ3auegi+C90Xp/x32f7QRc/XH
81llcFNeayFeFWrCT1hyqZL69M9F+Wpgk9qHUQy1j3Y5Zte7LR75FgBjb/JacfiPrF5GtcfYBI2l
5OmA+faeZbiY9zknSnn+H2zgxUFAsotPO+YVOUtVY+qv9i2/pVzR9C4YzoUkoj7+YUAuR/YT957F
/AxQSwMEFAAAAAgA0it8XcgiKnmECgAAAAwAAE4AAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0
R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ3VpZGUvMi5wbme9lns8
G1gWx/VhxnhnlVYRRB9ajdajFA3NiKp2UFXPTEZLK1GvUZGQiGzTQcZz1BCqidBWKdJmUBXEdFqs
oRJBtJSYoonGs0SKko2xszud2c/u/rX/nc+999x7zr2/+z3n27MermrKu5UVFBTU3E7BzikobOUq
KGwZVZIPKFQwFL9WUFBpd4NBz8cPTg9HRiDiDH6cF4SJT9ZD6zOQl7osEpWiNHcqCndVbTHR6CwD
4a9lQC9s1WMbsU9oaR3ZfXYrQHHc7XOz0QySKfgL90BLNwWvRxGjJMyx1/oRl45csrjMBQbVIhp5
mPrhSDzHrpiTHjOE5/XGrgvWpLNPi4vubFn2mtAxQmlaK+3enkmHcs+GXUn7OqcmM5by6ENQ8I37
Ab2k/Jo71SWSKVpBiRrVbVC1WvjTSOHB22UoqJ4V1pVrhPL+btUEBdkpVQ+4aoTqzcbvke+m6ulI
XFwrIboPZaChM6ctQuUL3pif13VzURk8xtIifQK9TgdsnKkmN71PHI164n8KBGpaSaXHfh8LA4Wd
ydKXNAlMtlPXaNpglCa61YMrP3DT5+AXXsSHPPtQ5JUKwWx1DjU+59xzbl5PrIVTEFT4ODsfCjQL
5L7suzoHMRElgt3ApYrUe46LX94vTaKE5Jg/5/4u2w3z11g2zO1qhcgBbBQnsCuI/Ug8dFR50L/x
tHwOfBhxl54Zd63FtFYMDwn92DvDlTvtdm4BN/DUzo03PnNDoms/GW8KAn2V2BGukHudni3zD4HB
rPeoDMOvHnEOesdbIb8fpaggWfXjo+k/TfTsAniyG5pWp5EtuMVvxnybdgOYxgHzK3tTB5KWOsio
01FkMrmiRm1Lnv7ityrAZaNS5tJPDNtZ+NyLLGm9bRf+AAiEoS1xGUst5us1Qx6+pKwJh4G2Ifcz
Gulk8vPKrIgXI+wJeOODLDL5Xlb8ynB1p3103JAu+LKMIEpnv4x/clNqPo0bY0iJzUbBfHBREVZf
G+BdbG9Z9kq2KjQbZU2v2DhTyqImtRr1suwa8YoGyP7zfn57n88Hwp59MDEJ/rmrPm2wJrzrApfZ
tLbKCfpyWBLvh0ajMWUApi3otTz8Au7FKsTl0Hz9+daQqHTabExfa7jVJ8fLWZVzS5BUuMTrpRVa
0jpZEcsyLAZiNRK5tfF2oNKEW/vCG9mKCBacJ4FoPKhuSJC0QRrXl67vXcsqhA+hOTNUDYY1n8Hk
UfQJ1ERZHnZEFxBztWX/vmr2xP1KUH41mI8aklDn6WM872j8SiarUMgQyZ65ewNfJL26LGB+U9Z0
wzrbr06m0TfUtrZPevzUcIEqo+RPovjVfBJOQI5XJeUMqiKuQXYKF7RrHXds6NKGckenh9TtbYgz
zxtY4d/V3VS0yaZI1Egn/6U248qple7pgGZ+PQ1xm55ZV7nDWmnwHc9HmfVjyHQdW7vawuoPPhDH
Gxeb9aB+OE7HkZFMuhkxyeN0ku2E15hOxuTVEEFNBfxSSvcFjluHp5FIOV/d0nu/ob0CFFmPgsCd
s7P4MXY+Yn+agBENoXif4VxfGZH2E0UdiR+o2mjAG+G1NOBT2vRKaG0asJhG8PLXxxBUBv0pkWlR
PQsiphhvfXfb2vtn2KkubmHe2wDusnkgR56Yn2hHJEkHTUvj19AXztfSFNVIjKYD9u7uXFK3Z0+Y
1FDJ3rYTBVH57YPs8sEQkCQKx9JZWCEkzYzqoJNWz9bSAWivQ+90VQJ7HAWqD8V6f0z8t8+ltBvq
7PtSQoV/JYZzGF7ctkEf5d3bIxMmDyoiRplLgYK0NlW1j1nyu5v/bi+GIMxHCHCYTJINn3FOvmXn
Gb8Doq3ZdYj/7okkBQls/s9RU8EdbCdNNBDnwZKd4C4XFOc+04fobMgmbHqFvyAqN5y7+JWsW5l1
AiJHXKGf03jRpoRwr9pY63+d5cbavZRAWJ+8P4kgXLl4IaW7/M44FiTKWKraYKcZhmTjomK/H3Iv
TQe9hPfYBKvnBliFlUj5zG3eNTzw9Wc/l7SBd9WV5v4F165KrXCzBy8PK7HepXukzkdtp+Yl10pS
6E92Jt8Nf84PaEZRdFlb8ebdQjMUwTSQaySKMP8ncA82suPCUjY/0j/y/Cjlv8kXxOJ9H0iqkQOm
qJDpg3IxPWpC55HM5/zx1dEu4REKtkSHQQ/9D5MG7YyVjlNOi4/GKMejUkIjjp60Vp9fnLVvieiA
YpoeLmd8m+n8wbCa6EAooXdkpTx+fQY+oLay6ABOr1R0D51CWMV0/IAS4cZawx0hCW8Ls5cI7IRZ
Pxww6pRvxNrg4lNzVLoBxRCBb0sHANw71AAAizgMDHYc28NMvVV7tTMJafqLZtCOc+bujfl8MGPt
uUEuCPTGBVYFx4rjCL76uZzJBcXXQgEZNfK+qxBuQrMT9rPWDadmfKiAyEhZPG5uIe9rsu7N6wEx
h9IPCJtX/WGwW0tzTkNBsuUSwXDz7ORSnRDIw88NatGGa+a/JxJnuHxsUMAcv3nNid/WP6mtJ41o
wC6N3jP7RdPK2kT6xjtXx/UQvvYXMQDAcXnWQ2lJWLPauXhc1g4htLRbVCfguhomm7DrliaOSatN
kjWnFxx7BtssmF9l9qlT0GepSjdz8ONrd3NNuotf/TB9G8CcSAXLwrLJkc1mWZ8JpXa49UXye9gt
SxOQ40theRSn9e026oNvnA/ZHXus7frsTiu1hUxu4TRGn8HDYHhOr4FnnxRhaggEWJQInfCrxIfD
FgsnhPJYoVbBRfz2ZLcbe8JLjUFJi9179daHctarpMtxjepz3nlvGVVDUhjsi8xqEwcY9/tw0sz8
zwuAyPkxb/XqtLIRoWFloOXipwU6h11h1lj5nQGxGVOaUG8dA432Bzxr997F1yjyMWN2fTOh992b
kW3AYmIf1/BiVGQvpBHr+NgSBGJUsPETZbI18bpZCp5MP5Du1GRxe7V930DrTWmwT/90e383YZxH
4LQ8nD4hv7iwOKFPbxZr6haLTLZzcp8pckjg50U+hchjC2uNiZTWP3GsmZveH7w+eFjfF4sRv2wW
jJG3rQfz3G1pczmFto59krZ+cT7QYv5O9PEjU86nKePvkvukskeJQ/FEezfOdWuk7RtvLdvzg1x5
aRqqyXpyOCjafLIcbjtsMTGqwRwvb6Kp4DKJV1CHnxqHikhS/Z5AY71L3TftmaryR1OOIQSoM8d3
CSbuVuobYgiNbV8y/9ySyPlz/bfeJqXqB7GDFlKS3hcqUp5qOFb8gC4p2YBBTcOeOrIc5Cvc2Iqp
/6lwpS93DsiPPAnVC/c7gNKslcewo5ZpPrczGUMI7/pPNJXXAOFSFYYgTkD3acyZ1hORigj6Zl/n
Aj4sTo3vBAXKKXlUvZURXVi4UYFF+qdS41U2mBWaZgNVsfd0ESf09T9WDPFCg5BQodRMLsUT/w4q
osSCyIL02P33M27TFCP3DCcr+4QcsnD+XS3PTrbZBu9rvJSykaHsJstVPlZUqpKYej+DslHObBQb
HEg2oTOZdG3EK4fc8VUZOPre6Z71Uj9dB0hRiTvvqk5tWf8h1MOUj8B/1mJdo7wUZXzfpenoRmvv
5uIBY3x+gfR3UEsDBBQAAAAIANIrfF3lmY907BAAAMoSAABOAAAAQ09QWV9UT19LSU5ETEVfUk9P
VC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzMu
cG5nhVh5PJRrG55CKYQIM9nKFoXsDEaRYbJUlkOkqYNsDTpEMij7MpZGkQbTGCrJljVjqWikQ4Ys
2WaKjqFhxjLGPr7hnK/zO8vv+/55nuv3zv3c9/Xez/089/VO0nlbC4H9oP0AAEAAZnnGDgDYTQIA
dn3h5TwAFJfxBAIAB+/Bzpx2uDU8mxcV7PBbTnuLnvwxS17SQVdEsiNJq8QCM0En2hXaFDJzSyUz
pM8xRS1T7tyuppWVJTe8LHoq/SzRday/lpfX+QRbf90Ml+gnElvgObj/aW3X7YMupbu4o4Sv+LjI
MtjCj7UyPTSDqGRDRgSDuigexDAMJS9HQIwWOw2Xu25BAfTzRFGAKZes9s6wM32Ghh3cY5Clv0yi
s4WMY7r0U0lTqN4+0kpnbgZunxTsEX9qd1JejmZBfA+vTedDqdg9p7zthBZjSCu5o8CCb4BYxc2T
FrwCd0iAuK+TTpQmss1IUrDpNQUgEIQV0eLzPHMQL/xIX1Nkx4RX4I/pf+Kkx0a4Cf8kp1CaxgP+
2YzuSpq66cReqByHbnuVfFEi1Dt74zUVCfuusjc+A7dLCAT4Y/iB/3y0jWXZFbSRi+iwX/UIzUA5
UxE/aBInjE1YxzHhR85KK2ZHCM13+f8b/780KkUbelzdzq8PqjwBvhV23S+wvA9cLq2zkOVvGEdf
gBYa+0beHpfKizMKHwjzM4JJkbVnErkgrU2f1m+vtdIPg2uNN57s5kdaAtem9LwCJJsfYzNnyTpN
aWNj84zWSvmyb/yhatDLPRHdTL7ombOW8AiT4ClsAoQcOPZutZayMPdJGdb79Ogzw8YNjMtFnqHB
LdPWPOJuRs5LWS4Gj+63siOOexf8hiBlN9zqRYx0F5eQ61eKet4xTahtsaL0TjS+1sfxWZWIXXzk
0l2ETBq7NzqoKK/GJoX+eSVKXHUDk0kVoxQ9zUfnP6ysqvX56qbetPXBs1ydskBItmKzStBg3yds
i8+Q6kmK/m/AdWRt+dart6UcB3z+lNGb03Wg29KMzcVVod0yaaT0MZLq7MVNrKs6urqFLjVdo4xR
Z4zRxxoi0MHF8oihl8yfnvc4a56vp2yORvrQvnk9VaYhee8K/mZ2lWbTX7IcPLuWwKV3tpfYgxFs
6v/cxPw2tIrw1SZ2ZlQXN6xmvLK+6TfSwCp71rgM8G+7N/o1q9qnzWovJTcMSb83s3iEG3Kff3Oq
x0vRkqrmM1bBsPZpI/oKuLJHWRDQgaHzcjCTbGbSEKNra+gByzwFG6gKGT1Eay/+pSugzpjyrHPb
gSgO3i/u6YFisnJ6V3xhrR+H+i1aG0Cw3jKGLoOO7rsrecPjdeBgamZhzkiItsriNnvzKcHgjbYW
trxPtbzP3DwExFrZwMwrDXwjZMil8UvQqxRgXsX2OdRWXuQxneAHZF1j6/fUfgYj99XilxuLEX2J
Slzx4XXyPunPX6YlCK+cj222Nnm/WTbXjmqfXSMrPPB0SQfNe9wJtBoZUfAp9a363Yh9bXUcExW2
EgMf1avp/tRPZtUyD9sRp0bCG8gPa3bpbGSqfPUTFPKfnrqf1YqoqotEnh2YP7lbxkNgLGzc8IXJ
pXokXS7dsjcuovbwWlwX1epcp/7qypObgsbyAr4ubi4KLvYREe4X0jvN410fNeJP9z72NNsJHehv
67uGvYiVNlorFzOiLE87OqWe3WKHbPBhZS7rFHvadTRZFolq2RX3Jdlmv6RxxbpikZ7f3x8R0XV7
EGGEeh1uS47NpWXFRTaDbUUKdDafNcEjvJRHu59Zk0VExHCUZmGXjq9neR59PydYksK/Hp5KKvrp
iQ4EzGXqfsCUS7TTS25T4m1ZQOD+2D2xe6yuOMaAhpWzV/uSSWEj6JeXriGhU42wmuETOhB7M/Hr
wfy+DkjOLXH9jVdsSETNHfN0eTLC6TNc2rfW/dRS5LrMMNz2qJlrTBK2Gxhl/SZW+yc9y3GVhOnN
dl2Q7f7RK7gudJ8d9mpxtoakeuUaGscH6xBgiSUn2b7lzauST03oWVpBkdioJy2VindLJF+RW20k
F+DlBybhZlUf7r3vRkUQzHalkiRSu3lTeziWX4E26u48dekHvsW7yWCMOxXNDB2CzwfKVltBJ7RM
CR7aELnfIZdpTJHyI+5UkhqQs3YWvb34B8xVh21+JygUUO9X0DpGRc/HdxtUultklZcSVHlTu0NA
s0HHb/OZxqRCR9aeHhIaBn2f8KgOwNKEQfhZLRCWL9qNsmptN9wihy0/Bc91ozzuLYNW7f5nKKm4
HhgyIjZEorty8LR38oH9B2KJ3pz0fgP9sAPwInySFU/L/Y1/VdTnJbdj0ya6tLiXcioTWZFbUp6D
ehAtaKzt5Ret5HuHPuc7h0TE8ECr2g/j8GrqrdrgU9ihpdQeBT0QNkW+uETSHDpSWPpCh7v+JTFa
Csi5vlMUcxlOlqS/pwJFYklIZR+X0xbNvWx1k+eUd/gOz5AO7+1dRxG9/oCA2Fpt88zHwsMK+Hkg
zk0ThI2JdaO8sx+FzDWybg26qwDBKtiUkddoitgDMWvzqffIJ+28sxJse+3wRmEw4DtCAxyAVS4Q
Bu+BTgR9qaAZymqy7lJr2Fmv2to5BIfVNFOZe1zuseaAOPc4p7aLp7xH7IL9vZp25fPxIrA9F4xE
hMCa+CakCCdD2732985LWC4miY4d2O5MprAexTshd0i1EojdPnt57D6KciOqs7OfrNZyxdZ+z7w6
PwvA7VXcFc5cKQ1AXkPx2rwAKmw7+U0Bf2aKu/0RZY3oLWv2l37+r/hU7pXBuqoK2mHs3/of+E3l
tUE9KBfwnz30H3icm9DsvqsuIBPntmCAM6wXHnYzOQni/JJpamwM9eYcB407bpRT8RyBANhWCX9M
/4Lv1HOOstfXuub5HI2j2pXX7m933PvZqIM4EUm/SNph/D/b8b/gG5yS/shx9G+JcaNICHj8iPkj
9N8wVdlrfzQxU17kkuGpqbv7EC1urTBXTIzPIFddgP0v9/uoqKhDn9Rm2Ee1IVSqj7/9IiKhhyNV
8vTfqsAO/2K08CntKAhn5ae9qaqTn0mDumtJ11joYXIEbSpnc3MkNHeyH7xPJW1GS9o+gcRal+zQ
2oXDLxgMWhjH9PBKaVkLe+3CqVqRrsm6V4EyCriiRyzM5gxamH6a+d/uVXWQKlkGBAUDEG6CrgWV
q3aFuGtzHFbX7HskmkryX0X18M5mdUtInZhZU8tibip2NauN5IbsKzeoSJt3paxcetENKe8Z7V66
ztlzpXYvzqbbCp+JPnDcPBMnYtbkBknw0G7ZPn0LBqL41dIAlFrGz+IzvRo+4n5fPhpqBidpiF3a
JQSu4N45aWcuBHrAufDCYPo2C8Jv/4PQXyDnrkBEK5rvGAdrVNAIJ5MpE3mCd2e4vDh3g/hkUOIm
389cfITm+SExrAanmtDHq7sXNBu4pSyTtyvTdSIIAK3ilETQwXfRbuAZLiWzBFgfpEoylXThqmS4
VKztrWjbcZqcNs9e872mE9u0CD8YcirfGfMY9i+0diBHdA4oetsFc+ShoXjPzPzHmDUmBm9Mfytn
Js4ISlq3SoN6hyKJ3rFq0hjkkzToVK6CsjF0qhCIcIwuUzKn7iM0r7/J4iGgCmKKDmhWn7vOzJH8
3fV9ybhVvz2B78uey2HJmbgjuh3pnAzNq+kfAwsN62y/59gCEC88rLrzyjgY6WWoFIpjocZZa3Ds
XH31q4+3ssCzS4ukXxEQIPgGRHwwi52Js5ow8yt3LyZ33QYVzRCKZz227DeDDYKuJBGU00ENAVjg
HiA4rzblaXnqUmPuh5ABtqRfSRc7S419xHMqTMdkbrltW81ikLX6IiOjFpR5k9PUfjyU3CuVQ0q/
DZ9ebXdgwG/nbSxNk5MPlUMcp/1k3ao+uk7A7BL0unZjVW2iix1UHM/izRK3bBm0aUFCwNRn1hwm
8syc4y+j9XQlvxbF6SSqIjk3gj7VeZy4talOWKg/u15PvDnUTqd/hoyiN66Hmbt8oPOIbF1CNY7P
GX9ST3wRz8qCL4RmWvgxVL2MyH5u3l/vKZVE9veNl98f4shgpd1LxQfFpEuRDSoXNj45fzG2n7Tg
jlJHsqOXA+6VbXnPv2qyjaBGlTAnsiPSvMYrp1+Itd2pGMcSY7YmF0FEcQu/msia5s8IlEY3DYvS
IDrkeaE0TPLPh62ZpzSgNK4lPGJ1rnyejnr1RsI9zTjwjQ82n7JUqaGkXvmMuoQ9adjHHKjBNzl1
qfs3Bnr3t3mlahAb8cVEE6pnRpitb5fiyuq+e5cCVCNQJ7aSkvTZHH8hNjI6zAUsyxfjb4o7unKp
9jh8fnBQxsDdk6FeQHc+Ou0U2jQHP/SnWM6eLL0f2bKSCpmY9x+DwBoc0LXXL94+rkwKiU7aImBH
1BF5GzPVL2rfPfyy3IRj1Y7JjG3lXE6oUyt2Zq4L5ksuLRyE/VDPDmvTH7SkxwgBQ7/K5PuCW2xS
iQ+BaF1HPRnN7GJ/hOsg+dCDZelTEjRlCButm3pr+gtGK73bGD30E8f9esqDG71wJqTBLvRjdllp
7ssNfxiostKlNcukzs0Fv+5/f1K6qbjcT+Cvupo3M1yYGK1ikrji9ELm6QedljEW0h06UmA9h8GF
UnT7MIPhNyZv6sB6H/S3GMrCJkoUBAypZj4JZQ8Ky5fCKneUdph7wi0y8qaze1opxY3feTXBVna+
/LASTKtGrgpxQXGlixQElllntIupfYCMFleF/zTGCk3L0HZBa6/UB1c0uqCfx7NuVkpjo7Saq6hX
nZjK5YO98f3wQ6whmne4pOVG+HB+ka1nteoHbizw9ipfJvWEAe2uFFrbMgpdWNaKfl7tiu7DPe9U
4jephaPB6UxK0rqhF93o1iiSkrwhnv19wgGOn71xcp7hQ1AibBMSWcsbiVd36se3T0pmatu1ZBUK
tCv0+9bIb3pseUE9IBNVLkqwc9caDTY08DBCcyjMM2cgW40yNHeZXq6ZXN99tw0+TFaD+Tlibq7+
bD2nxMyNERywtC+P3DwNExe8uNXKte7UlVk4tEYfT0vP9+29ebH7YVF41mxUwLs8n4TnTbOI6WUs
qqduObhJw48raah9i5jIlyY7ri6V1/tLPYI1kH6uw/cSal9zLPtrCrzZFs2+2Vc3XITTC6WcXOgM
QBaf7W1zTSc7an1/tKzeYkxTznx0AB51bSk3SU7FVgq0FtdEFVyIDP4+b+MpmGf8bVwJc9YZbRo7
n60YRTofxp6IyfKMqlAhcpuYtkSE9y/kS65/kZkE+fS81ThEPTGjETSdThQ0nH3LaNTXX4cdp8vo
1U9+bBdErS3itj8d4DkyW2+pCU42vjmxJ7NEHDaWOpyepElqXv3kOIRI0Tgyrgo+Xo4hnIjOBmIc
0Z6o+oxLuega1wrkkslg2xmpLc6naEl0VNx7lihZb+ZXd5ZxaHnZkVYF9LNxmRxSuMw9eR0doZEz
Bx035ETWZM6Fz6sWNd8wxtkoXnhH6ULQ+0hZA6Svrefs+E/x2QsdR2fj+Nb9TLtYAmWPVfpET2rY
Zrw20XYfnw06HXGWTKm1+rnj6s+XLb4hgg9GncuhrHEEC0dwyCns7dmj+aeu+334fziYjFLo7MhJ
0hxP7Oa1kc/hsVJWyvq7aJo65q1UActT0NzRcYv+HySPcObMAhEjM882PqwwR5DBTnceMBXRmtyD
0wC/0poAPpVrt31QuGmhLheyYh2vCMNrmU5o63Jkp84/daFz6xYXwH6gL/C1fP32n1Qwc9szZaZX
ov8DUEsDBBQAAAAIANIrfF174CiqtBIAAL4UAABOAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9z
dEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzQucG5nxVh3
PJtr39fS1ig6qE17Ghyj1C4aaotRrbaUmqkSxKgRarYUrfmIvWO3qBkrMQ5KKCEiqGg49ozZ2uFJ
e57zjPOc837e96/3r/u+r+v6fa/r+tzf3/c33t67q8PMyM1IQ0PDDNLVNKahOY2joTn1Kz11gOZ9
+Rl3Ghq2MJCm2kNfIpnkb0F4lofZXGe9oDmXd5ob/LcoewwbthtPkHbetsvIBjpyXGyaHL9rbmWM
LrZ/mPw+N40TVlWbUvxoM/OGXA2hjq0WXRmPR/jSPmfXSqXQJqadomNL7V3fPhZeUBiIxm4f7m30
3Twf/ujlwgaY8Q6ORo2WjvmCLD33Vcgvw3upU2rantn6Bf7HGrJlBIMhOsN+AJY/PTvtsgnkLl+U
rJgsMANm33TLmc0QlyljH4E4FWLPAA6iT8/GKmtAFe/gxFX7Ln5HJEQ7BK2gv5gOefUjQfadvN8N
7a803Ur4bqhjH0I1PEvP/X3nfxzh++dVyMvv47+d6Pt4KOKUz8zTdgw0dbHKHAvzaF5MO9fLSJ4o
/mxQmmybCo3ZyXNgnfTgpDMcoOL+21Ve/gu/xLEyvg9wARnVLQeFGshcKgnsFX/6EuA4tGxlNCsV
T0e+xijMbMScib19AelMX2f+wcS5oPqDSem3tfQv0u0oE/iV2VbiYlanfxooBHa9qsLEbziR9hXq
m4Xw/BuE5QOYxZvg1bMgIqQvEcDVNSjjAACNx5yIcnllTW4y+S+Sg12XxkWncuCJ9oBEEjcdmdED
Vcgrtjc/IQll2V8hbrPqwl0bYSQp0MFBsX9GklXj15E4Vg5zODrIdOyDGq4/kRslqOrp/jwPm6sd
jwlyerCF2WvfFRQx2ywcpdy6Jj5m/DcpQR+LZ/Vn1ZS/gcBO60LxvUc+JgEumabVBZ4Cr7+JASvf
beTnmu7XpgUP1HU8muSms1xHRYCcLnk3wU3l1/bmzy25YQRaNhJ2xr0z4urrU6qsWh8FOl/wamZK
AuxfeeThHQJ38eFVKsrLmwaXFngON8jRE9826f9047ajJ9TGRm8wnpCaypQS+jWj9uMHA041dF3R
gRVcno3YMi3VvbVUss3BASGVCRqwqaEjVniKJT4Bt9boI4CYT0kqrNZNt3oc1j42F8cGHrYH9nGo
oRvC4x4LyzLz+D3xHA8F5qkSSZKr050svQET0Qz0jc/tz25r4crX9hfyuDX7gyaPbQJsxx6ogzZP
OP1q3SCrq61SlrVdMqq9ksQ1YxR5Ro50ro8InP4kHM7OXZvbWpUNugoZqLI6TKUL2eEN/CpgoO6y
ZcuYuSxT9JKdypt/0vFfNCrnGqKU2NQ0W494iSF7IuVJh63Y3XlAqW3qisDNJyx3pViT2dMTzpv8
CXd/57Ta75h3cP9BzR97ydl2xZ2WGYqQS197OtD0fyc4sqdQbtn0G8It8GTdoh+hKv2EjgxnURlU
/HySbuUZlER4MdYlWBhRE31qLjxcE2RcbOJzWLu3qGIfi7AcVHZZWO8R6z4Cd5HhX3H5D/ClKK3Q
2uZ0ZLqUCRwfcy61jTjVwUaIZI1YMUpAySslJqEs4bLBRl/k3UCR7r4+k7mlAD6Z5NhEsIrDBD1R
bi5uqG8BoKW983PWqGFSNNQxST3dTvoZVNHC7NPbuwNEiy9yxwddbc2jieMaHK0wy47uJQe+c1iX
UlbmDl1bfrNcy49CnWMtcS2lABdS+l5qR+VzEP5V42FZCi+dCaS49140udO1dIfDrpXvpthoECEZ
cKJQzdrcuN/QgXA8lPvsVMvyA+UZ6wea8ShlQC1vkB2x7hiWb7I49ha/164jKUdfhuvnQASgz/h7
IVttDR4kU96RIhMK9vRZToshtym2u9nKvRIUHLBilvXMTv5WgLmusXu+PvP3yW/3I7ErWMm5zsIs
8WoJGC+713ElYC67hXD1AnKbmWHi6Xa1JcoqimEDr4S5b4nUg5sk88zm1/RdU0Pj+f3is/n3zNYa
aa2xKI1IQk1ySKDGqHJs5GiZVoTnRPq1nqB7qVWewVI1urjymTbAZG1gxoHWjq+KRvqvtYik4OLd
ab5zJJXlr6+Tb3TtuAqNsToRlNFZCpOPr0E4pJdTerJOU/L8mhvMlluqdGzuTWIDe5nNt/SUJ9+I
OJ/vscVFvsKen6+U95132Ncat6wOnMxYUmHsO75oqiJVhmsA5whCn16iJ3oepWb2U8VyAaKwxy2U
m7yZpS6MWpGY/0vnEPl/cQ5wng6P62/eEWcvNc5N1vqDexBK3U2PcvxIe28Qz9O00Fb4cw6xzTmI
541MXhQhSxvOwQVB0LXwAtnrbWvL+9o286/fmZa+cDDrogkJrzFdivYRbV4+NKvAfKwgjVeGlFId
4XGu4eIvGmSlGyWbLCiVBJaNwGMLQVP2LuYM5PyoaWmg6cWRWjpybOTZ+jFrUlXcun7AZqZYBR6r
zatbMltyFn1FbPUXO9OMoJAWsHCHCzR5F47T6Te9VdlhCK/uiEiyUBq6HhCU0jSK2RtxfyVhiMpO
zx7b6JSR56iZUT96qqALh8W0tjx3X5cTxPicZ3T7DPPSXnrX6PIt15ZTBBYK3cU5aqvPU7C0h8Ur
GxvJx0AfEF5pxhFk7O61r1x2SiCkzMUwZfKQmFgSAfSRcGwnlT51sDz2/Hjgm/For8GUI+lDuyKJ
RW/yC7qwuKAcjvR2nn4KTzb4ORk/FDw27es5rgZjmfTQNW/1ebJu4DiedXLeowGFV7YLK/d/dSWq
E/z2XnonuOqLxHuN6RU077m51xEROd2MwUamZnrZ9oGbU8qUnIyDrdXl4xtXojxh/EM8A8rem+pO
i8lHfW2db+EEl+HjkNV6Wvs5PX9hc501YFI8m6USlBjETI3HGqtnx8Y5GymEidRQhTPQ/pP9kZnY
cW4MdXdY+StaQRDlbGyL7899P3lDjrzHUrO58LhcuUZT/f31MkKHKN9Bd+YZI6uGC5ncRUK9KmMi
oH+qgrmFrGs8oQj7zqO+jmt24xk00NM7czvnhbX1BxgTag3WULf1/YZuGR0LSRI5GCZGvTh2STI7
+5OD1fV2/oPxeKl4S36KIX53Ko4/mzCVHpTTOC9K8b0HnghT9WFNIACWGwDPomN3FKIdP8FhELCg
Qh2XXYW/J2hUdN4JRO61tNznq1ZX1u8IeZIx6TOl7x759bA9BxrM6TRMAC9tLMc4j+sr+cVpES+3
Fo3PleG9jxN/rSq+lNNcaaEPD4gCUHDNstunRUzvs0+OwP7WfAG01bwhgDH1E23WoGrlZtzeVFQ3
XDUoCb8RhgRKBjnWxH9RvW7XttZHnrl7N6HAEDu6enJg1KlfUp9SdwtgNXpcvO+M+SQQKCIpQbaL
964CnBGrmc4gspRE+oBGzhRLeEdQ0xeTlU1b21yGIReWDz8boFrD3GbLWqwF4tkalpO7Lr5l9jFd
eRbhF6yh88vlfckk1fTyUfDpJuRduOuIOqbi0KGXuWRL7FVLSsE3LXYSVRbhgQduIG47z8UnlEZv
Tc3SDaMkQRF5TeOZEeESV8WmkIUwb1dwb1hxL1/0PxRTH++7Lpi/m3XsPdYdZfQqJuswiu/so8KE
E1S9h6dJdPkGCwMxafbwtZ4xIngs97KoqKhEnZ5oIsECTkA0RKaKNRb1n5zwGKoGFn1pY7BiMt/3
8ZO0giu12IqTCQ3Yd1+j6hezSP3julU8D+cmpat8oUNXOtbOlyxSYR2bHv0MCiuGttjnqP4EEnYp
ocepigu6lvQLzcDHo1GSfgYrWxiU2+pFToKPpzUI3/CBVp1CjDWzqivk/tznzvswSXFAU/6Nn1Dh
tPLsIxYHBvwAHPm+cvUeRkCV/3rPTsyGZfBjxWYlnnknoGEZ2tRJzzplU/kqaNnCT8oQ7rWQBSd4
vgG812GNYO7BePCy2W7/ZLQETOLfEtmP210dE6xwf+gVQY1u+JbBInbhOMrwjn/z7kohu05sizJm
HueeE2Z0vFdx2Z8DYNEllN/iV87ewyDn2/aT1BQh6TiQzrL3SPuxA3J9T3e3iPoPbwfYaxsUv6+n
S+FD7TzL8VmDjE+tvWi17BfqiPEb2ZnNHxY42p0NEaMcfvYg1L0/XhdwklqUzHJhwTqjt2y6Xwq7
VirKLh7Ut3xigJIccOyub6iCgwB7ZjwK3nBpCzI92H1BjUVjre87dxqrmYLZHtc+qXs9Clh0H48j
fAgA3z4jhnzSCX3OCbVdpie6cMxvKSAcQmArySQXWkPcR4tnyKmvBjh+5M0hGTV/nFBoNgORosD1
feizR89Ld6EEBMk/4f7zQXEcHbmLybMxbykNQWqdq/7xhCXcVxukrnVtvTk6EsPALUGQpidmD78L
lfzs3dzTUH2iIKb2AIkR77NfGXv9hKX04lpmdeZXd0OYn+GeTJgJv7iYrHBjtJo+tXiApCGwI9JS
l2VvhCLG7F4izFIZ0pMd0368Z7FXJIWlIYCON+TtCp+F7BQ0h6n10rlkCwchqecMS2UgPrgCMReC
jDy7ICsVinDkojPspSPn7nN/XH27Bwy7Cokbt628cxkpzG44sJoLzIeEZlJN6vlsek/9iI/+i584
hfzKivyTf9UauP3YBLKr0mlvXnu+w84ZyQH030vuuArxK4L8RaS9/6ATeDoYfIWeqHWkcr2u0bqU
J5yyzgVy1G7vFKuOPsUeU89nDD7eSSKnYcQwOq+Gw+dmBvSqH8MqfF3n50gdPkZAxZcvAJDRSqfX
a2nuTzc2VwMFFDwaRPP83NbEotEUrvl4hGVHD4PfgQjohrlXLLoPDanMcLRjJYtOYFekx6fu/Sie
wj38F/lC23nq+LJsVTVXoosFQW2DfYJiSKbPZddY3PIGlmD3DuYnbgDJrJJp98QLi0+qC7eu2YTB
UOe9vW7Bf6+PKIPNlz9c383+pBtZHkD/ODdL0voUHAlDFKgW6Bu7O6Wmix/aFVMaOrVmroBciNEl
v625s8+i81sx9OV4kcWwzImenrhPhOQAmCvNa/TjXutRhXYVMydasqreqXEH1z+qU1oiJ/E4jZ1/
d0QRJHqr8+ElpBjnpYaV/eVotBmT2O2Jh5P6eD8T5xAYgxqT3EpLjM6AwOFOkn4Qfdc/hUs3Yibr
aLQ5KaMGLCtjxuSblH/lY1ba1x5heIGJmyX4MUZBSMJS9H19x6b25YU4PjHmiW6DanV0+ODSAzf6
HQa0832/HH1mnnrvO++sx6V6+eIGXghVqxFkRPqe3tjoG9iqOeH3+EPt82el9b94kd3j1Sr6Gbqe
IkdidKnOM9w9dtum0CcP3+z7xpp641xxKjXvwoLOiv1vcrd/yxN/X/Yq/eaMzqu0pQ5uw90qB6uv
faHPwmDrD6BFj3pvGtRp+w/WRLgpng8pcogU+q8M8DcU+X6ryZ+izK5C6tmgnOFukFGpDOiEtPT2
wvDFvvNq6A/t+Wj4WgP517CocasXjQoJ6rg10Ulzr6Nex1NP1pXMPPatGViPwsyuQXyyh4pICwGX
D4Z6BVO4iyvAevREUq0+QRqEPwekpSj3A8VEsLrdsUybcaSrIK23ZB7tu6o8lzofDksMHDFkQdD6
S3Vx9bGTvwpkpkxqwh9e8JLIj/n6MQBkvN6qcM88JWiSL3G2trBYFtwIINUAr9b0D1SSr5cHgB/n
Pgcx5ycJBkq1tmXSYiacd/YDQHrMJHiOYsOt+wfQFzNaYxEJKqr9mheRTM6OsyK/3DwWBZ36lJLs
vIwcwfIbSIwF0xXvuF5q7AsuRhpLRjtzyTvxP9DGrU0XnC60jEwpOLZtnddb5hd6DyI8d6znTyyI
SCsizlOrtzwNef9FLy3dF06CoMjuHqZkdUFQixYelHMTxOj0MbNKHR0xHDY1qqt2YAlPLLyKdqYd
WNA1nnAUikSQ2iUfyBobcwjq48MznUPI5WtlrIAlIHXG0vr5WiyXAr+jqhneHZuR4T3d4RtTKSD9
0EhojveFv2jCo3FfPhTszELSca6pnjMo/SgS8H6huEVv5VKrOlwp2MdKTze5wL/l/Jj1gsNniwqN
7YLKHTn6JiXYvRw4q7hek+3gRPviOeFDpegX6A78pPltWcUyvqFORvInMS+suICU6Fv2dHYibRNu
Ni4+QjWt8FwqY8gO3ZibHnz68CY7HZnB/oASXFTOIx+eRhVSnHS84rvLTSzMf0rdAQeUNTu0zjrL
GcVOtNPKWDNVy1jHgkw6bo6q2tTxZoJ/KD5X2f/cqvov6D90ov660/XybWjsvGyGg1DTrThqWMoE
2bdp7btLtDH+BzhKpcATjFXSL/vhbPtOn3gvUmfFB4Wyr0n2cwAvf/9Q62NR8+xP5Qkpgmz3R9t+
W5TBGJWkkgVQHAux2Wa5ZgU9aQjH9HQGbhvWPx6kITqY9g0lmNALyHr4vTEJ0rqrWa5uE/J3UEsD
BBQAAAAIANIrfF2vke5NPBgAAMwaAABOAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJk
SW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzUucG5nrVl5PJR725eK
FkuFZE9mQoqmIVuoozAKpZBhqKxjyT52c+hYKpIbY98yyF4MMmMJIfvYaxgK2ccwGFnGvHrO0znP
857n8zzv+3nfv+77vj7357p+n999f5fr+j29ra/NeUTwCAsLCydM57ohCwsrkYVl35dDewGW/JKD
riwsgrGw69fu+ZAoZH9zI5u61hXqxDkp/jvLorb2Cshp6QorC7/47Mk7/bTXCLZrq0DCCw/5jktp
RchLesXnoR+OjrlrpdgaDrQPyN8tPB5tCwUn+mqusNk/c/ftFhOyp3KeOS1UudizLbYBXzDtGVvY
CAj0obNexhy/Hehzh/WY/a9X9x8QPE08TWQJZhuNipY0t+addIo1Z8j1XsIm3eKxn7iFNdWMtXNo
5OgiQmDQvdvo4kj+bK1Xh+WttLwOyV/NTAp5zR18tifdTBwjfJp4S2Mg4kdKqZT5zWLqGUu9WAEk
d/4zu07i1Gergi/NOoA9a5eS4WFWzh+1n/xefa/2Ifkfufb9r8IuD6IudPiVs253wL6Xau0quDis
fhcigHLMMEYdu64xIiafGa9sTHkERFgRbn6mmAp8p16PZwQCvdPeLOGvnngRI3hiVmjspcvrfcEl
6i8CzvvWu03RVup3TFY4f4mC8L/mCUYpj5yjxy5V7If3xA906MYNjJcVIQHa7pjGpdOvBz/gHBXI
MnNZK1EMQQ6dnWmNI9uyTg7191GL5cSsT2wKr85ioafBtKwDOZfmegD6C/UrXW4bc/tSwHME6nTg
9wdteuVgxFu1mpn0Eyknh/OwLkEp4jk1b/E8Txo4AslBm+WUcYFwERfztbFUptRkFvXm4y0h2NMm
b/Nq29Lmdem5RrTdp+m5nEi24LqgazL9GocxtMv2xXPSyHiI7auT1Lia3DyReRmEsIl7/8n6WPl6
zS6MQUl72cL6qIpZvyXfSB5u9s2U6oxnO0tLyFWTX03YwjyFpOYym8a+AWF6h6LN4SZbU/ZP9SoW
98HaP9e7Xi2PDqIo4MI9+h9tx+2KI5cTVbowl60vHlpbF5LKj8FaCtOXYtYSsXBnsLPc2/z5gLrd
FTYAO7A7sph82dMB7pTRtwH46dD8XzZ80fvqtVos2WYATFoC3S890Q1aDk/1wIwlb5WVrvGEKSlv
VJ5lypaqwoUSA1gS0AjOF83+sSc752HGMWRxLpcVXSeHu/UbIfnArtEv/RNbcbyguThQDkTwAH7C
ESMDw9/s84t1MXyqt8GhZjsyCEKz1icXrvmGYzmBkoBulmOzz/jOIxG5tGE8pEPfOo8x3i6+gRmV
t2vo2m+8G6AcSLaGFevOMs4FqoOQX0fLwx9FQ1iKsmSGEB054JvYjGQu0+WKvlfO/kLxo/faLSoK
Hmwsn/Cr1814YidsRJ/tvZchgG9UOw5XEgGp3ybl7o6FqtbaoWSRz6TrejKNGgBsbi8HS3DJfc7K
9ecfo+3IUY6izidnx78vJYItE0Zxg09/y6LMb24P1G1zMxVLPiyV9s3UwnrXd5KjDPBP90k9tSmY
NLqh7ASGdqbfPWVr/88w/jtifsfM/yV87SfwTDQEGE0O0V0yNpPBxqx8EsSSYw6mGMvvZInL8Zs9
2dS3jyiKq+kqeAZFTNd7PrceFXT5CYnHnr9NvVZ1qWE72txSskKsM2XtY3GOf11eeBF3+i/kw7ib
qYrVdlUGHCTShVUV1eRHxecQX8dVNFRde/39pQPzTXNVLIzimozdD15QvtQ9DGDFVNOTd9w/Y4Sd
H500mWy8qDn+Cd55rwZEER0ss7VP4F7lb8vv9dpPKonFjiZVDUYE7LqTc+mSIosmebYzeu4qBvDP
0kqZg7iOUArqfvQn0dEltHHfi6B1hmCzKHa2k1iSkhXP5w7OSbL+jOoRlqQg+ycJEkBNpSeQbi4F
U/M+ILLlFbaUHne2zd/LUjk1z85OB8AHTJsR6ZVP8r1AgeS6cQfk7l1fgBdfDIbKQ3EdAxF9d2CU
BLGPuohj8soIYCjcRRlt/2Ds1txqqMJMbnrk9kQRQzrjt8edO+Iq3p9utK5Wdi0HUpaT+B5adko5
CcQygkFgKa2t4dmI3yZNpXuw0djZHNuCbDPhezoJ607f4DaREEpFpStTvhhyFpYlGQWZ2T8vBNVx
EbTqJDw77xQLGheLgkyrF3tekTOW2wsKks3fMSOG1VoSOx4e/9wS2XvZKhKi5tUYeHTSNjGrQ/xu
A2AYpn3w/tB1kXgs13HAQUFNBjwHgfk1fo2kd4Gl4bAXMxTjSND6s+/StZk2k+z1DAu4B/2wGDJ8
aWOFTi87sQ69IQcW072tIrk4RGxzOB84Ls4UEjUFeGVhtI74S4FnQNIg4u6iFoANa3e9IifBvDqJ
iySG5L7NANc8NnObjXRf9bZ4yHJfk9BpWS40dl6vJ2IsNslxzENdMDX2LEyAn+ItGgsSMYmY9BXf
ZH9xDvtmrqmhw92g2IUMN4wI6mb+Qoop4LE32VwR4IyPK1I0Y/dFFq9+JeAMAWOlxdH487COwZaV
msu6L7FeSEV+feKRU64Bk7TUUzC8yaqUYjAqp2YtTW7UY75yBTizTlspCnxyIi2Fow/7Dnf3aLrH
pySy/2rofs3KQQrFZ+xYrTpltrr+wyyMUPkWXvZh5jDMj2RHSqzl795ZHVS/l04Q5tu1rXM1Im6+
gbQ4bQAg6qmuy2dhkJZTVnB/IatHIJiaZvbikrvn0QQQtV45za7ls9+i5+fdp68CBkfo9m67lDlV
Dm/ldx1fj9R5kTjG3+U8BXl9crV01RnuQjzHmV6srbaMnTmZE/6Z4rhslEHaJ6Lh+2mzJqlDZYBW
P2mQsfXZ+1isM2FTvDkAOnu2frny7tDtzb4J1VDZsuW2h268YQqeCsvzZsw6z1kKczCbr89MTiYG
wOzbyJIxnydUfmvcvxd6RV/H5h7AH6mdZc6Jk9V9rjev0d/njt82HCIOBuXrPLyv2cRz7P+LgzLd
fScysG+uzBhGtXKW8PtOw5OyXJYhl9M9ijF5Xb0WU9V+pUrnWbvwgCP4Lzy1l/GnQfAcbGM4f6lv
93XQYr4hWa3qDqMy468Wy6gS/Vn97zF1bUwxNoOvvanMRZyzf2mRolQe7mDZP9CY1/TvNJaIv0Lc
X/wuJFytaNC72SXRpJ0nGh5YOukaT0itdOxGq3tqAfdmshmlcaUJJO5pPb+poT5cZ5Dfx60v0h8G
vgW/6AV2tCXVC8lm0cyvSVPzloXHrNz1nX1JaL1SGQBLmGDWFKYi9N4axxfQXNIyRN7N1tZODQwG
L1mg/Z9Remmj2owcAcorD5mJb/KX0d4L7r7DFBo9oQLVMlIp2vNYDuZsl1CdYYqWQXzNUBYuemGy
BMor4cJt8MAd/HHXIUDAZcoyPQ4gQ2+s9LEt3IABNml1nshovhRBhGImRWVkpPlPqrT7O1UCWHI2
fIiDQstyZrbrN+wrzkXI2lc2+X2gf0ExywHUWiF1WIp+WvmC2l11/8HzzHGzqM2Zj6qsmiqllSKb
mVa3ozClNgySPAwiHf3bQdTW6CmrF6+jIY5r2ntsI151yupWt1DV1rg8pFDfuuErqFmYGZgmuAFK
puGbg5uy3C1XwKFTGipnS2+VW8RGQloOSC0OxYHW7c/ALMyiILYRoHy7+1jEYby2DrChXZlwGpaM
jITwOEUTzKXt/QqpSKvIzzlBLYlKIwE8+NLReFf86Ikjd/XiNmS1Cy+zV900DHmEJYyPoCFWC+ge
AGsntk0LGPLu8e6pdAyY0GCi6BOVj01M9TjQ0+Ed4Xnr5cz1Khy9o9s6cMQ/xb97H2cTzfCoIqtE
zw4hCace0LGpuX/VVncr4GFXdb7kZJ2SI7pbMksIio7oFkHdMdz+xl5myH9ATz/hH5k9wBtgXHuI
YCqonPnqY9wOnZNI8kGoaaYoKoyeiu1/v/AGsinB69OdWFwW9dKiIiV94JHVNHdvwfZNN+ia1mBq
it+lEsyirT2jFbMazlYQ7d9NPGs4frKb6HUmCgI7ooaMVBa7PX7q7zpQlpEViJZvSdzGlbmO/xCK
n0rwZvuvShAiQGqG4kQ3GAs2c+UD7Mk6qmLRtFIN675muZxQv8ePYt+0nuB1GR7ypjy5dgEz6u2n
5yZyobdQYkGbw58cZDm7JVtxZnI/qnoO9DL/wQxC5Axo0MHP2BAQjcVKCr+ocpGF9eoCcZeunHtf
dnb+Nc4MAgzITOSthVQ1cwdt1+KmF3nU+7jI1EkKxQY8b2drMVwnHdfoj0WbL2PefDjuLth15pkQ
muDzLmtypkaIVzoc1CZnYphr8Bso9ABJzMXarEhKc2t3aVPaFIgD20yJ2Rc1UtM/nBNHN2dB27u6
OqBAyct7JuxwCLxglfl6/aOC9seH8s+Tlp4J/C2pDb4QU+Ms3tF93l1JSVIPuCRLol6x3S7NPIb0
01pL7zRfTQeFTokpFbwMwXCzy3WoVdR5OcLEt5SZR5HawDzt6saREVeH9ebd4GFh8fBeHHmtPFR8
odGodTwtcPtZGKyiwhIYsuFXDkow1u07Ep5GAMDIapJOm1+518uEIV1DIbBOHx6XonkUzsahVOfm
qx8JIhf6gnB9rJSN+3T2Sr5WBa29BYP5wsQhGwWT1BL3HieRkZXGwCc5GIXhHj2NirW2V85sSENz
Uv7BHuXFzqXazcZg8ZF5OuanloGRERYZqLVRy0fWwwZFmPMrvr8A6fSky7bUUCgzoIL7mtcmgsuq
zhhaiEyHTLtFqaGQLjj5kUS5qW1STLnMwrwB3Vv58YjnbmtD/di37+D3jmPVsc8bPZ9DpqGDfkxr
eMBLBuLFqb2fqbiWvCCrHaxuFwmZ9oUZ1u8QhOmlSi0oMRX59pID5EZw27ZLSyLFApgSyf7ckuhW
KauKqPTPlbJcr1SDLzqqBrBvZCGCEjQd/LevQT8C8qSFYq193iURMdjuybIMlxP02Tl9nkU4SnX1
6u3nN8bcDnZMvYf4GgyWKH6vEgcGFKYbI/yOa6qGb42xMBmMxhG12lXqQ2AtzyR5S0t/MzNR62iu
4oYjbfTV2kVCIGfd/F3VzElJ7pvzb77WfXlZkkIg1RHKijQvMFV31/IzGIRYpxFVR+nplGuKm6FV
aWVhT6tO2NpD9XQvt5xanQtsEEdUyQ46WUW+jSKCw6m8orM/0rU0UnmTU/Nj6vT2aBWd5+rnUX+2
Jyc/zb+HaFNxtWn0QSPtnQD+hLqGj0FKYvPw44ofosxHj7vDZcalcci+epdH2bJ4UI021RoL1UBn
sqosxL+rnPFKXfKsBvPmJrs+4b7SI4ZWgyMckrdKnGtvH/c13hNr3sfYqyaz3wlP+BkaatgR9ujX
L7tFP60JGfpZHcT/0jouMpBhGpwWqK/VUdlSgMlYsahwtK8StDQw01w1G/+r+f8hqiSJ++Yye01y
pGRUGbhnq42vutlgxAj16oJBctWVCz3p76YumstA5bM5bP+t3P/Rvf9rzf4znBniMzGj6d8t+d3/
i+RD/xi7krir0HZzmZtcioJWk5AEB19SQdPzKyZUMO5Gpm/hh/gT/8FmlCwXu4yXMZ1GTCy8Z+6o
sCK+TcPVnLm37ns4cZexkcumSBp+Na3PKsY7Rfofo817jec8VBSWXTbVbc4S422s87w6wMi51rTW
T/Qa17XsL5e8odQv8wmSabJl2znMTdqHeIZB7fW0w57gtxOOO1/j4lQqp8+M4GrWKc1VCdUJ/bF2
iqLjE5tnth01ahcmnjIHcUd58YsBUtd8cYm0xk98gm6P9aEjqJlUd0/DjaKp2uzZXQ3dI4nrbro0
BG+yAB64Zb96bQJQ2IjG/NHuOGujuOzvZ28u8xJsPBw8yb9WLtCqKJcX9T0eg7+lVc3fmXYPWCnC
1KNOfnsTv+jawLeWgoJR5hE1ZdTpEHUwcloJtqo1AzNMuHAw+PHPVsed9Eaja+VXUK18BVWb72KN
vonZLw8Ts9TMUlZau/Wqvpn+2c2QVFs4yP7i4G5Z5YWmqlQN+YsutjGchP5UOIyq53xSOyYpS8Yl
bCgkixRQz3gxLFkylxOzqtXtZV+ZpzfLfbwvNOLlvTzO7f5U7oCxWrpJl8wjn6SsOyqtLezwpnKn
6Ls/+xCUQ6RHx++9iJl105J8nrFgCqFAWWFaVhssmAxhLmzetYzFUlWtP9FtYHMO86OXzIGphIWa
h+jku4VrjAvUvA+dxHipIM2qLKhgXQwI1g99tWE9nbwBkr4XrjsSykDqX+LVerr37VQuqStZiHt4
hE3r6A6lFD+pwRkDS4OqOZSmXXnJFh4NxbirJt9CJDyMefINmORy0I35b5Om22xg3T4pqm/TBmJH
Omi2YntvA2F3y0MFeWbbV3fzyBlxWO9GC12Mln/toNSXbr49xXN4ocDsTu4Ki59gC9mrTr+/cdua
FYEMSj92Qg72LNELmXgnnHPjYLgnedQIkHd3HHdlTkuctCDwh/ffvvaOG1EbnrBNfH398NtwKdY9
UKJAqbmH+J67FN3LqZwbdbHl7BJMVpC/yfUmjO2P4dkfQNhDR/C/CP8L2JRMNmSow6XRCa335sv5
Vms6iSzQtai2b/2JRjdic9mZd5T+J4MHVwk5H/S144c8K95So6QRr1mDUaHe2awqO/fbepIUi5qs
FeU6quoCO3Y7lCx9yWnamTJGGL5k5uu3XnBgYKcDGkwl0GH9F1SFQL6U0QljTfnheaQ/sTU51jLv
WtX5anppAOXH9MGjFTcipp1ZeL9qqxB9Cp7fk7iY4aO8/nUfEOekNs+lcOozkuwOg2+5zUA2HXey
xQ4mVKf4spvUX5mTDy55NB49GkRwzBAf2LOmWMO9jtn7WTLT6aPIkNnje6wydS1i+rB8K0fZMr0O
s3ELc3pyavoVwsr3kz2EiYNbx/r7trvk4hmRT9iqzTjht3wfLh6JUlLMS3ImeOgrq+T7G9PGGoDs
c8UVFmVdWXf6NIrDadpVtvibGZ4brzEKmoQAKSTcg9FcVmRjZBlx2Fldx7xserdXX+52357ZdJQX
S39U5aQfVSJERCF2K8lhZGR3cWJW4XsyZUjEEYRcDX6YVRJ4BkbCe00rKeJ9Mg5StMyLqonnaKwz
Ud2xQCx61PCTfDHj+NzImJmKsouSeYKmjK09f/vH+hHXoo8xd6qPgqT1sxHbR0hyGi/j8aft3fFn
RYlXrTqp5Mzzzi1iqooM2xn+17VWncRafsOJV0HO1T9d78nPb1S78gfXoYO9F7iEuRh+bcPv6DdR
N1RsOgUZvXt7+fFCS+JNr8ftCtM4dKtjDRchT+pmzuo478nEXIWWT6wIXdTw676TuWsTOV25H48G
6EqIpICl17CQ6YCrgTN71PBM1VUtMatUFlSvFfVMOB/yfVnSsNGG34CoKyDK98CUx2sgrd3dKSBT
4Urhx6Oj+ZDuC6rXdQoG15xiOMMX3O2bBfEOkakCw5qrCxseK86NXAKV7KZLnhRN6DRaDT3v2C13
EaGXZhZ2E9hxT1MULu3I4nOcbZ8olgHivK4BA0XbpIFipujSAmkmNf14rSR0uGbGODRinOg8Gxnm
AlKuf39bxD184Qwx557ZNlgagj4jEF9uX9fjyq9hVzbmJDKVU1Epl5NAfsWl3cLeKmP9uJsonMfv
Uzom3eN1fPacu9170kZ//0l+63d2UzWDgULV35Ulfro06UaS1+kezvmL8j/ZJtXiyx8sY/+55PlV
k5g/7c6ml5AbyDGyMMMDN2wWxbpkflwCFowwNPMxYSgajzFx27HAmv6nm20v5N4MCjvupimkcN6U
HdlbRQGNNKAznnv3KA9fIUaWqfyNS2jpKNccvroQhFxpemjEVJ7WMDj0NAF0oxMv36lU9z7GbDts
W1Hs7ZvIYaOGIofNVqVXqRgnOr/59ztbQ16Bubvzu9QXeJQXhdmimxMUUu9WR3I8mZv8IEyWf5X8
7n2rtOYm+IPoGeLSpEipsbZWuGE4bSTGlaQgshoVTzu8wDxy4x2Xc3+TOY70iBMh4Gg6RCzK+o+D
BNkvvRpfXIwm7azC2BKzXKxzBTWEoP/+OGF2wdot5wCedFFUvhtzhdpqrEadyYr6BoMmtDJOVbLL
KnMM62YK2JTEgdknf7qaf2Vf/m8nGP89LKvP27SoHL/8SLgNGmwLyg9JoT0838Dxz0aphKONoyjP
+KnA354DFHK0flxv9Yqai8u1PL/Cs/cu9OAdEdauxDtCrHqv1KouYfKHJFpdCnxIaE+5lhdXoJpQ
GI8dq14uDBrMdl/zL4uqWmES7G6hsqWP9P04poLd0L9e8suDkP8CUEsDBBQAAAAIANIrfF3uG4dd
eQkAAMQaAABSAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNw
cm9pbnRlbnRnYXRlLmtvcGx1Z2luL2ludGVudF9nYXRlLmx1YZ0Z/W/aSPb3/hUjnVaBxrjQdq+7
LYNEU5pyl0Iuob09rVZosIfgrbG9noHgjbJ/+715M2N7jElPhxQyX+9z3ufQ65HLTSrk5Y7lIZkm
kifykklOrtiK9P0B6fVIul7HUcJfiA0L03uS5alMZZFxjyQpCfk+CjiZvpj7z+DsNMl28i2R0ZYL
ybYZiRKyjYI8FTxIk1B45CpKdgfyeUEWgKL3nvA9kCSdDJjosfD3nZBbtRCkaR5GCbAiuoh5vpOI
Oki3WcwlD2GUSBZIsudwMpCCpElc+GSWkjsgvss5CSORMRlskNPJ1+n84vJm/N5/FqcBiwnKScnD
4zsc+stllIT8AEtqag6td0kgozRRuGTn4BVdknNADmIxufHFHzmsPj+cF89hhydhE2wdJZHknX0J
pjQHU0rPkt12xfMzwpKQ7Cnd4wCxspWAI0Mcb3Z3vA1xlIgo5J3MW3WfEfgY9BliWeF35h9GdOUf
+nY2VLOBmRVqr7B7hdorBs8UpZIGqiXh9517b+OtmZCaFBOCg9hGtPsuojCzjZ7djzTizaivYTT3
Ar44Rbm2UaLQdl8M+m9e1iUQHCxAMslWMe883FM4RDeehsRvT8SpFPThEQe0761ztuXwPwYOl7CT
RLGHGNVnBZS/8ZCuWSy4F2xYHPPkjuMhJRLFLyrzHX/0lMDdYx28zTlw1dGSCB6vfcvCu2pK+2ZS
Y8OsOFQRPboKOFuo7Fht5kTssiyOuCD7SEQgu0eUOWbqTCLjQmHigbL7JE16KRh9zLIsSu6IZPkd
lwK95MJSIpEgjAjYj3lvJzjJeL6NhACRlDdI2AxiFm3Bu8kGfP+egb+wndwAsShgSnS/oQSWbzul
JArJfZs5qGW8ejT08rwyeLzSs7q1lNs+P2QRaLnroDzaHgF2hD/a6cHOkP7Yx49Gsk5zsvTAFyAG
RRmLctF5qOAgPOWysgdfcSQ2j10SpqXtGDZQklW7BMq9uo2FQWOhaJ4oBkbOGhGFaES11yiQanwY
DCma0b3dtAsbe6I/LB1bwQ6RBFJQxlb5H/NW9HsqqF8AU8QxgoAukRNmJkxxgfEDdwq1U/RrHlLZ
/APSoczT+OnKA0sCj4Qb88zt0aP7fHzWEvOyNEpkR6H3hBdoYtEazdman/APjrKFX3S7RJm1jS9W
IwAIh4coAAxGRsU4K+xyMTKKRgyBHyV7Fkchhot3TYya24w+HCgg9Ar4Lh7rTAag4lxIiwwnNHsH
QxUz9AhlFHRwAntIMRFBMO9pKCAE0dtOilIpIURgRae0sxK1HZwPkB4EY6r/nYdqYcsOQvLMRGl2
6JRLXtiteC2t6zhamoTcCTwpMEbXU0C4yzG6UCmAaTSN2m7CJbVaQj9HajhEua3MPXMIpLeSl0uQ
iOHu+vW0I3MW3W2kkdPkJqD1Qi80z4eHU0wc0z+CLb4DW2O0goXQPTlAiI5U8aNMXgHFLOFvCTgG
nIvuoBiKIZRJfpdHsoAIyINvAkSLYB8yAZQ+NS4wqaHprkv9GcWP6GCggqSzOBxg6KyCEvKr7WRE
f3JLk/DQHdGXr/vPde5TOdkBdA++el7NC+2b9j4gxvk/N4kaYxvSNy+bBLRsOWciTaydlz5pnVxt
0rPp7Ov4avpheTv515fJ7GJypu0VagCEMfnThZl/ndxcja+vp7PL5cV8thhfLBww7cKC82SJ116b
Fy6m8S/T2+VsvlhOfrm+ml5MF8vFJ1hpQ9ppXIE2TcCM9ZYiU17c4CVmN5fUhy8348V0PmsIqK9u
+No9/HHy7+WH6e1iOrtYLK/n09ni1pWQyyFQqendhb/9NL9ZKAzXV+OLyefJzJXF3uuw77/5qXEf
NzeTyy9X45vl9XjxqcGsufLRz38/SRkgLyfLjzfjz5PlP758vq4w2COloZ99HN8uQNefgdL0/dVk
ebu4mf9zcqZ0CXaxAK7bdt04q9oM0Dqke2rw0ydgAXN56gT1ehaGMkvXo3WCG+rmzdLAN24cV70Q
NDqqgCtbIVB8+o0TjKYwZWsJBSVAEci0hOnQvGWFapnEbgvFofTr+MZJUUPGpOTbTNrDAk6/I5iW
gWgsUigcOcuFg6SlzC29WklbqdN4ObI6grzvYzGgK0YxVAumAigR2NBgOh4TPaFu0Ui67qaKsWpP
FxvoQJWq7R2b1PqgOwcdJ9VQdxTqC1IXZCjP3Kr+59WMohpWrUYp/1LJDDH7T6hy1NArk54deCrR
wZ/XyMlemarswLP5uErDJcHTeaolUeqsWAM+mag6p1JqBQx3FEdBJJeKAx0RvXKtsGsF6E+yKOHh
Evr7CDUQ+NCNhEu7UaE89Bv82ARftG8U3mFAW1KzV7QtF48thcqa87ADSocCH+425B4kkh1vrSul
cMpKgHDmCtpZ0Ji6rusqQ7O9pGkNbXvqFJQPj461qshaayytrzhrGCy/g79E6LSpUlgiIBQ1XYeS
h9JX/xPaGtuKggoot/+ZLT/czK+vJx/eqrcXAC6SgGx4zh2JDBqnPq+w5PyPHUSC0tggPd0DHDax
LwzKVUHU+5WDtfRDo6mRu2oDTCWcG7nqekeVvHJvUcVkVM/rN+6G2cSr1w0EDkevBuX4h8FftP//
aNUhUr05INKm3dRtR31MEUyrl4tfy+FvdbGUwVu1uI8bdQgqHOylOn58Qh0j2j/erHizbZXwg7+c
5FFK7Ae2jwR/hZOI1dORx7zt6JBjJiau9j3sb/plFK3FsPrH1IMG2LJj/ntOxNJnHttY3DAwIX19
zrYpdJBnSnuDdlVgQxoY9fuBj69DxhZc5EcGwW2CewpfvXc9xlCb27pM3+orZbxm/Lr1hsuDhtRB
346uzqAHttMGyRp/bbw3sdo8Y/jXuG2iaRfqe9dSl9mMjexHobB/HMn9ZvVwPmi4XJDuEkmrBke/
SAn1IKXfoyr/Uu9Ozo1pWPw+H2BEPHbpdCdpzecVeqxdTlJwxDc8Kqc7utEnbgUYGg3sE4b1m5Pq
1yLpG2hHak51nuquTNvoHzA6mEmhJ4YT10dP8qM+kFpuzMH67wxEPYHirxtBGvd0T7naSWSE76G6
TAKunksj/JXEP4X6VkUpsoWKcZer59kUi3WsyFep3BB2AFIbtudkBbKRdCV4vueqggVRImF/1mjH
j+2S0ZEppGvtZ+N97KQCEIt+fEY4sKNf/wZf54Pf0JxbXnAwBDnZsfmpHK2qt+ufJyNObWxyGbDT
WrLrOs7M8Iea/wJQSwMEFAAAAAgA0it8XXTutNXzAQAAcQIAAGMAAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9n
aG9zdGd1YXJkLXByb2QtMjAyNi0wOC5wZW1lkrmWokAARXO+onNPHzYBCSYosBCU1WIpyViEghIR
EBG/fronnRu9c196v79/0ODBcr/8SLMt/esEL7/um3EsS+tb4Go1HQhtDurCaSCABgCeDi478Ps3
9elnQ8CnzftzPe4WtaziBE1vEfgMDfsHuc+CNZlqfMn0bjoMVx1sq6rjl2wt5anT5UKkTZwkZjjn
4ipYZYjEhryugEge44qbgILytanYY69cuPf92cES1U3Pwq3ryPsl7VvcfObbPSLAh/04LeIsCl7/
sAt2SZhpEHKlM1ses3dplXbhoFV1O8kVjaODscHpsiFT+iClH6FWx/nnjQN5GtHl9DKm3LMZDvSL
kcoceqLrBZABRzyZqUwJcRAecnxQCmtY/VJ4+8PDDpvaFkexKmWZR+aLcxFTp3yN0Ts5hriRzk63
9KruzK3LPZSRDhyETcLStIKCKF+HDppHO4BqBefMA4KEScFEN6sJd8mW2pRNslMu3fyxy65rGVA1
pV5Z0rEugs7ya/WEnrMS72/6kJXL3qjPmx23MFlVGGJyiMT8GHvyJ8HzuR7TU5die0WxqN8Bu+U1
IHmmVClYdaSkeBD7pbKpgq1U5Bk5GKynyoW7DjkkG3eVlPFGe0efvUvludwEr/O6YNPuK8UEtaMB
AP8w/xKC7v6/qv4CUEsDBBQAAAAIANIrfF0NQWlU8wEAAHECAABhAAAAQ09QWV9UT19LSU5ETEVf
Uk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tleXMv
Z2hvc3RndWFyZC1yYy0yMDI2LTA4LnBlbWWSuZaiQABFc76ic08foJQtmKCAAgtkKRYBM2SnpJFF
bP366Z50bvTOfen9/PxBRSZ2P/xYPWHtw0bZr/tkHIzVsYeu2tCppZ2pPDkVEmRA6Gkwk+Hv3zX2
z0Zw1F3umD274QBzsSzyr+5gMFEiLp5394NVM/TTiRtbGpXF1SNT21HCSXyFz/1y8ybIBQDUw3zU
Ovu82Lju35qhHpmgjzlZ85HOTePDO0+Zlp+b92Uh5ksZb0v1wi1XaTsHuLGxqqlfjEFf73x/uMo6
FunKBCOeAtVEOwp6x/oa8tSw81lus6iP6uxu+0oFwtZsDKUU4bbtiI5Dpzo83+bBus0sYM5rsnWm
G+O0Z7MJC4dxb/s3oUFRykqBlSrPuEwMNiV5tuwKluWBUOziF1sAYaag4ZhQvvEAzXY0D48Lhy+n
MOmkZmnKejWO4t7UJLO0I2+R2Tx9RuQscdKtt4M0SWTQf2GWKWj53gLpsG+vgo9K4sAcKS2dnqfQ
ajiqWJGwoc1JY/39emi2y27d+zpbPopzka8NnpF8eXQq/UXcInf6TXitAQst8QpITVHtVZkshvcw
GVfeqSn3oEfPv/eXO4AxP41bFzOjPE1CaLdYIUQth3i4jAn53hveoMcddVvQ+6cjq7DUyvawcVQI
0R/mX0LI1f+r6i9QSwMEFAAAAAgA0it8Xe2rAT7TAAAAXQEAAFMAAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9r
ZXlyaW5nLmx1YXWPT0vEQAzF7/0Uj56dZVlEBPEkyx4WRdY/F/HQTtPZYDszZKaFIn53U93iQTan
kJf3e4kx2B1DyruhkgbjJeJQd2wxknDLtsocPD5oEvZuVRiDR+GxyoTEzuts1hLuX56e8bB93R5Q
q5SDUAM15iNhz77pCEEWtFAMiXVnOgFDM9glB5wQhVoSRdzgcLcMhXLF/gfbTWgV17OT3/ts6KN2
NXecFaqrg3h8FtB6K938n5v/M1GzzGa9uTLr6/IdtzgnriL15cV/gNiz9j/pZP4qvgFQSwMEFAAA
AAgA0it8Xc6fJ6guAQAAKQQAAFUAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
bnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9jb25maWcubHVhtZPdasMw
DIXv8xSh113c/TIGg72JcW2ReHWkIssdZezdp25d14w0UEZ9JfA5R5+FxSCFsX6vaj3BibMhcv1c
z0yPYko2TfBrJtt2lKUtjsNs/qVN0QNmsAy+A7+yGTxhyGq9XQwVPpHeM6W0dFoIJWCHHgaWvYcw
RQT7YwV0ywRBFcIFRiUMbczCW1s47bg7kXV+MobdW9NG6cqyZGBtJIDSeOpNIN/R7mYTze+zrlYR
QwLTu4hmH54PRfOaCWejADm26HSIcGEC7TMOcJhAH5mJ/2L4gEofIMUNNwiiHacBXv4xggsjnJyB
d/oL7Y5w8u+aoW3qTd+J2vC8wJOEeYveZnEC5wQe2cZjW3aDTXpY3D2eWCaVIHixEnugIiq+H9UJ
iUtHquubefVRfQJQSwMEFAAAAAgA0it8XfE6fFK/BgAAGBMAAFUAAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5z
ZV9jcnlwdG8ubHVhrVfrT+NGEP+ev2JldJITTCDP63HiQwIBfCSBEqB3jSLLj3VwcWyfHzlyVfu3
d2Z3/UxCT9ci4exj5jevndlZ1zd1l9i2Q85ISL8mTkhlCaZSvRbAjiuLRYXg6rHr65brGLBbg2nT
tKg9n9fiTUBhRKI4TMyYGI6vRTEZqrcfq1t0HWjBC93g/ujpTru7GX3ZSbSyUpLJxT4CM37NibTz
h8/7xRVIUeRuYm/peJSRTa/U6ehjDSwgDfhoHv2mrehKMxJbNn0PSNa+Y5EGzBXieDFxqVf/WMMR
ktshpTJj1mE1FUoad6OJFlLd0tBDd49DWORkRqCQnKzxqgh800hHCQCxUWYCE5IzoZlCGHcGaeRj
NEBG9iKK2MpwUjbwFZBxM/k6h4qe9Xavn8Kgrbh64SxpFD/R0LE3qufEVSil5HQwLmCLZXiMhCLc
Thq06AxhV1ncY2Dp8ZbWKSr3mKWQyPlOtZiYXrxH4UvH0919MIkXOUuPWsR81kPSgEmGCOM84jlo
6WyAhnqugp94sVKFXFmFJYRqIPnbznFWgQuCF4tazWW5O4HM/fMvMTHDTRD7GqRoum0nnhk7vkcw
dTW+L9drBP4cu0BP4mfqQQmIk9ArLlPPYsQczX9RCIILdqwBoiQwfraOf0dH5DwJQwo23dzew5Gn
IUkiGglkMhiqpPe+SW4oDUivf9zrERuqjaGbLxGx/ZD4LrAU4aIkCPwwBkdlgEbiWS6NFKJ7FrEx
lO6GxOEG5uDWNQ0jsBsYQDsutpkBCjvAdbzKFQxRMiL8kzinBPWv917av9d/Y6+3d89zXB6K1Mvg
U8+PQT0ejn1qKhlGfQcruA9H1aCCMOAbq8Pz+y93D7fa43TwNFDHg+F4JGUohcifZZHeOhU1JBcH
bNjv8hNo+YWDorvBs27QGLakwfD8YnR5da1+uhlPprd3v97PHh6ffvv85XfdwBtk+ez88eKuPD/4
GkZxsv72uvl+0mp3ur3++18+HB5LDBdPBd5SLYUcZOiWj/Ln6fw0SgzZUZz6AggdckRazDCmbZYI
k6ahR7TfvaCmb1HZ8YIkFgmBQ+CMfbgSHG/J99CfklQ/XSK49C7CmEpZBgkeMFNCQvmAL7wj3Tr5
+4yc7AjBTL2aDh4e70facDAb9buaOn0ajNULqZpsTBnwbNV8JkIhXSJcXnC7YiimYqH1SJP5QynO
D1sK/FfW2rDWrqx1YK1Tr4hY68oaDwfz+0Jhv8YiIwKXrHX0B9iKDkFaPvkZRxTEmiDTZI4+k1jG
nyA8SjcXVVp0gLWT1iprahY1tf4fTT0QDi5okHa/3ep2ySH6oEG6Jx/6ODZh3GerOSNEen4An8MW
Hlx++Jp4R8grPX5u2q7vh7JHjkm/1+v063C64CauFy0x8bChtbxu/Cgewgi0kiWAaP0goreHvxSr
MthPuBYA5QwRgpVGt87gHYQXmXdEOj8lJf0VbLFuuLQJN7Gpx7KPFaJQ87Jawro523GpHIBj64Xk
tTEH/aYfUI/tgQ6hkZcNLNB2Vc9K/kcAYZ+iCFlq6ILXPjVdP6LiChe80VaJW7P+Rg4Sw3VMDVtg
rsSKRpG+pNiYLD0dmKlm9LtFxfEKJDQMsf7vahl2XS1wd0eUc5VNCOiKPSwyL5X1KYEiLUSWsbBy
ukOCBF3zWD3XsJ2cqLOZOr2qVk3Rpy25CZViv8NqIR12dgkUQMy9uQzo3/n12Ky+DkB7KNDwzcAZ
7XZd2WEQYl3CjTzaugmwCRYCd70hYKjwc55+RECFgqzFB6JMJ473Q0rdDe5no5JaBb2gWxZqVd4a
eYOJFLmgvFQKnvwpwxr9bL+i0NPoXr1kL4hUlSxnS91pQZuthwlr7ZmDUhLxoqmLZaYBattimNB0
jh0jpLPZmNDXwMf2tQrMHyJEj4hOgpAGoW9CgsEp1l0HFmM/Raq+XRR26JDPY+Css402K8N3m2Sc
6J/UB3J5qaLTQgp3PyWrJIpTNGwGcQszy63yEwve62bsbpppEPJ2css/4iXFfJPVhgMx4s4odphv
IBVfVAyOJeIBfAswtWLsiw9QfHTW/u1giEOBXTEogIVfup8NtNn1AMKoiXqO3Vpe7aFITAYP59fS
VoXkwb+mr3Jq7X8sguwMFUugwC02lOkSbym3ej3s7zF9pNJDcd5pL6rE8PzcSQ+vyHmrQr0dK3kr
1AqCKgJ5T4YUcqP02Ih9L1kZNJQ59/xkwVrfTnvXPcxjtafM6WEcbbe8JwrptLDVZ/vzA/ZTakSA
EhobaM5P2q/QnhcVmjuLev3Ny53Bietd7E9q/wBQSwMEFAAAAAgA0it8XQr+x8rXAQAAAwQAAFMA
AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdh
dGUua29wbHVnaW4vbGljZW5zZV9nYXRlLmx1YZVSwY7TMBC99yssn5yV6wLiQqQcQhWJinZXSsQe
QFC5ziS16vVEjgOqEP+O27jd7a6WXXJyPO+9ec8z0ympvLS1NGiBGK3A9kBkLTsPLiXodKutNKSs
cvLzPQlI0uvWQk0ctLr3bk86DLS9mBhUAegQfVbDZmhFC17bBtlbTiuaiB4HpyDthw17l6R30qst
o0xczRKaRPIq+/0nHu+klS24+NcMVnmNlgRNlkxI+HRzwhC/BRv8+MHZ8x3Y+giL/EyjwA4so7PO
oZoNva4pp25Dz2oWPWlGLXAOHaNVUS7y5frLdX6bL5b5x2VBk0fCPTgtTcaa1IGsGb2SAYKOUJqk
Q9eBY0naHiLTbz/y6dc30w/fQ9vYtEmVwR7uA0W1jNL/9aHQNrrNamy0AXYYghA0jnM9FoUZZGwc
vXt04a2eIcXqyEot/GKjzKgQn/kZbqw+4fIoyg94PqYd9S6nNzmEO898JdQW1I41GPbnYQDccck3
WRfOhp3gLDmJHXclfcDNMu8GOD7dxdRxd7FCjTQ9cLpczIvrqljPPxXzz+uiLG/KlFAhPIa117Zl
8n4IkSnHDnzzOEC/t4o9tc4Vr1+wf2DeWKNtWJPXGf+Xv7Hl0V28Wk3+AlBLAwQUAAAACADSK3xd
vvx/LSoOAABuLwAAVgAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFs
L2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9saWNlbnNlX21hbmFnZXIubHVh1RrbbtvI9T1fMWDX
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
rEOhpdVk9DLQff5zEfJekIMvVemYvvUHMk0KV3638J2snOFpjR2GGQ2vmlZa3s/giz/I0fxAqspD
83PMWo7FHCo+WGeOtWqg+kpxkXjNBXfNdbC1lSK7KLE5Y5Zw8I8WViFvTgR93TOPp1wjQat2m3QZ
LvPjhm6J5oJxp/+ux7PpY6izay6u1EFU9tWggEvV30XI44Wy59+yV7b7kn7v7ZLnvjvJfyzogeIu
9zCOCHpC3Gal9hTdjWMGoA4zV1X0KbGSGbBYWP3R9n8BUEsDBBQAAAAIAEEsfF1w633M2QYAAG4P
AABTAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRl
bnRnYXRlLmtvcGx1Z2luL3NtYXJ0X3VwZGF0ZS5sdWGFVt1q3EYUvs9TzEWDpEbWxoFCWVcUx3YT
4zgb1uuW0qaLVhqthpVmlJlRbBNcUnJVetPQQim9aIxpL0oDgRRKY0IvNuQ9tk/SM6ORVtqojcG2
NDpzfr7v/K2toUOB+ZrkZDrFHEeoyKNA4g1EGZoE4WzKWUEjlLM0JXSKWIxuEHmzmLhKIGY8hCsc
TxiT3qWUhUGKDnd9ju8VhGPbKkivIFlAA9BtOUZgl8asJXJEoimWPQLnGRYChGvZLUZjwrMu8bD8
NGHHtXQai6VkSiaiB39mjOMgghjhay257z+YFOLEj4NU4FNzOBwMRr7Vy6jsFaLnRWHO2ZhQiakU
CcFpZBnB0WBwy1fSnmf1JGOp6O1qsQMtNj68s7052vHUl+rKcOfg8NaovlSivCYk/O1xLIpUVpJx
QUNJGEXKbTt3kDn2CfNYjqmduxafWM4GIjGQIFGMZIKVuCw4RZSkCNNow1wTftzXiqx3A3Un7ocp
E9iGR3NBKPFV26CXhNiWDtDZFwk7shVrfYqPHkh8LH3pSpJhVkj//VOnS8GM284lBD/lOdfPkC9o
7OaIUETygHBhP6jhrmiy3PoIDGEqQFvjK1iLmFamfgABYNULJOTvpJBY2LlCN0+LKYFbmsGSwCkA
7c1Y+aWC/z7mSr0njyWYzVgEief7VkxSbJWgggHeDS/3cx23cqP6b2T4pQ5AeEFtZcEV+J4LX1JV
XSVEYGTfU+lYWjLYW6++DaDijhcXT1E6f4nCxYunOaIJ/JOeteSvMl7ay32FfMV+GoD5BCtfAxqZ
jFIIVXh6IrFqJ1QyVTcQUNV878eEQhJtb90ZDsYH+5vDkcny8c3BYG/88brlrruSF9ipb7aJUTXj
tAPcSl4/C1A4f44OsoBLdKhZQQljMyRfP3t9BuHLZP40TDy0Pf8L3gYUb6UknP13/GzmFpKkfq4g
tk0zcK04hk4E5+1gwQ44K09ybKuPHnC0Sw+KyR3OQmhEzpeQC4Y/qy1JxFJsm1HcFm1FuTcYaqjR
LJn/ATEki4sfkOSLi/MWpYguLr6i/xcYdSmWq4FBP4TTI8ZnvWWfbYSoUq6fBTJMbGusNb1jOToZ
7BIBWvEFavpEQMOlOJQ4sp0Vtm7Oz0/QbPHib+3qY4I+IWsfEYjk9bPFxU9hl+fgA2S7tqYsSCYg
HejUhkOncuqLy9EV5VKzyKr7a2voOpMJClmWKSXqNw/gIOAYDim0T+gUgAc7SokApzeUvQLTECMi
UESmRArEaHriaX1MeBxn7D62y3bc7FDGBvT/CTQIkSDL81TOQrWoR4WjeYQCsquwbH2i4lEwWlZT
I3jHwSc3J5FhrSvJ3CptbEf5h49xCPViG3d0b20RarTW6QjaVfLRIpsA9+oYTj7wr64kYZl7M0i+
nwkKIePOTtCrx4q689DMfN5FYdmYfFXZG5U2hQW0SWgL4czSMJheNSOLi0cZpETQSu1/Hv6qHTNS
cvHinKD78yfoeH4WoozQBE3gjL5xqYlm3UjVKmJmS4M95QtgHUEtNsFerVNFhtMcHwpSc7kTMe3i
q8eLi2/AyxowSaAOKAQ6/x2OW50Z7ZUYqzs/goIUoCaobgJVuQAVUDuJbu5Kogv7hosqrtI/NY/B
4ahI8S61110FR/dVQ51ecTZQNXJsW08BUwCalp3hcDBEt1mVB8gsJE5fFBMw8d76Nac/Vc/WZ5/z
z+ldKFgXct1pDb9OxzonIdY5bDis9guz6S1XDOvG/LmCcX6+zJO3oauOH8FEeaIlXvwpP0SGx3JH
RXswxVLsWS6bjUsrw9KbWof+VIHlL4uzyYguvMNdz0RSXdW7Q3sIQHQrQlDmGAip82yUsPmZRDAP
viMog+C6Y5qf5ShaXPxCpzpTGpvHaQlyDe++p/PZZnEMKztudaQC5uCxb774uqrL+i1HQ1mlVrnL
wL5iShwanL7owvKzbFditQbVYgMblS/q1r758eburc3rt3aQDV3eQfZnl48ue5fX7l5x3rFaiKp+
Wqd3dzpswZ5QtglwCOxAN/bQ6M1e8mGDXLNRUHb0VlrrmHOOc5gvy6hVXPWFsjQcvRjqxzrY4c7m
9qdoOclMkrfYrm4DYcvGvuSxfoMrCpRa99bhcLhze1RrX66IUB0qZ/KEzH+jBh/Iop+I7ke/qE2x
5YFwmrnzRupkmBYGFNNRDPoHLJZHauwaSP95+D1a9655V9GBDCawL7vQH8ZE4mys3/0HdTRGw173
cEA91GSpg6I6o3Un0/6fuqvaRxyqptwXoXiaBrp11oSs9MLlTtru6lvQd74u3yqY80QVbjJ/oicD
EDGbv9Rw1/6dnmp8DZL7l/4FUEsDBBQAAAAIACIsfF2mNhRPCAAAAAYAAABVAAAAQ09QWV9UT19L
SU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2lu
L3VwZGF0ZS12ZXJzaW9uLnR4dDM0MjA04AIAUEsDBBQAAAAIAGUsfF1Fw+UO9wgAAP4SAAANAAAA
UkVBRE1FX1ZJLnR4dKVYwXIbuRG98yu6yofYXnJo086mYlWlSqK0MtdcUUXKcWVdKROcATlYYQaz
AEa0tnzMl+Qncs+n5EvyGsCQI1u1h+Ria2aARvfr168bfELn0+vlgma1l7VflUrq4j//+Ce9zCbZ
C1p5sdFyMHj+/G+L90uaXd1cXN1kFB6mi6ub5WKePX9O5/JOatPIgjb3dG7y0ihftncqGwz6dmmr
tJfWUVsrfl1ggzdtXrrcSllTbmovcu9I1fRusZSikJa+o59lvViRqekXofTGmlssfafqQkuX0cxT
YaSj2niyshHKRpNUClvshZVkLDXWeJl78qWkWnh1J5MBYj/sVuQSrn48N/taG1HQopZTrfLbvz8t
vW/cm/F4xwFtstxU4+IY33hXGud3LY4a3QaDYyu1FE66sRZeOo/V0eY4wPypD8en7hi8dV5onbny
Gf37X/RxmYz8H+c/GwyePKEPpfB/ADhyPxiMaFUJ6+l9U8C1N9Q6aUeqVl7hsRjScnU6evXiTxNy
alcjM5Wo1RYhOBJ1Qau3p6PJH7+nO2nVVuFzo9sd8tSI/FbspBsSQtgxA+TWAHWLnThN1btDKjO6
MrTB+p01LUw2Rmv+jgRtla1CsqzcGOMzOHsV83QJOy0+zJwBogosMF326Uw4ldPkxWSCl/r+hKzY
JyJfIqZENz7CykqoGpHkbDSjKZgmP4MQVtROBbOJI/hz2BGR9sLnZWF2AQG8BGJ30a3Eol3yzsrc
AJl7ElucSGbDKwFGlw0OaGEVABO672EOqIYHK74EaqXRBdAs5J3KJYlCNGyRHQBVJFwgVTVaVjAR
8WjrvBQ1oOdDUCs//BSKdxK4vbNxEe+vxZ3axUecYn3e+iHtwSSSn5ULqXLS8/8OaMgYwglt2Sn+
0jbMGUdvb26uV/DQ5C174cgiZeGELTAZVapuPVdWAFv5e/Kqkqb1GeTENKEIg22b0ApJ2EobMoX0
3wa4Tltv6IwtF8qxChUZLRrZUwYQtEXVdKCrWEQhwBO61GYDrJPwsHPKs0rYCm8REVwHVUtAAvpF
epC4g8DwUVkonlSVzM+2AZAFGGVNBWOEHOFEhOBw2GCwlL+2yoacuDd9mXJt0wBpMCFSdhixWr0N
JEjJYb5VDf7EycfoQOvvsxevviMtOMPSDpMQvs7w8mnMSj/mmJxDfWJZNnk2pA9q9IMi1CRVyjmG
uJANa2+dKxbQd9c/kUIOYwiAaXv0QUVdTadwBnoltxeOWOKi6nNWUUK/sMxC8rA5MCu2keX0ZUgB
LzLbLapeAtIi1uhn5n7P8uu+5UhPYbU64g2nr0Uj7b5UMPA6WO52v/xzl0z5GUtUKBOddWqiDiqC
0L6SDyT9JbuR38I3ujetJXgohh3/eozkE1Ez/ojUtgURMzpPS7XcifyeLlmeL1me6doahvYI5WCC
5V3DYWDy1lp4e2g+YAkzowG2plO89aHo1sPghW3riNEjvMoGrzJ0ANDwAU0QOfNNSw86mkcrKqOL
ThHuhFYH6YGABrHzAJjZcFGHaB/WWqgRDgh+thxzLXPpnLBA+HVGp6ioLpFds+gPG/RU1bluCz4c
vBkvp5NnHTthFt6bWo5YUo5IVarTOUCVgu0YWbR5rI7IN29bxwlED7VJ1g+111UalRCh0K14UDmI
QKe/VqKQWhmrg/UEElRLWXBSWTd+aIOaxwPdYIBmU3NZhEocsl8YdXAETD2Yjv5CK7P1oQ3GHo03
01IiPq7e+Cq0Lu6W3ZLa7BMTYsM9JnPP5wCACg0EubopO5dsJxJI59fNPpj6eXYN0nNXSl3dRTBj
qw9LRNNoNoAaSDlc29jkdSvWxKSOw1kkC5/Enb9tTnjLYWITKKkK6OcBRIuBICxjWocMW3AZ3IlF
n1TWcaXoYWgGq9WcpvMZ3CwFphOo+hA5+001Q5q34sfZTXT2d5I824bY+IET2mlkaAqNxmAY1E0c
YU2tYMhy+2jdgjiSm1s8iPze9ASV2VSjHIB71Wr8jcbognKYAIhrHYsznw/ZyRNzijb0Rs5Fci70
1lTlA05tymOXI4SiVaV8mLCDmxBaPExejTAVyW560wI6F5PedXwXpqg4Oh1Hk/78wQaQjmmYOlyv
5HjDA3iHD8pt2M1Ysog2OBBMYdLyVNTvSod6Fzy6RiOy6CHMEfO0BNo9mKjfX5+f3lxkz9ckHCaW
qFdcPf7I/mEAOkrdA2U8JIEzu5weOlVqUS4KbVSprFMrB0/hNObpl+g+L6ICdEPrrlUFbk9fDi++
0GlUoy94ORqNKP2Lp7fGqt947tTk9qrhAYoSa76g3yGnsFA/vhTABV5ghMHHSo7namMhuKg1WWH7
CmMoaBSfYOCv0oaaO56kFQ/6WJmHIuRFc8Py/81KLnM+DMgKbAgjWVB63rMKq9A+QxPYGI/yJlnA
edDMAQx0xq2nX9ES/TGwM2v24B6N6VQEM+dK7Ez9aHh7g2aq+pMVNCL0Et4WwOXANdgHN74MBu9T
map6lEjfJeOSswNZAd29aCJXNtrktzCaKu54KcgguKPgfDINp8JFlW2H96XQ2xPi+96eG36RYnC8
sluYEEnxoxn24uhaexxWuzkBdg5BxeYb57RItGW6dyDM1Rm3gLwFE3Gb5tYgofz3tD6frU7P5hef
4uX9EvWxDkd89WH1dnYxP/90tljc4DuuiTDovLGcIB4uTniwwmG0vrj6dtvlfHF2Ok+GH1sQ7A4P
XerBWMAi3I2DmJ1x+7mVsnkgrmliiLrc9WTxjTLEEj3Iba7RZAvuHIwxRvP1cSL7lF6Oj9exMRw8
Dh/r6FKmzW591OeSk5AuZ6AP2hQaqXX9+YCnRmraDZ5Z2bscHbseX9gFTmViAmksLu9d6oGgJsLo
/yqyV1p3F8wTWmlAM/4gbuXxUgvUtOa+GYWxN/Rgrg0Khukk3uKjaEVVxro7xahytDzAdHGFmS/O
U+hkzFzT7srfm+L3kn9o4bF/FAf30JWULUYNsn0fby7DdDtlG4cUxfmAbSrLFg6jJhQWAH2cz6YX
V6uL/+GXEJTyZswIjZONZ6ETxJ+7UH0Vrpn/BVBLAQIUAxQAAAAIACIsfF2XwpWQmwUAAIUMAABQ
AAAAAAAAAAAAAACkgQAAAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQv
dG9vbHMvR2hvc3RHdWFyZF9JbnRlbnRHYXRlX0lOU1RBTEwudG9vbFBLAQIUAxQAAAAIANIrfF1y
KRQxJQIAANYDAABPAAAAAAAAAAAAAACkgQkGAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19p
bnRlbnRzaGllbGQvdG9vbHMvR2hvc3RHdWFyZF9JbnRlbnRHYXRlX1JFTU9WRS50b29sUEsBAhQD
FAAAAAgA0it8XX+sF+OyAgAACQUAAFEAAAAAAAAAAAAAAKSBmwgAAENPUFlfVE9fS0lORExFX1JP
T1QvLmRjcHJvX2ludGVudHNoaWVsZC90b29scy9HaG9zdEd1YXJkX0ludGVudEdhdGVfUk9MTEJB
Q0sudG9vbFBLAQIUAxQAAAAIANIrfF0R2tnWdwAAAJQAAABKAAAAAAAAAAAAAACkgbwLAABDT1BZ
X1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX0JP
T1RfUFJPQkUudG9vbFBLAQIUAxQAAAAIANIrfF2lt59vbQEAAKMCAABQAAAAAAAAAAAAAACkgZsM
AABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hp
ZWxkX0RJU0FCTEVfQVVUT0JPT1QudG9vbFBLAQIUAxQAAAAIANIrfF1LGlqNOQUAAKgLAABPAAAA
AAAAAAAAAACkgXYOAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9v
bHMvSW50ZW50U2hpZWxkX0VOQUJMRV9BVVRPQk9PVC50b29sUEsBAhQDFAAAAAgA0it8Xc9vp1nq
AgAAXwUAAE4AAAAAAAAAAAAAAKSBHBQAAENPUFlfVE9fS0lORExFX1JPT1QvLmRjcHJvX2ludGVu
dHNoaWVsZC90b29scy9JbnRlbnRTaGllbGRfUkVQTEFDRV9MRUdBQ1kudG9vbFBLAQIUAxQAAAAI
ANIrfF1bCDOtGAIAAN4DAABOAAAAAAAAAAAAAACkgXIXAABDT1BZX1RPX0tJTkRMRV9ST09ULy5k
Y3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFU1RPUkVfTEVHQUNZLnRvb2xQ
SwECFAMUAAAACABkLHxdszM0O8cMAAB+IQAARgAAAAAAAAAAAAAApIH2GQAAQ09QWV9UT19LSU5E
TEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9VUERBVEUudG9v
bFBLAQIUAxQAAAAIACIsfF0Ix5B+8wEAAHECAABIAAAAAAAAAAAAAACkgSEnAABDT1BZX1RPX0tJ
TkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX1VQREFURV9S
Qy5wdWJQSwECFAMUAAAACADSK3xdpnBVC4QAAACwAAAAOQAAAAAAAAAAAAAApIF6KQAAQ09QWV9U
T19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvQk9PVF9TSEEyNTZTVU1TUEsBAhQD
FAAAAAgAZSx8XeDpRIBNBAAAfwcAADQAAAAAAAAAAAAAAKSBVSoAAENPUFlfVE9fS0lORExFX1JP
T1QvR2hvc3RHdWFyZEludGVudFRyaWFsL1NIQTI1NlNVTVNQSwECFAMUAAAACADSK3xd5obckxIK
AADGGAAAOAAAAAAAAAAAAAAApIH0LgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50
ZW50VHJpYWwvYm9vdC1sYXVuY2guc2hQSwECFAMUAAAACADSK3xdF3siHvgAAACvAQAARgAAAAAA
AAAAAAAApIFcOQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNw
cm8taW50ZW50c2hpZWxkLWJvb3QuY29uZlBLAQIUAxQAAAAIACIsfF3JH14nhQAAALIAAABMAAAA
AAAAAAAAAACkgbg6AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4vX21ldGEubHVhUEsBAhQDFAAAAAgA0it8XY0xNwk4BAAA
dA0AAFUAAAAAAAAAAAAAAKSBpzsAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVu
dFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9kZXZpY2VfcHJvZmlsZS5sdWFQSwECFAMU
AAAACADSK3xdScdcc3oEAACKCAAAVAAAAAAAAAAAAAAApIFSQAAAQ09QWV9UT19LSU5ETEVfUk9P
VC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2dlc3R1cmVf
Z3VpZGUubHVhUEsBAhQDFAAAAAgA0it8XdN/vCuyBAAA+wsAAFYAAAAAAAAAAAAAAKSBPkUAAENP
UFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5r
b3BsdWdpbi9nZXN0dXJlX3Byb2ZpbGUubHVhUEsBAhQDFAAAAAgAZCx8XbwRYj09GAAAW1AAAFQA
AAAAAAAAAAAAAKSBZEoAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFs
L2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9nbG9iYWxfc2hpZWxkLmx1YVBLAQIUAxQAAAAIANIr
fF3LYOH98woAAOkMAABOAAAAAAAAAAAAAACkgRNjAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0
R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ3VpZGUvMS5wbmdQSwEC
FAMUAAAACADSK3xdyCIqeYQKAAAADAAATgAAAAAAAAAAAAAApIFybgAAQ09QWV9UT19LSU5ETEVf
Uk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRl
LzIucG5nUEsBAhQDFAAAAAgA0it8XeWZj3TsEAAAyhIAAE4AAAAAAAAAAAAAAKSBYnkAAENPUFlf
VE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3Bs
dWdpbi9ndWlkZS8zLnBuZ1BLAQIUAxQAAAAIANIrfF174CiqtBIAAL4UAABOAAAAAAAAAAAAAACk
gbqKAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVu
dGdhdGUua29wbHVnaW4vZ3VpZGUvNC5wbmdQSwECFAMUAAAACADSK3xdr5HuTTwYAADMGgAATgAA
AAAAAAAAAAAApIHanQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwv
ZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzUucG5nUEsBAhQDFAAAAAgA0it8Xe4bh115
CQAAxBoAAFIAAAAAAAAAAAAAAKSBgrYAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZElu
dGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9pbnRlbnRfZ2F0ZS5sdWFQSwECFAMU
AAAACADSK3xddO601fMBAABxAgAAYwAAAAAAAAAAAAAApIFrwAAAQ09QWV9UT19LSU5ETEVfUk9P
VC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tleXMvZ2hv
c3RndWFyZC1wcm9kLTIwMjYtMDgucGVtUEsBAhQDFAAAAAgA0it8XQ1BaVTzAQAAcQIAAGEAAAAA
AAAAAAAAAKSB38IAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2Rj
cHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9rZXlzL2dob3N0Z3VhcmQtcmMtMjAyNi0wOC5wZW1QSwEC
FAMUAAAACADSK3xd7asBPtMAAABdAQAAUwAAAAAAAAAAAAAApIFRxQAAQ09QWV9UT19LSU5ETEVf
Uk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tleXMv
a2V5cmluZy5sdWFQSwECFAMUAAAACADSK3xdzp8nqC4BAAApBAAAVQAAAAAAAAAAAAAApIGVxgAA
Q09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRl
LmtvcGx1Z2luL2xpY2Vuc2VfY29uZmlnLmx1YVBLAQIUAxQAAAAIANIrfF3xOnxSvwYAABgTAABV
AAAAAAAAAAAAAACkgTbIAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlh
bC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9jcnlwdG8ubHVhUEsBAhQDFAAAAAgA
0it8XQr+x8rXAQAAAwQAAFMAAAAAAAAAAAAAAKSBaM8AAENPUFlfVE9fS0lORExFX1JPT1QvR2hv
c3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9saWNlbnNlX2dhdGUu
bHVhUEsBAhQDFAAAAAgA0it8Xb78fy0qDgAAbi8AAFYAAAAAAAAAAAAAAKSBsNEAAENPUFlfVE9f
S0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdp
bi9saWNlbnNlX21hbmFnZXIubHVhUEsBAhQDFAAAAAgA0it8XdwkLTvYCgAAxikAAFYAAAAAAAAA
AAAAAKSBTuAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
aW50ZW50Z2F0ZS5rb3BsdWdpbi9saWNlbnNlX3N0b3JhZ2UubHVhUEsBAhQDFAAAAAgAIix8XTT2
FNiHGQAA21MAAEsAAAAAAAAAAAAAAKSBmusAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFy
ZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9tYWluLmx1YVBLAQIUAxQAAAAI
ANIrfF05KFhCHw0AAPQtAABVAAAAAAAAAAAAAACkgYoFAQBDT1BZX1RPX0tJTkRMRV9ST09UL0do
b3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vb25saW5lX2xpY2Vu
c2UubHVhUEsBAhQDFAAAAAgAQSx8XXDrfczZBgAAbg8AAFMAAAAAAAAAAAAAAKSBHBMBAENPUFlf
VE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3Bs
dWdpbi9zbWFydF91cGRhdGUubHVhUEsBAhQDFAAAAAgAIix8XaY2FE8IAAAABgAAAFUAAAAAAAAA
AAAAAKSBZhoBAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
aW50ZW50Z2F0ZS5rb3BsdWdpbi91cGRhdGUtdmVyc2lvbi50eHRQSwECFAMUAAAACABlLHxdRcPl
DvcIAAD+EgAADQAAAAAAAAAAAAAApIHhGgEAUkVBRE1FX1ZJLnR4dFBLBQYAAAAAJgAmAE4SAAAD
JAEAAAA=
