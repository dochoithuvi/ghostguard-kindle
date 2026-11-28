#!/bin/sh
# DCPRO IntentShield 1.2.1 Stable - network OneClick.
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
line 2 '1.2.1 Stable + Kindle Library'
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
    [ "$ZVER" = 4.3.2 ] || fail "1.2.1 Stable requires ZenOS 4.3.2 for fresh installation"
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
      n && /^( +)kindle = false,/ {sub(/false/,"true"); print; next}
      n && /^( +)(continue|favorites|authors|series) = true,/ {sub(/true/,"false"); print; next}
      n && /"books", "authors", "series", "languages", "home", "continue", "favorites",/ {print "            \"books\", \"home\", \"ct_1\", \"ct_2\", \"kindle\","; next}
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
local changed=false
if not (zen and order[zen.id] and n.show_tabs[zen.id]==true) and enabled<7 then
if not zen then
  repeat max=max+1 until not ids['ct_'..max] and not order['ct_'..max] and n.show_tabs['ct_'..max]==nil
  zen={id='ct_'..max,type='plugin',label='ZenFM',plugin_title='ZenFM',icon='zenfm',plugin={key='zenfm',method='__menu_submenu'}}
  n.custom_tabs[#n.custom_tabs+1]=zen; n.next_custom_id=max
end
if not order[zen.id] then n.tab_order[#n.tab_order+1]=zen.id end
n.show_tabs[zen.id]=true; changed=true; enabled=enabled+1
end
if n.show_tabs.kindle~=true and enabled<7 then
  if not order.kindle then n.tab_order[#n.tab_order+1]='kindle' end
  n.show_tabs.kindle=true; changed=true
elseif n.show_tabs.kindle==true and not order.kindle and enabled<7 then n.tab_order[#n.tab_order+1]='kindle'; changed=true end
if not changed then print('SKIP: tabs already configured or seven visible tabs'); return end
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
install_kindle_library(){
    KVL="$P/kindle.koplugin"
    [ ! -L "$KVL" ] || fail 'Unexpected Kindle Library symlink'
    if [ -d "$KVL" ]; then
        [ -f "$KVL/main.lua" ] && [ -f "$KVL/_meta.lua" ] || fail 'Existing Kindle Library incomplete; not overwritten'
        echo 'SKIP: existing Kindle Library preserved'; return 0
    fi
    [ ! -e "$KVL" ] || fail 'Unexpected Kindle Library path'
    command -v curl >/dev/null 2>&1 || fail 'Kindle Library requires curl'
    mkdir "$T/kindle-library"
    run_busy "$T/kindle-library.zip" curl -fLSs --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 300 'https://github.com/kaikozlov/kindle.koplugin/releases/download/v0.0.11/kindle-koplugin-armv7.zip' -o "$T/kindle-library.zip" || fail 'Kindle Library download'
    printf '%s  %s\n' 'fbbda29e0d46a54ab9d3d8ddf9b606f02341ef789f45bd3463bcda05d853b330' "$T/kindle-library.zip" | sha256sum -c - || fail 'Kindle Library SHA256 mismatch'
    unzip -q "$T/kindle-library.zip" -d "$T/kindle-library" || fail 'Kindle Library extraction'
    K="$T/kindle-library/kindle.koplugin"
    for file in main.lua _meta.lua; do [ -f "$K/$file" ] || fail "Kindle Library missing $file"; done
    grep -Eq 'version[[:space:]]*=[[:space:]]*"v0\.0\.11"' "$K/_meta.lua" || fail 'Kindle Library version mismatch'
    lua_check "$K/main.lua" && lua_check "$K/_meta.lua" || fail 'Kindle Library Lua syntax'
    mv "$K" "$KVL" || fail 'Kindle Library install'
    echo 'PASS: Kindle Virtual Library v0.0.11 official archive verified and installed'
}
line 7 'Installing Kindle Virtual Library'
install_kindle_library
line 7 'Pinning ZenFM / Kindle Library'
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
    grep -Fq '# DCPRO IntentShield 1.2.1 Stable - network OneClick.' "$path" || return 1
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
    echo "SKIP: automatic KOReader launch disabled in 1.2.1 Stable."
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
kWYJx+rh5ZCD5o6X6bkHVXAoRARflgFYBVyWzW3d98t0WsT8kDH5A1BLAwQUAAAACADdTXxdEdrZ
1ncAAACUAAAASgAAAENPUFlfVE9fS0lORExFX1JPT1QvLmRjcHJvX2ludGVudHNoaWVsZC90b29s
cy9JbnRlbnRTaGllbGRfQk9PVF9QUk9CRS50b29sLc1LDsIwDATQfU5h1DX1MSo2LBAXcBujREqc
YjuquD3hs56ZN9MJ1yxoKUxwbaCtOTxyYXuZc4VDs7PNcGOKsHVVlk+u9SBlIIlQqMuWWGFXVn72
bN9F+LOAVRy74ZKa+dJJ40V8KHfNVHAdf+cfMY/yrm3l8AZQSwMEFAAAAAgA3U18XaW3n29tAQAA
owIAAFAAAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50
ZW50U2hpZWxkX0RJU0FCTEVfQVVUT0JPT1QudG9vbI1S32vCMBB+z19xy4ZuDzXbHicKiqWriIJ2
MBhDYnOuwTYpSeom+McvVfwBk21HXvLdl+++u8v1FVtIxWxGLDoIsCLTySTpsEI5VllSrIQ0EJRA
b2qcRZm2Lqq4EfMplto4y2LlULmIO6QEvzCFbvc/ZLbQ2gVSWcfzvJXrDwqP3cYDcbpKs0O5QTzr
9UfhPB4n4TiZPcfhaDDv+wy9zIh6SUiJKSBYHgjh+A+FS4RoNOn3RpQMOwxdyqrSuzSOibQ02nuu
e7CZxFwEdRetVKslkUt485q3UkBQ3VHowD28Q6Ph0Z2bId1f06KEwO6BH4Pazycxkue/VqM7JV0U
XPlya/DrMj4HXSZwzVSV521wGSoCPryzQ958nuF1OMNLaB7T+kxhtw/YbuGpCeFrnBzfHOY7pO2T
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
fvMBAABxAgAASAAAAENPUFlfVE9fS0lORExFX1JPT1QvLmRjcHJvX2ludGVudHNoaWVsZC90b29s
cy9JbnRlbnRTaGllbGRfVVBEQVRFX1JDLnB1YmWSuXKjQAAFc77COeVCAkmIYIMBBhhOiRsyDoMw
x3Aj+Pq1N92OXvVL+/PzBx7KyPx4eLyOhA8NRr/ukzAQ4vE3MPmyHl51JXPbiQdPKAFgCSC6g9+/
KrWfDUFjrB4esY10x10U1/NGpiASSx3TAQ8ydVVi0BR1Retq9eQVrPVSH7tQMSPfqZPscc9nEe2Y
fH2XQWqisBInuFOEcONirEwB08q67T6cTko2yPKbsyV3iabSot6FdKP9zVEtuV8W3xkBXm4c295n
5muTiDykt+RcFzE6ik577TbcVOyfSr8Sa9WFUn/ss3Z95V5WV+PlER/4Le63pEErmQm1tRABzGNx
CVuTPYm0AJAZ9epqHYdR24JRvu3HexSyG9viiOuCfiTPW3OWvut5ZlREhuFIcIfMbp3Wt2/9Yl7z
ZCRnFTL52nW3yaP8QnryBmzDcolMPXppZ11eOWWvrNT7YtV3vBH7GriOdb8ZJD3lQBMn0qYPfS4K
Hj0xPS7CeYDKMvAoldyGM665vQRsk04rh4y8bTqCO2XDBZp+cHCXNGfjq6umelEUg3ae96n5cuse
F2ltnFKbHsONRp3EUlEanE9XXRKlmPBWlOE5upT5XjZM9ZK0IxatucnEXVsbz3qQ90mSqehCaQwo
DR4A+If4lxA0xf+q+gtQSwMEFAAAAAgA3U18XaZwVQuEAAAAsAAAADkAAABDT1BZX1RPX0tJTkRM
RV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9CT09UX1NIQTI1NlNVTVMVzdsNgzAMAMD/TsEC
ID9jMk5wbIGEoCp0/9IF7oS0dqCaVoqReTdl6FKtNMTOEe5Ksih4i1oRwQRBgiqmFNNlGJbzvMe9
fQ9fp2t9EbRZ4VEJI7oJM2amZZhzLTM50gxp2llDoEhYjXzYAsxFuQ1D9/fnHLfjjuO+1i32Pv6P
yc8jXz9QSwMEFAAAAAgA3U18XYfajT5PBAAAfwcAADQAAABDT1BZX1RPX0tJTkRMRV9ST09UL0do
b3N0R3VhcmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TZVVrbps5DPyfU/gCTfXgS6cJKIpKjU2cwHGK
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
kyaVw/kAqvIfhB7IcgS/HawP1Gx9UjfvZUl5YpehBJ0MRfIoCdjTOqz2eR1jeTbi9+KUg6aZkRk0
mT02xmH/fwClypY1OOsSj+cWCpQJC1W8FieF9XlVFSKU/wBQSwMEFAAAAAgA3U18XRd7Ih74AAAA
rwEAAEYAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byby1p
bnRlbnRzaGllbGQtYm9vdC5jb25mlZDBbsIwEETv+YppihCoCoYjRT21FeqJqvRUxMHEm9qqY0f2
hqQSH1+T9AfwxbMe+83I93jtGwqmJsfSPuKcdPULWXIrLSLLwG0DOicb3iHN38SoTKg7GWiRKYpl
MA2bZOYvz+8fO7w5Trf32pBV6Q0VUXvGF7ndHla2rtQU8mxAX5GDIIUqyJo6H36ykZghLfO0HPZO
G0s4IJ+YHIVlrJc4YjpNR3coKojasWij2GofedvKoMYWn8FIK07eczFGL6LGcQPlB+wYMZnNzMNq
Pt8gWqIGq8FTqfogDrcH4HIB9YYxtqeeSoiTcSKZN5GuY0ZO4f9P/gBQSwMEFAAAAAgA3U18XVTZ
wVKFAAAAsgAAAEwAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4vX21ldGEubHVhNYzBCsIwEETv/YqlZynUuycL4kmxX7BJ
VrMQNyXdFET8d2Mkc5jDzLxJpDkJvDsoEnwSHKB3dkmRRUn0gUr9rrb3HEJbTMfr7QLnOpk9U3Aw
DvthhFnRhEY4Wm3iRTnKDzqFaDAA2hqsfwzFAYujhYqJQiJ0lFprXjBF6yOrzxuX20/3BVBLAwQU
AAAACADdTXxdjTE3CTkEAAB0DQAAVQAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZElu
dGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9kZXZpY2VfcHJvZmlsZS5sdWGdVm1v
2zYQ/u5fwS9DJUw25NqZi6QckK7DWgzuhi1DPwRBwEgnm6tCGiTlLDCc376jREmkLSfZHEAR3557
7u65o8Zj8hG2PAPCylI+lFwbwkROMik0qC0zfAvkTyEfxkaOrx43MP5AWM42BtSEfJEEtjlsCRd/
Q2a4FJNRKTNWkiXd7UfLyb3ModR09ysXeQkfmObZjO5+SNPkXZruE296TnfTdPE2mc7n74KFs4GF
39kG1Nc1NxAc24+KStQ0yHKyZSXPo7z2LR4R/DXMctrSum4Wm9HNhVvX1E3rTAGI+qQCUylB8joy
unmer8D8IQ2z5paIEMWUpv3SV56btZ3Lr6c3/fQn4Ku1aebf3oxA5D5nAQ+/MAORfSQNjaRg2oT8
mcbMmGjYjbj1Y0UtioWMLIXE2vPAeEH8c0/0jZ+jN0QqIqRp93CxqczQ3ESjNG43ShqZyZKYNYg2
WitivbO2xuNaQaTSoIlRLPvGxYp8/oiR1ESX0jQh/XD15fbqt79++nSe2oWCC3RDQQlMw6QFulJM
6BI9I1KUj0TeWZVCrVfDMqMviIAtKFRkgU9GtGHKkELJe9wiVY6gBvTEC+gl3WVSAV0lPEep7hMB
/xjLiqaJRuuZgZwKXiaOCi1YqTE9XGdM5W4kpLpnpRvYKNPVxP5L7tDIN3Db9rXZLuGX5wo0GBub
qMmK/aHNYmIZNasRZrSeati5Qc/RTfhM3VTA180FrGuTbZI8VgVAHpnEPG6SDMWRYCn19FA4DYPa
4ybjTSBlZWhPfgjEkWhj0m1uZy5a7SBUR8wZRaC2wCwepbPGdoBoVAUdyG5/iFHvLZlrceZ9P/5v
UN05ao7g3fmgFI6Z1N7MPG/OFvUAo0TpeFqf7vY76V+itB9Q1JoJIBt8lOfE5dPuJ+z+jq8qWem2
GBKiH7jJ1qTAyi0qpAJYCey+1b/vji/FCz/Dh4HoTr7k0XzhRbXV3QsJqkGmfpJn6XEscGMdp9Qz
0IrdGiDYFaHd1KD5e07QCrh4Xf+0ywForag+BpFL68x2Tfc+994X8WtonFDKiYi8T60BfPlu+hQE
5zXR933CVnONMDfUdpNja0EbcI3ox9n0fxjsiqmzGIAeNrtg9P30CAqLZIntBIkw7CFYJd5lgzdC
PbVZP+INh+3KFQlZKVltCNd9/Uxe9nb6WhGFHd01xVkyXySB323NhbvOFmHvPdRgB951/wD04jnL
7ZEe3VXNSyKOB+UXYD51uiHPXwiBN759v9Gnpw36FX0yaV6PFAO97nl12tZ5m9icWwFtGFc6aoMc
k1yeCjEeOJnT8TQetPXMNZri32tu0EHtDfqLZl7W1RCFwW74SlZhS20B3Ozl4eewkVW2/nkLwrjv
+E48sX8u8hQTtZLpBDuLYzuIjmWNF1Qv69N9unfYwvgfzfTwo7m7Aw6usLj2zNFdjv4FUEsDBBQA
AAAIAN1NfF1Jx1xzegQAAIoIAABUAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50
ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2dlc3R1cmVfZ3VpZGUubHVhhVXPb9s2
FL7nr3hQL3LqyHVaDJszFUiaoDUWpMPirgOywKAlWuIika5EOSkCAwNy2KnAgu5S7LAEwTBkRdBh
3WX2YQcF/T+0v2SPpGQrW4v5IIt8v77v4+PTygp8ntCUckkkExwEj553gNMxTYDxb6gnAd+5TEEk
4IWEBxRGiZBoUO4phlFnKRIeieBJ103os4wl1LYy1spYTDgJaGI1SodNOmYeXTj5ej03b2RSCr7J
SCSCG5kOmR9Q2Rpou6/t86BujCWeaof3xTBlNu/zkEQI6fp0kAUObjM+FHa7ae1aDScVWeLRTpoN
7NVGJybSC23LdpZbjXnww4z51D2elMsRpk/d4yU4traL6ZUEmaBGVhOsL7NidiqBB7jG3fycwfVp
MTuB1GzoJyumf43WYGx8R2ExvajcnmXkOUTFFONstfPCK7PoeOPacKxJU9VeJzDOzyCmPKvV9vMz
BrKYvYY4vxyB/+63YvYjgyj/lYPNA6HM7dY9k7dR1o2L2U+wTprq5WcPEeCzCQMhDmKSHOgyQciw
F/IpcISfgSQDjM0vYKAUcKCqrjFrDAErZm9ISbpWRuGtKPQSYrBen6L3Ca/xwFqXApJi9pIBR+II
S2phlL8D24qP5oCdW8yuiFmUBqNUB4H/WRZ/4TnwiDAItR64eaTK8KCjxfDUghmsDjwopr9gm+fn
Xgjj6xOuOF5wrUIdrOHvIdeKzoMQC3Ej4n/aQYXfIKLdWjyfIlld0dPh/9LSKKcAvuLgEx4aYA58
FuZ/YFoMmp7H6PbunMMBHtJuyGjkl+dS6VxM30hNQ8C4mH2nweVnArpc4kUvQ+7DJtLDnAtH3PsK
y2ngV3xRNP+dA14CmSUUZCjyc2yBHcWEB4j0JVfgX+uWZXgea7CeSQFf0DSLKQa/xRjFSmM0/a5U
n11mgPuv4MnuRgc2u7vrG9tb/e5Ob2un93C9t6UlvLm9+6i7tb3Z33j8uKe5TpaGGTdjSl9aJw3F
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
ZmnKejWO4t7UJLO0I2+R2Tx9RuQscdKtt4M0SWTQf2GWKWj53gLpsG+vgo9K4sAcKS2dnqfQajiq
WJGwoc1JY/39emi2y27d+zpbPopzka8NnpF8eXQq/UXcInf6TXitAQst8QpITVHtVZkshvcwGVfe
qSn3oEfPv/eXO4AxP41bFzOjPE1CaLdYIUQth3i4jAn53hveoMcddVvQ+6cjq7DUyvawcVQI0R/m
X0LI1f+r6i9QSwMEFAAAAAgA3U18Xe2rAT7TAAAAXQEAAFMAAABDT1BZX1RPX0tJTkRMRV9ST09U
L0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9rZXly
aW5nLmx1YXWPT0vEQAzF7/0Uj56dZVlEBPEkyx4WRdY/F/HQTtPZYDszZKaFIn53U93iQTankJf3
e4kx2B1DyruhkgbjJeJQd2wxknDLtsocPD5oEvZuVRiDR+GxyoTEzuts1hLuX56e8bB93R5Qq5SD
UAM15iNhz77pCEEWtFAMiXVnOgFDM9glB5wQhVoSRdzgcLcMhXLF/gfbTWgV17OT3/ts6KN2NXec
Faqrg3h8FtB6K938n5v/M1GzzGa9uTLr6/IdtzgnriL15cV/gNiz9j/pZP4qvgFQSwMEFAAAAAgA
3U18Xc6fJ6gtAQAAKQQAAFUAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRU
cmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9jb25maWcubHVhtZPdasMwDIXv
+xQh113c/TIKg72JcW2ReHWkIssdZezdp27d1ow0UEZ9JfA5R5+FxSCFsXqbVXqCE2dD5Oqpqk2P
Yko2TfAbJtt2lKUtjkM9/9Sm6AEzWAbfgV/bDJ4wZLXeLoYKn0jvmVJaOS2EErBDDwPLwUOYIoL9
tgK6VYKgCuECoxKGNmbhnS2c9tydyCYvjWH32rRRurIqGVgbCaA0nnoTyHe0v9lG8/usq3XEkMD0
LqI5hOefonnJhPUoQI4tOh0iXJhA+9TTE+gjM/FfDB9Q6QOkuOUGQbTjNMDzP0ZwYYSTM/BOf6Hd
E07+XTO0Tb3pK1Ebnhd4kjDv0NssTuCcwCPbeGzLbrBJD4u7xxPLpBIEL1ZiD1RExfejOiFx6Uh1
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
pP0K7XlRobmzqNffvNw5nLjexf6k9g9QSwMEFAAAAAgA3U18XQr+x8rXAQAAAwQAAFMAAABDT1BZ
X1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29w
bHVnaW4vbGljZW5zZV9nYXRlLmx1YZVSwY7TMBC99yssn5yV6wLiQqQcQhWJinZXSsQeQFC5ziS1
6vVEjgOqEP+O27jd7a6WXXJyPO+9ec8z0ympvLS1NGiBGK3A9kBkLTsPLiXodKutNKSscvLzPQlI
0uvWQk0ctLr3bk86DLS9mBhUAegQfVbDZmhFC17bBtlbTiuaiB4HpyDthw17l6R30qsto0xczRKa
RPIq+/0nHu+klS24+NcMVnmNlgRNlkxI+HRzwhC/BRv8+MHZ8x3Y+giL/EyjwA4so7POoZoNva4p
p25Dz2oWPWlGLXAOHaNVUS7y5frLdX6bL5b5x2VBk0fCPTgtTcaa1IGsGb2SAYKOUJqkQ9eBY0na
HiLTbz/y6dc30w/fQ9vYtEmVwR7uA0W1jNL/9aHQNrrNamy0AXYYghA0jnM9FoUZZGwcvXt04a2e
IcXqyEot/GKjzKgQn/kZbqw+4fIoyg94PqYd9S6nNzmEO898JdQW1I41GPbnYQDccck3WRfOhp3g
LDmJHXclfcDNMu8GOD7dxdRxd7FCjTQ9cLpczIvrqljPPxXzz+uiLG/KlFAhPIa117Zl8n4IkSnH
DnzzOEC/t4o9tc4Vr1+wf2DeWKNtWJPXGf+Xv7Hl0V28Wk3+AlBLAwQUAAAACADdTXxdvvx/LSUO
AABuLwAAVgAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
aW50ZW50Z2F0ZS5rb3BsdWdpbi9saWNlbnNlX21hbmFnZXIubHVh1RpNb9vI9e5fMWBjQEpoRXbc
7caJAygSYwuWJVcfab22l6DFkUyYIgWSsqNd7KKn3gssUPS47bm3AgWaY/pH0l/S9+aDnOGH7N1F
D00AmZx58+a9N+976IdTxyc9b0qDmJ46gTOnETkk3363pY81bNsLXPoB5vSJrS2foRhav510h1YH
F28R+Gf4HM6ehdHCSQyTGDGNPMfHp+kqTsIFjfDZi+MVdW0OQj8svYgaJkcxo06yimiMMxKd5+Lb
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
Q5rVKM3kA39P6O/3qFpds4gGlgxXFCMjrmxXcKFhbrzZ6r9AxovIoa9zuoh4LfHjjUayAYKGVh54
BdsSGWYvepYsOqPE444FXcZbh5/WlFj0bbh0cB8tF3z4zX8ujN9H2QoiLDYFPIlJjKyXPGXKcQv0
PNLH533gs18mH4R60H/Uej0JHyPzBx2IYJd23l7e7cYrZhY/I3DiPYCClYk3OtS1N/EQA7Tv49Xl
ydn17Ox/+CKK9OYT7t8k7rHrRSt89gY3rJDyfwBQSwECFAMUAAAACADdTXxd1Ti2u5sFAACFDAAA
UAAAAAAAAAAAAAAAgAEAAAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxk
L3Rvb2xzL0dob3N0R3VhcmRfSW50ZW50R2F0ZV9JTlNUQUxMLnRvb2xQSwECFAMUAAAACADdTXxd
cikUMSUCAADWAwAATwAAAAAAAAAAAAAAgAEJBgAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9f
aW50ZW50c2hpZWxkL3Rvb2xzL0dob3N0R3VhcmRfSW50ZW50R2F0ZV9SRU1PVkUudG9vbFBLAQIU
AxQAAAAIAN1NfF1/rBfjsgIAAAkFAABRAAAAAAAAAAAAAACAAZsIAABDT1BZX1RPX0tJTkRMRV9S
T09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvR2hvc3RHdWFyZF9JbnRlbnRHYXRlX1JPTExC
QUNLLnRvb2xQSwECFAMUAAAACADdTXxdEdrZ1ncAAACUAAAASgAAAAAAAAAAAAAAgAG8CwAAQ09Q
WV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9C
T09UX1BST0JFLnRvb2xQSwECFAMUAAAACADdTXxdpbefb20BAACjAgAAUAAAAAAAAAAAAAAAgAGb
DAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNo
aWVsZF9ESVNBQkxFX0FVVE9CT09ULnRvb2xQSwECFAMUAAAACADdTXxdSxpajTkFAACoCwAATwAA
AAAAAAAAAAAAgAF2DgAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rv
b2xzL0ludGVudFNoaWVsZF9FTkFCTEVfQVVUT0JPT1QudG9vbFBLAQIUAxQAAAAIAN1NfF3Pb6dZ
6gIAAF8FAABOAAAAAAAAAAAAAACAARwUAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRl
bnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFUExBQ0VfTEVHQUNZLnRvb2xQSwECFAMUAAAA
CADdTXxdWwgzrRgCAADeAwAATgAAAAAAAAAAAAAAgAFyFwAAQ09QWV9UT19LSU5ETEVfUk9PVC8u
ZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9SRVNUT1JFX0xFR0FDWS50b29s
UEsBAhQDFAAAAAgA3U18XbMzNDvFDAAAfiEAAEYAAAAAAAAAAAAAAIAB9hkAAENPUFlfVE9fS0lO
RExFX1JPT1QvLmRjcHJvX2ludGVudHNoaWVsZC90b29scy9JbnRlbnRTaGllbGRfVVBEQVRFLnRv
b2xQSwECFAMUAAAACADdTXxdCMeQfvMBAABxAgAASAAAAAAAAAAAAAAAgAEfJwAAQ09QWV9UT19L
SU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9VUERBVEVf
UkMucHViUEsBAhQDFAAAAAgA3U18XaZwVQuEAAAAsAAAADkAAAAAAAAAAAAAAIABeCkAAENPUFlf
VE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL0JPT1RfU0hBMjU2U1VNU1BLAQIU
AxQAAAAIAN1NfF2H2o0+TwQAAH8HAAA0AAAAAAAAAAAAAACAAVMqAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TUEsBAhQDFAAAAAgA3U18XeaG3JMS
CgAAxhgAADgAAAAAAAAAAAAAAIAB9C4AAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZElu
dGVudFRyaWFsL2Jvb3QtbGF1bmNoLnNoUEsBAhQDFAAAAAgA3U18XRd7Ih74AAAArwEAAEYAAAAA
AAAAAAAAAIABXDkAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2Rj
cHJvLWludGVudHNoaWVsZC1ib290LmNvbmZQSwECFAMUAAAACADdTXxdVNnBUoUAAACyAAAATAAA
AAAAAAAAAAAAgAG4OgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwv
ZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL19tZXRhLmx1YVBLAQIUAxQAAAAIAN1NfF2NMTcJOQQA
AHQNAABVAAAAAAAAAAAAAACAAac7AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
bnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZGV2aWNlX3Byb2ZpbGUubHVhUEsBAhQD
FAAAAAgA3U18XUnHXHN6BAAAiggAAFQAAAAAAAAAAAAAAIABU0AAAENPUFlfVE9fS0lORExFX1JP
T1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9nZXN0dXJl
X2d1aWRlLmx1YVBLAQIUAxQAAAAIAN1NfF3Tf7wrsgQAAPsLAABWAAAAAAAAAAAAAACAAT9FAABD
T1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUu
a29wbHVnaW4vZ2VzdHVyZV9wcm9maWxlLmx1YVBLAQIUAxQAAAAIAN1NfF1XDzGRtx4AAEdoAABU
AAAAAAAAAAAAAACAAWVKAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlh
bC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ2xvYmFsX3NoaWVsZC5sdWFQSwECFAMUAAAACADd
TXxdy2Dh/fMKAADpDAAATgAAAAAAAAAAAAAAgAGOaQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9z
dEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzEucG5nUEsB
AhQDFAAAAAgA3U18XcgiKnmECgAAAAwAAE4AAAAAAAAAAAAAAIAB7XQAAENPUFlfVE9fS0lORExF
X1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlk
ZS8yLnBuZ1BLAQIUAxQAAAAIAN1NfF3lmY907BAAAMoSAABOAAAAAAAAAAAAAACAAd1/AABDT1BZ
X1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29w
bHVnaW4vZ3VpZGUvMy5wbmdQSwECFAMUAAAACADdTXxde+AoqrQSAAC+FAAATgAAAAAAAAAAAAAA
gAE1kQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRl
bnRnYXRlLmtvcGx1Z2luL2d1aWRlLzQucG5nUEsBAhQDFAAAAAgA3U18Xa+R7k06GAAAzBoAAE4A
AAAAAAAAAAAAAIABVaQAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFs
L2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS81LnBuZ1BLAQIUAxQAAAAIAN1NfF3uG4dd
cgkAAMQaAABSAAAAAAAAAAAAAACAAfu8AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJ
bnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vaW50ZW50X2dhdGUubHVhUEsBAhQD
FAAAAAgA3U18XXTutNXzAQAAcQIAAGMAAAAAAAAAAAAAAIAB3cYAAENPUFlfVE9fS0lORExFX1JP
T1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9rZXlzL2do
b3N0Z3VhcmQtcHJvZC0yMDI2LTA4LnBlbVBLAQIUAxQAAAAIAN1NfF0NQWlU8wEAAHECAABhAAAA
AAAAAAAAAACAAVHJAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9naG9zdGd1YXJkLXJjLTIwMjYtMDgucGVtUEsB
AhQDFAAAAAgA3U18Xe2rAT7TAAAAXQEAAFMAAAAAAAAAAAAAAIABw8sAAENPUFlfVE9fS0lORExF
X1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9rZXlz
L2tleXJpbmcubHVhUEsBAhQDFAAAAAgA3U18Xc6fJ6gtAQAAKQQAAFUAAAAAAAAAAAAAAIABB80A
AENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0
ZS5rb3BsdWdpbi9saWNlbnNlX2NvbmZpZy5sdWFQSwECFAMUAAAACADdTXxd8Tp8Ur0GAAAYEwAA
VQAAAAAAAAAAAAAAgAGnzgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJp
YWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfY3J5cHRvLmx1YVBLAQIUAxQAAAAI
AN1NfF0K/sfK1wEAAAMEAABTAAAAAAAAAAAAAACAAdfVAABDT1BZX1RPX0tJTkRMRV9ST09UL0do
b3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9nYXRl
Lmx1YVBLAQIUAxQAAAAIAN1NfF2+/H8tJQ4AAG4vAABWAAAAAAAAAAAAAACAAR/YAABDT1BZX1RP
X0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVn
aW4vbGljZW5zZV9tYW5hZ2VyLmx1YVBLAQIUAxQAAAAIAN1NfF3cJC070woAAMYpAABWAAAAAAAA
AAAAAACAAbjmAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3By
b2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9zdG9yYWdlLmx1YVBLAQIUAxQAAAAIAN1NfF0+
cZmUXhkAANRTAABLAAAAAAAAAAAAAACAAf/xAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
cmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbWFpbi5sdWFQSwECFAMUAAAA
CADdTXxdOShYQhMNAAD0LQAAVQAAAAAAAAAAAAAAgAHGCwEAQ09QWV9UT19LSU5ETEVfUk9PVC9H
aG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL29ubGluZV9saWNl
bnNlLmx1YVBLAQIUAxQAAAAIAN1NfF3MnlZ32QYAAG4PAABTAAAAAAAAAAAAAACAAUwZAQBDT1BZ
X1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29w
bHVnaW4vc21hcnRfdXBkYXRlLmx1YVBLAQIUAxQAAAAIAN1NfF3DUaj3CAAAAAYAAABVAAAAAAAA
AAAAAACAAZYgAQBDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3By
b2ludGVudGdhdGUua29wbHVnaW4vdXBkYXRlLXZlcnNpb24udHh0UEsBAhQDFAAAAAgA3U18XcbF
ijHMCgAABhcAAA0AAAAAAAAAAAAAAIABESEBAFJFQURNRV9WSS50eHRQSwUGAAAAACYAJgBOEgAA
CCwBAAAA
