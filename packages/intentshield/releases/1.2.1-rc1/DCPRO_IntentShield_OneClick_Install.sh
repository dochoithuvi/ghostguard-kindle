#!/bin/sh
# DCPRO IntentShield 1.2.1 RC1 - network OneClick.
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
line 2 '1.2.1 RC1 + Kindle Library'
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
    [ "$ZVER" = 4.3.2 ] || fail "1.2.1 RC1 requires ZenOS 4.3.2 for fresh installation"
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
    grep -Fq '# DCPRO IntentShield 1.2.1 RC1 - network OneClick.' "$path" || return 1
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
    echo "SKIP: automatic KOReader launch disabled in 1.2.1 RC1."
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
kWYJx+rh5ZCD5o6X6bkHVXAoRARflgFYBVyWzW3d98t0WsT8kDH5A1BLAwQUAAAACABwS3xdEdrZ
1ncAAACUAAAASgAAAENPUFlfVE9fS0lORExFX1JPT1QvLmRjcHJvX2ludGVudHNoaWVsZC90b29s
cy9JbnRlbnRTaGllbGRfQk9PVF9QUk9CRS50b29sLc1LDsIwDATQfU5h1DX1MSo2LBAXcBujREqc
YjuquD3hs56ZN9MJ1yxoKUxwbaCtOTxyYXuZc4VDs7PNcGOKsHVVlk+u9SBlIIlQqMuWWGFXVn72
bN9F+LOAVRy74ZKa+dJJ40V8KHfNVHAdf+cfMY/yrm3l8AZQSwMEFAAAAAgAcEt8XaW3n29tAQAA
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
DR4A+If4lxA0xf+q+gtQSwMEFAAAAAgAcEt8XaZwVQuEAAAAsAAAADkAAABDT1BZX1RPX0tJTkRM
RV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9CT09UX1NIQTI1NlNVTVMVzdsNgzAMAMD/TsEC
ID9jMk5wbIGEoCp0/9IF7oS0dqCaVoqReTdl6FKtNMTOEe5Ksih4i1oRwQRBgiqmFNNlGJbzvMe9
fQ9fp2t9EbRZ4VEJI7oJM2amZZhzLTM50gxp2llDoEhYjXzYAsxFuQ1D9/fnHLfjjuO+1i32Pv6P
yc8jXz9QSwMEFAAAAAgA6kt8XRBZ039PBAAAfwcAADQAAABDT1BZX1RPX0tJTkRMRV9ST09UL0do
b3N0R3VhcmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TZZVdbiQ3DITf9xR9gd2IFClSpzEoiXIGscfG
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
kyaVw/kAqvIfhB7IcgS/HawP1Gx9UjfvZUl5YpehBJ0MRfIoCdjTOqz2eR1jeTbi9+KUg6aZkRk0
mT02xmH/fwClypY1OOsSj+cWCpQJC1W8FieF9XlVFSKU/wBQSwMEFAAAAAgAcEt8XRd7Ih74AAAA
rwEAAEYAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byby1p
bnRlbnRzaGllbGQtYm9vdC5jb25mlZDBbsIwEETv+YppihCoCoYjRT21FeqJqvRUxMHEm9qqY0f2
hqQSH1+T9AfwxbMe+83I93jtGwqmJsfSPuKcdPULWXIrLSLLwG0DOicb3iHN38SoTKg7GWiRKYpl
MA2bZOYvz+8fO7w5Trf32pBV6Q0VUXvGF7ndHla2rtQU8mxAX5GDIIUqyJo6H36ykZghLfO0HPZO
G0s4IJ+YHIVlrJc4YjpNR3coKojasWij2GofedvKoMYWn8FIK07eczFGL6LGcQPlB+wYMZnNzMNq
Pt8gWqIGq8FTqfogDrcH4HIB9YYxtqeeSoiTcSKZN5GuY0ZO4f9P/gBQSwMEFAAAAAgAvUt8XUL1
35iEAAAArwAAAEwAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4vX21ldGEubHVhNYzBCsIwEETv/YqlZynEu6cWxJPSfkGa
rGYhbsp2I4j478Zo5zCHmTcjqFkYXg0Usb0jHKD1bpFErMh6s4rtrrbXHONGDP1lPMOpIlMgjB5M
t+8MjL354x5XJ7QoJf4ujjHNNoJ1NVh/G8seiD0uWIwVBK1H2dr5CUNyIZGG/KBy+24+UEsDBBQA
AAAIAHBLfF2NMTcJOQQAAHQNAABVAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50
ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2RldmljZV9wcm9maWxlLmx1YZ1WbW/b
NhD+7l/BL0MlTDbk2pmLpByQrsNaDO6GLUM/BEHASCebq0IaJOUsMJzfvqNESaQtJ9kcQBHfnnvu
7rmjxmPyEbY8A8LKUj6UXBvCRE4yKTSoLTN8C+RPIR/GRo6vHjcw/kBYzjYG1IR8kQS2OWwJF39D
ZrgUk1EpM1aSJd3tR8vJvcyh1HT3Kxd5CR+Y5tmM7n5I0+Rdmu4Tb3pOd9N08TaZzufvgoWzgYXf
2QbU1zU3EBzbj4pK1DTIcrJlJc+jvPYtHhH8Ncxy2tK6bhab0c2FW9fUTetMAYj6pAJTKUHyOjK6
eZ6vwPwhDbPmlogQxZSm/dJXnpu1ncuvpzf99Cfgq7Vp5t/ejEDkPmcBD78wA5F9JA2NpGDahPyZ
xsyYaNiNuPVjRS2KhYwshcTa88B4QfxzT/SNn6M3RCoipGn3cLGpzNDcRKM0bjdKGpnJkpg1iDZa
K2K9s7bG41pBpNKgiVEs+8bFinz+iJHURJfSNCH9cPXl9uq3v376dJ7ahYILdENBCUzDpAW6Ukzo
Ej0jUpSPRN5ZlUKtV8Myoy+IgC0oVGSBT0a0YcqQQsl73CJVjqAG9MQL6CXdZVIBXSU8R6nuEwH/
GMuKpolG65mBnApeJo4KLVipMT1cZ0zlbiSkumelG9go09XE/kvu0Mg3cNv2tdku4ZfnCjQYG5uo
yYr9oc1iYhk1qxFmtJ5q2LlBz9FN+EzdVMDXzQWsa5NtkjxWBUAemcQ8bpIMxZFgKfX0UDgNg9rj
JuNNIGVlaE9+CMSRaGPSbW5nLlrtIFRHzBlFoLbALB6ls8Z2gGhUBR3Ibn+IUe8tmWtx5n0//m9Q
3TlqjuDd+aAUjpnU3sw8b84W9QCjROl4Wp/u9jvpX6K0H1DUmgkgG3yU58Tl0+4n7P6OrypZ6bYY
EqIfuMnWpMDKLSqkAlgJ7L7Vv++OL8ULP8OHgehOvuTRfOFFtdXdCwmqQaZ+kmfpcSxwYx2n1DPQ
it0aINgVod3UoPl7TtAKuHhd/7TLAWitqD4GkUvrzHZN9z733hfxa2icUMqJiLxPrQF8+W76FATn
NdH3fcJWc40wN9R2k2NrQRtwjejH2fR/GOyKqbMYgB42u2D0/fQICotkie0EiTDsIVgl3mWDN0I9
tVk/4g2H7coVCVkpWW0I1339TF72dvpaEYUd3TXFWTJfJIHfbc2Fu84WYe891GAH3nX/APTiOcvt
kR7dVc1LIo4H5RdgPnW6Ic9fCIE3vn2/0aenDfoVfTJpXo8UA73ueXXa1nmb2JxbAW0YVzpqgxyT
XJ4KMR44mdPxNB609cw1muLfa27QQe0N+otmXtbVEIXBbvhKVmFLbQHc7OXh57CRVbb+eQvCuO/4
Tjyxfy7yFBO1kukEO4tjO4iOZY0XVC/r0326d9jC+B/N9PCjubsDDq6wuPbM0V2O/gVQSwMEFAAA
AAgAcEt8XUnHXHN6BAAAiggAAFQAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
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
SwMEFAAAAAgAcEt8XdN/vCuyBAAA+wsAAFYAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
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
c7dkdvIfUEsDBBQAAAAIANxLfF3NmOxsux4AAEhoAABUAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9H
aG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2dsb2JhbF9zaGll
bGQubHVhtT1rc9s4kt/zK/jhXJQSmpacycyeHebKsZXENY6dsp2k5rIpFiVCMtcUqeHDtnYu+e3X
3XgQACE5M7s7tZElPBuN7ka/gN3d9U6LhhXN1U3G8tQbhyNvkZfTJPeSWZOVhbdIGhZ656XH7lJ2
52XFPxhV7C2qZBo+ycsZtP146kVexX5vs4oN/Dbba7NlUiQLVvlD0eSE3WUzpjdLqUQ1mNwBGNYw
DMtUi7esXFoNFlDEmmqt2lxnS2a1aaBI1b8+sWqnWZqp2nxe69V5Nq334OO2rFiSsmoX6lXbqiyb
KGXTdhEuWJMV83IwDvwrfxjWZVvN2EHdTgf7w4Nl0sxuBv4gfLo37JYCWI3Scp7lbIADhaGf0T7E
hO+8TSzE1VZrjrx4VVGp0eEDL7M6LFjdtJW7xxkMVdR2j5yX9iG6iv5YsCIaBUgidyyaJ3nNAtE8
EoN9k+CfXkX+3rJo9tp6D34cvT6bxKfn15Pz67dH1xNfNDv6eH3RtZuca82u3p1Ozk7it2cXr4/O
ZPvLyYeLy+uux9ubsm7etkmVxpdsVVZNvccJGzEtO83bghM1e8jqph6shrDXgJUCNz5MmqbKpm3D
sOJ7VGS5x4r0ye6u9+vFJe0/UP+qbRAXHgyX1x7R51H6j7Zu3pXlrTdlcyAVL2tqaHqTTbOGpV5T
trMb7yYp0pxVoQ0KDXkqGw+GTzz4T0DFtz6kJh70NwrCOJnWMbuLxcgE8ROE2JphVhYN7NTFihUD
3Es+RTb3irIh9vaaG1bIOWkzaeGiFW1/ltYEQMEemoEsGRodm6rt+gEavDhALHirJKvqAe80Q+xA
FYER1nkJiIKff3wbemmJk9XhzDmoGliH8onYntdJnc1+8soiX4ce7tQufhUC6/eWVRmrDwH0O9hB
lFqBd18BsgMYrGYNAlCxErCj9tmvvXka4tDXN7Cb5azJvaJdTllVey1g5ywr2gfv6PK9F59eHHt5
si5hP2BqlI1eW9wW5X3hcRbdK5Il28Olynb2/tRFsqpvyuZtWabZw0Btj9jsZZmy/Hvk/5rhNvO1
+gaSYN8Dvy3qdoWEz9KYuvgKZ3y+8jaYz7NohZQ7ECIu8KHIHx5KagAS7g0MLeJlVtdZseiG5KNA
VThL2Tz48gWkl4c4HAC11Y03u0kq7+kqaW5w+YGH1fM8WdSBF4YhTggFs7ys2YCqUlFEuBZFAWCy
zhYFsFBeFgsSyyDExAhfvw61xSlkQqNBUQXTNbCx4u7Rw99G/L9nVPH05xcvnv/8bPTw0wsoKioL
U9pgSToA2Kiuq8clRbj2gt0PfFzql/H+3776XTtAJ9Yfh3w9sBaE6+cAmg0D7D58OUK6w0Y1SJ1i
MaBS2OYFUcFuU/f2WEHZQZJ0YADOnu/HzZefv+J+8uqpu/oRMAEto2c//RLs/zQMEgT0cTiWyUOA
JB41JeeTQfJl/+sw0H6OvnIyS76Mv36PaPXQ66X88ur5GL/hILwMv72Cih+YvYig3bOxXPVDf9X/
89UPimdjhZj15iZq7AcAOXrxy6G35l8exdooCQY4wlPA24O2wVsbrrc17PZh+tg+AFBTgPN7RJIG
Bpx2eJ7CXnyPfgyXINajP74dkgDP4IjHXlw0P3zJnuGQa/qL4/KSl7tj17iHXZ9XkYAdBv+Sfe2I
hFcPDQGvCfk/iKTwI0Cw4N83amJxa9lqhw7CDKSUlta6UBSBtgAyeY9OT6FahmGmo9BWA6ATP+RU
I02egrRjaTBPhUiVUmOgxA7fU5KKOFJAYohWO/TgbLmIL08uzs9++7+L+Pzi/PXZxfGvxjQAD5+D
Tt55KtFoNOrgWQCa7pK8ZUrEJwgd0HwPPg4YF7/QgiDqjYpHf8nVDhpWbOGcI7x/TiTLabZoy7aO
hWLPqYBaR3wEfY/1jdS/2wc9dg/4lAiKX976SHu+PDXjtkjukixPpjnoeUIjOEIVbwUaadbggLvl
fHdegYD1ABG77cpb5S3oMx6p5iB8gTBz5t2yqmC5Oo69rJaWAI3ZlF4yBRDgXEi8ukmgxyqpalDp
vHNSLSqGqg5A6XG9WCpeCG4ym7FVg0iDZrMSmq89gih8ok6bq4MpW2TFpagfSED41tQsn4eiL4Ac
oWZ0yEuBSFIsgm04NNqtY8nOZinpJ5EcnyuOYsvV6ml/zW6cHUUD0t64nBAc2il7qg0piSA+ekB9
wT5fgaUV7+M/DRVNlcxuFSqSYBrMlGKURMAJSAzTKHreAWqhDxY1PHStoEMT7UDcrrgFYxSmiKF+
ccVyltRM1ggi1bRlgG2sYHs+Ukwzi6QQNGfmCi4MxtuMe20IkJ4azGd6Lmf66RdTMjhWPZi9Elib
vYyecxhnO2MAa8i/I5lKQpDE0B+GzCIHbXCSMo2HDcC+sIDFlb9yYEet/NCGBVkWB+vD930TfERz
veZfo5kphNRG7PZ3Qu79fxokcYAaaOxxx1rRua4GCxDTyCAy3NnB48Byq0WVG4vujL/eGoZEE4ZR
KcEgPc7cUFW0iaycZqjQ88r7uMlmt3WEXp4QfnbGkjnmqiqnHOZmvWIDat6U8RKB9SUefWrQ1Q3U
+LuO0YYv91+MtoDo6BKpAbVFoGwM7m/WfIukpBwY+MNSYkdCOPzgghRRhz84VfWxaLKVwllU1iH6
wAbSzrvftXYxLxc4+Gj4KnrholSox7VwSXgAvwb+5eT44tPk8rf40z4oq3OwitMAtKmmFOYMrHAY
hr50EelVtLqOnuTyOJ+gKox4HQ5dGiE3+3XZQoCiOyESfjLU6tHnM8CPgBcGfMjDrnXIz7IeCrsx
Nx6qWKgfDD901uodUlavixkidQGcag6FDoS4aoto1EGCagRgKk6rJDNHEj4mUeP0JLl3DJcxz1ga
gz4EAoLbbrBHfYQY/iiUfC4PE8uBiln6Hk7+Jqmajinx1+NsqDOVxo4dk+/yYW3dcIO/q55VjBUX
v7p8aXUImmiWDvivoat7Uw+YLlObiBH7yEXRUhpcAbdiTPibV2M23qc1g3Z5E87zsqygOTdzu4Kn
Y/bzUD8hhcYl7Ppg2llJoGoxOp2bsLmL4btmVzdhq1fiD2Fm89PWgC3BSZ9NN6lcSCV5VjBTpqJH
WAetvA3uhIWh6kPuT1O/AxwGuP/vhelbQpEG3+40GQOTxnNQ34ETDCVHuvZYDRr8HLTMxkuzZFGA
EMlmqNxDCbqVUoaMipGDcu6B1G2YIIIGHZtkOCVt3nD3K7CuoW/zYa7a5TKBgxQMprosAjL6dGmM
BQYeLfszK5I8wkYHC3T5+zu4qP/yAz+++vj+/dHlb2Hz0PgGSbEl6JzYD5AUNsuVr48XZSU3GrFZ
4N/7BjTzLaDA3txLa1TsyTxo0DJCITJLmsEfSqL6VtxnPxx7l8djP+havEc34oGny27dJznUmk6K
lBrCUZOi8PV3ftvdWe7upN7Ou4Od9wc7V77e/JJQbQ7N0W+0Su65h702W3IpBZV0ZmkdjrnB5Wou
bLG61+c1oO4WVJUiIZtNhElcQ0xFS3uEk6xeoSGJhjpRlquzqOl1PmrBrrxkdQvGKbSsa2g1dPWH
dqCMYbuIOEUf5AzOb1ZVZeXoqDFYr98xmNWAEjDQkLKWsAGwdG+BoRQRtQC7tQVLbA0nuef73wJi
aZ2UyYmQBjNFdlQQzBXNAtsjF95zI4NaC3vDNgJISNRw/KArlBM/8YgIM1DVEk4mqupkJ+rszkoh
Qs6NjQWrvswTHnmBlbM8AzEKFJuvMRoAeJvxkA2Z6g2UwC/yuXv7o/19ECbLLF+r0EAlKdS7KcVC
sV9ZZQuEHOOiFGAB2OCE5nUYmuARQhRZgLTyvqMcQzxxUBlfwF+IC5jCgdSDSI8gSW/oIo26EBOP
LcloYcpQoJaVETIiFqBjcJGGc8ZSCt2i87o707UWaVWuJGe6G/E5Z2A0VHjol63dsGfccpXm/Oj6
9NMk0EMfyYriGRwDDm9hedt31y3SAx1G0pMRogMDooHmJ7PCJT2IsGPRrmKhGXcQ2dAIQol0RMpt
Ab2RVaSjaj3uq2S1gmIFvtyhgGysOsDgiM5VNEooPFKckaiEy7uY94oGjkIuq9CvLv2x31w6uVzD
ZkgMXV1MIRvDyg+NCoUS+cWslusXf2lcHXmy4rC/KYKdYDdszQc5v6xMRlOs4YJaxUa5LDMAiBzg
mgT8IwSo8+lmOuyt3oXJx/egs3HsTejVSPxL3VvDIuBwJZWoW8ZW4rjS3JeYNSC/IF2pk/GOGXZN
3/YiC6/7CTNpv9hD1ug+TGRNDQDDoqUDtBfj5oMCgvlOgdw+AKGCR3qbs0FXK01I+hHpERQ5yLIs
sqbcPIyolwOJn86h7pNbtnEcrJSD4Hf3CIL6kEY/noY8UeAUSUonVZ1Gnc2olTrTDErSyEEAo5NO
Z4G6OKxvYXQsOzk/CRzKIXoU4MztTNXkHoukcqfKZQFWCrUtlpqdaiQqpJcCTl9VJX6r2Eln6czz
tr7pLB1HC64A6S3Ud44mrYNhgFCfQDCQIFesjskiUS4CVaS23OJD4S8w5BgyDFDRgjXX5WoJWP2U
1RnYBZ+zFMpM7xO07UV3dOoSrkYweWa3yYKBhpmkLP3iAyXUezxRSvxpM/8rnB4Rp8AKpBmYZcWM
m9IYAUNdCJWiHA8n3gdPHcyfYQ8YOqnYIgMdrAINCcw/IA2ZxyECKuioyJM16E1iAXKqtJwBpxdc
pxng8iMamn8L+WBWAku5Cirbx4CFDlmXCp1/cBdQNwI9uM0sBUETcE7NDJrZXhvlIDWcO7bbFD24
Fstc/Xr6IaDRYpV75FA8JNcJGescRdTFnA22DJIntYgQho3wmmLRyxeUbOEcG5XtOM+WWbNRK2rK
WzgolCtNngZUrHRW7SiRZb+3rAUzx3IOA9mjo/E6m91qZ24vzAHjfI8WrMO0mPY7n1f6Lh7bUZf/
0HLJgpUOxlpPDXWEmEHBT9ZR513jCxzaUeL/KAnFCfQX1O7YMQ0Mgpaogb69Gm8iAQqeCuIKaE3x
kmQv9ftTc0Tj/hwfJpdv+sOimEf+xALi097wymEecK3bEqQaFCJ98OT0aqjoQjkdeck90g058avv
kZBsLlxI5+4MTt2Fk2ENqkLuipDZNOUJDy79x7Nxrx+f8Oj4+vTiPBAIQITAVxxMfFWn7V34MB72
C9fjoYtKp2zRFjbXadgirEf+h6O3E39bAkMavT6B8zVbnWQV9+Kdzt9n6NZg6cfTM0qeAyhSTBqi
VIB7ONF5MgCcmSBOYBJehLWUTrQ7dqU18O0I7zLGvRLab2AZYI0a414JicCyUjuXRrtpb1f4UYH9
D7jeRCrTgD4PKMHobdmUn2DoS5b7QWphUAQcBYreT84/KhN+25hXN+X9e1a0/tbhPhydT842oFwk
CZOj8UNSMJ4vAmcYt+W3jHpyeny9dR8x0ZCyNrgqIwSdnDAvy9tWnZh3ASZ195NPOqLF6eLLydXH
s2skx4F0s1iaIZEBHztmD6gb0MnlTGsxvdFaOovFm2lGVAiqWQwNY56M4/cFh4mfq8nZZCOGQOmZ
wGzo+MHUX/TA4gy5dwN68z9Ra809WBicOAEBl3irm3Wd0amYrMLeeHC41QBOn+i4susHfyxQ44W+
frAq6wixjS3+eIiQyYN1hGwd3Eej4CYafQvQsNFY+dtW+ro6vrw420RgPwhZfZ+tmAu2EYdt1MEG
o8U/soZUig8oT9dSWBSgNt+I1CEQJDfAixnXRiOKyyTTGoXLevgoDpzHRr1CS6k7qkko9kQhteIh
dvy2+fiSJ644waj19hPM8Als9E+9OUI+kqMb8h10kqGIYHz5e/X34iuIfw84SHhSyLr3FVwUVdF4
gaa33SrJPd9+tlEpljoJmvBKIdmkbCpPtrYqDtaCEv/x+0alklKIuqAaC9HzqEXSMESSmgWUtKZb
UVkdT8nPGuk+2MjyweprlVFH8qZzZIiQNMDDE2+w2UCNTEVWEtFwo+1g9JppaHGlT23u6Uxacge7
0LUX6QlYI1fi9DwrsvrmDTYGhQhzBin7zpH/9Ncyr4z8GOneFgqrOw5OarK6kdHLlXJp6zq5mpq0
xVSn5x8+XgeG0eUIzxv3I5ywi4b9vqYh71ZP8ZoKY2C5485Tgs+sKusaQxBQVNQZ6YYYMp3lLVl+
97iKovTuuCvAuydfgFBuQznokUpjBM4vChpZG9GbQWGJwVkuGGToBOSzGFCZ5gC6yFqRHoaNe2A5
9jSvH/wzEse0uy3KUTjUCM1MntiyB01EgX8Vrm6kfjDrSZtpksYg2xyiRjqlIvlF6OJ8ihvoJwA2
WUhPxpIZIK+i5yJdz7lEPYjQChcdVhygL3jQBGbGpMnuvVwwKYUpM0YLcw5E0qyZEtaulNyyk7s2
wzscOuN9mw3STcmc/WSW30H4J6BHFczSzfpyx0ycMxobIssZQFKeAh1Lf4aMnYs3soFsyXIyufrt
/FhbYRq38DePgb1iES1W4sbMKzJI/YcX2CdLjWjVtm/gum1U7Io7bKz4U9EU6UcUAXyek02XPiuw
kjFCu5CpIJQkxzNDREQWsIknM0tDy0lDEbx+qNAF7b8Qu+kTdCAjMLCkALOzyiks546pTahjleSp
a28E73BoZwBb+WSmyDNlY19cPjGY6JHN7zOCI2/N5oDuSFaksOGktQ5TTT/Qz2ARZgBkITp4HNNU
Up/0WGGb69vE1z3YF2JvubsH/emfs7S5GQyDXsU7li1uTC98DR8sut8bj37Z165J4q1qL+Op80Al
Q/32ihHOiIxfmp9HiiZZ9TJ60Xe+cUoJYU4weAb+8cX59dHxdbCTBjs1fcL/wvFcfjzn3/wAPUTw
IQITYCO1FSVQwNdVCTYsVqYP+LGGD5glwYXD12XyUDdsNexJZUoCA2CXoDKQ6qFH6BTJDqwCGY/m
GR89AndNYtKXViLIyzjH3FUGFQtftwY5L3gYiS9r+eVhLEvGmy4QdSa/YYE+DF9F+09Nm9TRG46w
xrJcQdg+NUd6Yvke3sDeg/xkQIgr5sHk7IAipfyCJQ5JrgbugcDbuwyz7HjEBTQ8zCTTkuxC27zF
AbrURx2uF6OnRPwKXy+BDX5SuOK/nH4EyyczpxXEfAUxrsBK99hupgun8/3N2oZdOPm6BpH0WPGi
wV0A/D/kxIfVPvqEuBvLd7mq7T39bx0FNoKMSiQ7zR8kiwi723FksfiHy4s3p2cTweIPowi+rOnz
YUzf6bNgTUQ8L1k3QuYXfC9egQDWgzWT96RAnAfkoSH/DPlgyANzF8JQmgh4xHGC6oZIuVVyyo6r
ifmdXigNRVsG4FqG8D4j/MI/5xxSEXDlJuOR3KYtE3Iv7vbh6ZLE5kHoPp3wrg033pLrpV8kFV7P
AIGVwr51+YJmtN0RuzJURdmOdMlVlvavPAS+eOLBwzZ066sqFzBXbV85F09CpMROolMI2tbsdkCp
iPrRK9tumc/MbsQbBjrU24MyjlGFQCNLB6ziTqZr9xf7vhzxGoNMXTNeZJDR6on5LIQ76c2RabGx
ofKkultIZ2U/ac5asrFM9arF0YfT3taVeRqZr02kM9jmmPusUeWLYRsSlXMD7Ymy4W9IuWQi10z+
lI46elsmJlrVSBvv3S5v06wabHnQg+61q4b8ARBDu2rYMuLFYejvmdnIO8udNN55t/MeM5GfWPeC
sSd0EU+MoKNRT8iWyvP9DSaqyKdD6GowZs5GlMpkjANTF9Z4th9NJXnTzWA/0RLl566dwys6+k1X
+95RlxWCH13NRrV5y7WSH7ugYuaFiTzCkUpJAmmWlouYApbaZRZKg5kf9pL/9Vm2pYlp116XSdEC
LZXzudFbuJItuLu8LzmellDdS64WbYQwjcTfw86/Mzq0NHNZIPwC6rcM0MrfhA8rr+2Hby6ZaW+2
z9K4UBaZr4r84BUm637sn77a9C9fqO3fOxsduq/W6dllXD28Prq8DvRbDXSpYbeajQPOiAF312+8
z4ABFmncmDfW+P7zC20arWzL0h/2Yx6U/pTnttfIcBdsOEI6H0QcsLteXOnKONYdaSZXoQzGBFc4
QO/Flys9PgRte6Eh6CJSPH2o1uM/vTDUobVcYql+FqrKFHSchId2grTRo59/qNCzDJgRBlOYUbfQ
GOYJNFyIYiETk1dQXBYyPCmwovhZfdPyobclQys4ZKONiZV6JjNR8w+k/UeutH/Lg7X1oql223+T
eUqywFABZm3VXZLURiG00mXB792luP5jLt0LLzvj7+q+t3xTgG5kupNerAcI6N0B+yanAyzr9uwm
1zK2cD8U0M2kSZiPHwI6MWNOV9Sydqj7jn7q1iU+N4HWFkuWsbp6mZc8wkuvUHTFEjXD3kV1xwyu
RzF613KHGyIg+rHbcZjMUHanzjniuZRIJ8fZmCP3I1lUDpb5bqYsy8DFltCwgF8Fh23VgR/3bggR
JNNs4cdxbxL5VF5W0PXSPzvPX3SOf3/cOe68L4N3lfSEs3/nnQCXse+4ia6vfuCKGcidNXRRGTC/
3+0rmZhL4V67pYxC9w3o+Xx0ffzu5OJtwGEBRkVFt7sWLQHUUs4pKch0xLvDX6Rb0Fr6WoO5Rmxp
KtUSAqN06ET1plu7ZHAZubGH2+7z9rPct13iFUxAnQQbmrFROdeyjqyr4izlYy/584LLenNKDB+e
58Ms677mgQlH4orEaTHYD4zrFtZR/FhLQiPpfK/0d0n4tQ8tHIRXgGD/LXGn4aThgZ9NAkEu4tCC
SXpxtJsnvcR0eRdfdwG1mCikX/0PRZGuhLk8QbqVZGuynSSS9pBUysUixRx+0Dl1hMPLusei96Gh
Ytl16PJolQW/GOteTxdQUgtCmPt57eLdQLxpOxj2/FzaGtVhpiC2w2m6Fbnh0NSkzi2L7NChvKpz
qOedR5R3LiHQj0Uda+jdG3EUP0L7L4LuipDhLcR0DrxvfIQ7j8kCwrWfFXO8UuHR4SU9cd68Kpf4
1FU7A+O0nre5hzYc3vZQ918JVsS2eKeRWy8Vz9BelTDS2hNaTyVDrrBL6LltSJj1HsPEPTwDnl/W
Cw47fImUuMRSR44aPbU7DsYvRqOh9eKlEG3C2xJ07iEiFrFU8tCQE8a6tTx/5OLe/IBu2Q+2XnsH
CAMAPBDPIcwP+MNrWijYQfsI3hG/G2y+YyHIA9/LHTppxqDkTt6Y5YqN1NqMas1msl7T0JuKWcVz
wWG4l87o7jhl44GZHt6Wq7wFpcHf2Nd+8fftu4ur67cfjy5P4v+dnMevLy6u+9c1ETdXyA+fhEI9
6NnaJv6UNrHZqW3pwsQJP+K25izDQ0eCdP2z0+PJ+dUkvpy8+Xg1Oel5rbuz0ZwaL6uXxS7ZdHTb
fMqaRHij6wMaf5lQhC5fyzAcv0+OceTEm2ImM6rA6JgNn+gZ+k0Sbbs2bjKNOJlBX2ngMNeVA6rh
99QINtzNn0lZGwWIDSzcfEOaS35cBo0jfQibdOWeTJeSVyGazJ54cnl5cWk+fCBUi02I3jAy1cnB
xRg8YUot1ueepPji/PBk8gn2OX49uT6Kfx5dHSJHUqL6+0l88eYNDzZ1zY3qc59oUq7ARSgc+cOh
wfxSjYtcpz+RvJDsA0fGrX46areZ/gyrWIenixPNi1K9E7k/kOY5Sxp8vUE+0vEq2rcYi3CIGVHx
2en70+tD8RgzP66WdB+iZ2IBU53w9y24g6bwPme7bzL+6jMpBsA5BWvuy+pW3DHUWQdqgCMwRGo9
nNxme6LXXvfUvYZz6qgiNPArzOrjsijIsHAEatQizyfXny8uf42PPpzGH8+PPh2dnqFo/KHFyrye
W7RP+FQCbgsAXJEB7qzT7FVXC7DPR6fX8efTN6cbJ57DxG2jRIb+yPQellsv2Wj4wdoQTKvT4qqd
fqhK1DjcsS5qmdVds5OyYFtei+iIhwjnT2C177E0iDTaSLgiMacTUzgxcbonGnYXjfXelu4CzCcQ
6cJO4HDICFsPOFdJ70A8MBJwbUwdZ9hIP9INWPl1G6n5mQYrDY5Gqny6xKgWZVTvkGZ2MQdqOHxi
3GAwbE3adECF5VuEkpfSh9hRKPDN5JKjOn4DW2zJVBxmQ9KuFHcR/NPDg2We1+4cd6xy3COVA32P
NglPjVFRp8CtAhLWt9ombySFnttNdO77PGx0fLg4O+OH5CG9cYNvsqnYr/h/LOCHL5GO5csUwIMY
pUQhuq1dzm6l6YB5Wfi2VFtVeLVllgBY/Hn9qt7koaB8cVhWH3SObvq0bjFCN14Z/fLC2nXOXmcX
nw/lFXJuaeBb/eTm79/YMu2lMTJH7lq2cwUmvehOL0DSJaN94W/hEkqSOeACdivLMZm2FsmHLJU3
2eEohzOIX3nPeHpqW4c9ujKOUmmRW2d3p2q5Dmbb6+tGQu9pFM14/rfpFLKA+ksg3NziaNe5MmxP
jkMmuvqbuaiOcJnqJPUp0nk33q9yKCh9pZSCaFvvSy2T9ZSZmO6g19l9M45Eqw5DfVW3vz9/zYmC
/wQcV0/+H1BLAwQUAAAACABwS3xdy2Dh/fMKAADpDAAATgAAAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS8xLnBu
Z72XezgT+h/H1UkXktNxS4rzy6Kay69yScJRoVVSSYpGFzExk83EjFpH/ZAwJzuhuSXExhgzbE43
WsMm02qa5ZYxc9may5gdnUvnnF/n9Pz++n3/+jzf7/f9+Tyf9/N8Xs/3m3j0iJuG2no1FRUVDdCB
/cdVVJayVVSWvFu5uKFSSlQNV1FZXQna73ziCk/Mjy/vGjzXMsmiXp3XrQzf7AVf9ThQjwzNecSe
6f8mc4GEJPkeh9g7J3+3lrs5bKvVi6P2toUXCMMHzbXmt0eGhXQ+TWSbbDqOO/vy1PEH2VLetSLa
UiD1qmfJ9WqnugR4qvmm59TpOQXdT/mfFfQeaWyuLQs9Rhua5Ixck0Dg6l9brVy/TAPjyv4Wsg6y
3Ptcmmer9Bh40Og8gRjoru7Tjq29+aoadT7BJlI3GEjGA1FBvNasAlVo+9uNztfzzJ3HUvNkZ/j2
AcxreeZOY+l5zuyJnh+kboLxmVDexQfACO+HpL0i6o6o/LbD23zY7zvu/VIwZfHet5CP4WKSX0PM
8t/CbefCXVoUh0n4sOLjBPbmEWo4y5stP0pePHz2Fsvbr15/GC2cDfCSNWxQI+39L/kvzXwM11pp
53oKirzacLH2MugtjA3XdSvka7K46Jga74z3TPLeYvrv4t8UfxXfWRQPcij4lGPs97wtqhqYWprV
QWfvK8R78pNWJyH/2MWNTZdHGr5ujO1WAz/AA2MwvuxB8b6ORX+9Oob11X068LAlu2QpOr9WMob8
yf7fUuaX5MgtzMdlhKAL2mSqzcHF1FDLlONsHXzI4iak/B99W6bh0seJCrb7s9K3lpYTrGUu/KZN
1orVFnMoBRkcbEAgfygMiNjKebvUGVcZBFavPyOqLhDnH6rhVybqIhJjMuGy2g0ONcsNPtzS4SH7
FUZ7wexiSKgDyEQsxJcMLbHC+HRlTIFvvxe70t4Zl6ySI6AEMKW/Wgz1xeqF5dhEjHoJhtGVc7zJ
J5aobaA1FY2QUy04zZRcxHyBrGn60Vq9tvjtw/CujJru20Slp4/+PgKrSfslbCb0AvPyJb9cOhAU
EYwN7WmUvAe8cVAUMzSdqMNJAb28gZqGWmuzOE3WIYmEyUJa+3c1dWuUs0ES2lTKihGcaacRevDs
dFYHE4UNUHzvvqKW5Vi1IzpG/NyL33DSqWF6RkfwwhtpOBoz0Xd/eJuDwTFlBfsJF5wGeIMN6Bua
NkONaYGaiTBWyVzuFcfoXVEWR3Qbafd7seconIjeBGnPZS9mF4F9UhjYmTqV4613RN+vzJzZDrjb
gQ/g3KcxUiV3AbNnnujkOs6Uxitc4tq8FEfJauVs9xhUXHAzvbBp148ALSwgaOORKc0wD+x249v+
k88ulxHtInqt4x1Js9uEyjwUd7ZhGjwXlOFWy6fUDVNYPaQGBwbd1mAqGj5k+Lp+skzQs7uW5XVd
wgTYzTTP7NwzdkOK3Ol1ljkpihwMMTLkZ5pmGykPGHpgW+SOu+VJOv48En3cq19yHltuXx6EKlnQ
rDeOmp9/V0sVZRnlZvueHO+pDgx+ss+7pzpSme1ryEqne4N3zDNgstG48HOimHbXsizzFljlwCRq
3H15G6pkePK01NCHvGVWEW8QMZqPi0sDUCc05X7WfQ9Q9ImEACTQX0wmXU43rIxuYq5ytiTs1gJ+
uKVhZI9qLQ8KpPXbvnrrICtXz3Rkw9tJbnETRal4h0Be0pCbLVjGpUStvouYMyYQLvT/JLja2J3I
rcejlIGU8PmQIctT/KxUq6LgkPg+dzfPFgP111KSS31cvW1zZn/AW7uR/o0N+FN4u69q0ppzidqy
55TxYoqFcAwGAL1v2/CTNUc+WK2bsFr+Kl8gwGuCmyDfWYYn6X5gZNVVrcytMvD3NBvGSJYqbxSI
3P3P/UuIMRUDzZxxVRAH9frQECuMRZurzyuMRecmQpBzN/LTFObHR1eMv5T4CWJsXJ2zQwq1rVby
pl5uUQX3Uqf8BEnNar8jZeVnM38UcASNy/T8GyVyxLfjVP5nA/6JU0lPS8f3TkigQMTdGKJwVZgz
jqLpor7e2dulOMgM4oKiq77j2H6JUgURIw3kRu7f8I3GpRR8kYyJXyAj4hFnpHbdSaGkpOi9ycr6
/Q6m1iD1+tjTxkLJD+UQZ1zIxZPkvEN5vQYbbF5iLPZ1RBoEO+OQ6RaMtDXu9lHFeTr8h1A3D8Kj
GzsnloShZ3NZeh+C4yK9ynSQWj4e+brDRF6OlvLa0MIUjLi7LXV73YidcsRIhtHlT/Bv73T6niQD
3CUXovr0Z1nK8Uj4AsdQrhBSf2pgV4Xet5y7tKNK1AHwSN1lJuwco0aJjn0XLHOVlxBqRMjYWhr0
kORxSqfrbdqIPU0T6W8fN3PRYzOj946ehmhGkj+ZERfJAHtKPWp8xOn93LASPm/uqXKIQJHwy1pW
z93LVy7I840ZmR7x4a85CRW8iBPoFV2P73WKOqM2gyzcsW3Z3j05gIZipdVsr6ktON3sTHYjklsr
TySKrecJAvy/h27rgBaM9Sj8PYBpczssIlLBNQF+KLVgF83RW/Sn/0fAvVZl+jFGY2gLLRrcqfUd
k8nKUSqUnSRGNaHDMnsyjAQnmnpbYI31MUk68oA70kbwoaaqjfQxDICRCdByagp6A889sAOJRrny
lU+ljCdU+OWqd+LNpvW1j76SOVHNZws1EcTZsljpRJ8XY4ChPpoP5MND3Mehkq4EzxvcS8yqnaBA
sqm+dTBMUhhrAnKMehxi0JgWDYqQDfCdmJlvEQ9Zlyrx0HwPd1iGZdvrqA96KzIC9mIHyp8wFh6J
QTsCn64iQsmWQ5tB7UoQK9rh7kDDBvJMGaYHMdYTJX6luCkShC6Iq5WwKOwoSrqMu+aFZcaAWAFq
HggCYe/pZ5DeWAinC6b397pmCzu5dyrQVxC++NC4eePoPSBDUfXGXZxp1i1mMkjC6QY5Zt3EBkg9
THJymdIojOOdAlmsfHdEC0szLLuBODtJpV6UjTmEZNrs4fihFu4Yp8QH8p7LymKm5p/MA6j0KVm3
v2h2bLTVI2wDQvAYCluYVtiulN9PHhtdXKGr8/wOo13ZRlERoG7akEbTACm6LZWVNd1cAO+G1UWM
pl3QTKl7OEdZ3mVotxB0A02iB5yZe1vmlDbwcvAmTLRu+maFckwy0FfBXVjApmfoIVbJf8CRz9Mz
CyeDriusMPoGjsipH0+zWmNaYOVU1MhpPTN03lBOv6bDTClcPiZRSoAZNxDzz5xMQGFKHNBNkwZ5
9mAtSBdGD3zMLk1+tWaiItk38GCnxTi46fY2IbiExhU3o6jbx1NrpHrlYYPmk4XjS5UpRA3hsT/A
utbq2bgdX3AA25q9FdL+FFnYFbZRrhDPsmXJmyBqTXtM79ZVOTk+zNXWjRONK19vEe7QWWQlDl7k
yk7woBIXwxKInToPue8XCOWYFNMPMVFo0Zt1qlDi4gvnW0j3oUJtRMIQD4UGrgd+9jL6hLF96btk
YJ8jf6cshblcSPiMWZ/Qu+WbYrr6IyaFwL44Qi0wrVMF9zhqm0OWgXXu4Ul5OuJZ3auegi+C90Xp
/x32f7QRc/XH81llcFNeayFeFWrCT1hyqZL69M9F+Wpgk9qHUQy1j3Y5Zte7LR75FgBjb/JacfiP
rF5GtcfYBI2l5OmA+faeZbiY9zknSnn+H2zgxUFAsotPO+YVOUtVY+qv9i2/pVzR9C4YzoUkoj7+
YUAuR/YT957F/AxQSwMEFAAAAAgAcEt8XcgiKnmECgAAAAwAAE4AAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ3VpZGUv
Mi5wbme9lms822kWx/VixrhnlVYRRC9ajdalFA3NiKp2UFV1yWS0tBJ1G0RCIrJNBxnXUUOoJkJb
rSJtBlVBTKfFGioRRFFiiiYa1xIpSjbGzO50Zz+7+2rfnc/zf87znHP+v+d7zrdnPVzVlHcrKygo
qLmdgp1TUNjKVVDYMqokX1AoZyh+raCg0uYGg56PH5wejghHxBn8OC8IFZ+sg9ZlIC93WiQqRWru
VBTuqtxiotFRBsJfy4Be3KrHNmKf0NI6svvsVoDiuNvnZqMZJFPwF+4Blm4KXo/DR0mYY6/1wy8f
uWxxhQsMrEE08DB1wxF4jl0xJz16CM/riV0XrElnnxUX3dmy7DWhY4TStFbavT2TDuWeDb2a9nVO
dWYs5fGHwKAbD/x7SPnVd6pKJFO0ghI1qtugapXwp5HCg7fLUFA9K6wr1wjl/d2qCQqyU6ruH2OE
6snG75GfpurpSFxcKyG6D2WgoTOnLULkG96Yn9d1c1EZPMbSIn0CvU4HbNypJje9TxyNfOp3CgRq
XEmlx34fCwOFnsnSlzQKTLZT12jaYJQmusWDK79w0+fgF17ERzz7EOTVcsFsVQ41PufcC25ed6yF
UyBU+CQ7Hwo0C+AO9MbMQUxEiWA3cKki9Z7j4pcPSpMowTnmL7h/yHbD/DWWDXO7WiGyHxvJCegM
ZD8WDx1VHvRrOC3/Bj6MuEvPjLvWbFojhgeHfOyd4cqddju3gOt/ZufGG5+5IdG1n4w3BYG+SmwP
U8i9Ts+W+QXDYNZ7VIbhMUecA9/xVsjvRykqSFbd+Gj6TxPduwCe7PrG1WlkM27xm7ELjbsBTGP/
+ZW9qf1JS+1k1OlIMplcXq22JU9/8VsV4LJRKXPpJ4btLHzuZZa0zrYTfwAEwtCWuIylZvP16iGP
C6SsCYf+1iH3MxrpZPKLiqzwlyPsCXjDwywy+V5W/MpwVYd9VNyQLviKjCBKZw/EP70pNZ/GjTGk
xCajID64qAirrw3wLra3LHslWxWajbKmV2ycKWWRk1oNell2DXhFA2TfeV/fvS/mA2DPP5iYBP3c
WZc2WB3WeZHLbFxb5QR+OSyJ90Wj0ZgyANMW9FoefgH3UiXiSki+/nxLcGQ6bTa6tyXM6pPj91kV
c0uQVLjEa8AKLWmZLI9lGRYDsRqJ3Jp4O1Bpwq19YQ1sRQQLzpNANB5W1SdIWiEN60vX965lFcKH
0JwZqgbDms9g8ij6BGqiLA87oguIjmnev6+KPfGgApRfBeajhiTUefoYzzsKv5LJKhQyRLLn7t7A
l0mvrgiY35Q13rDO9q2VafQOta7tkx4/NVygyij5kyh+NZ+GEZDjlUk5g6qIa5CdwgXtGscdG7q0
odzR6SZ1eRvizPP6V/h3dTcVbbIpEjXSyX+qzbhiaqVr2r+JX0dD3KZn1lbssFYafMfzUWb9GDxd
y9ausrD6Fx+I441LTXpQXxyn/chIJt2MmORxOsl2wmtMJ2MyJlhQXQ6/nNJ1kePW7mkkUs5Xt/Te
b2ivAEXWoSBw5+wsfrSdj9iPJmBEQSjeZzjXV0akfURRe+IHqjYa8EZ4LQ34jDa9ElKTBiymEbz8
9DEElUE/SkRaZPeCiCnGW9/dtvb+OXaqk1uY99afu2wewJEn5ivaEUHSQdPS+NX0hfM1NEU1EqPx
gL27O5fU5dkdKjVUsrftQEFUfn8gu3wwBCSJwrF0FpYLSTOjOuik1bM1dADa69A7XZWAbkeB6iOx
ntWfigX9zYQ6XxiQUOFfieEchhe3ddBHeff2iITJg4qIUeZSgCCtVVXtY5b8ofLf7cUQhPkIAQ6T
SbLhM87Jj+w443tAtDW7FvHfPZGkQIHN/zlqKrid7aSJBuI8WLIT3OWC4tzn+hCdDdmETq/wF0T3
DecufSXrUmadgMgRV+jrNF60KSHcq1bW+l9nubF2AxII65P3JxGEq5cupnTdvzOOBYkylio32GmG
Idm4qNjvh9xL00Ev4T02weq5AVZhBVL+5TbvGh74+rOfS1rBu2pLc/+Ca1OllrvZg5eHlVjv0j1S
5yO3U/OSayQp9Kc7k++GveD7N6EouqytePMuoRmKYBrANRKFm/8DuAcb2HGhKZsP6bc8P0r5b/IN
sfgLDyVVyH5TVPD0QbmYHjei80jmc374qiiXsHAFW6LDoIf+h0mDNsZK+ymnxcdjlOORKSHhR09a
q88vzto3h7dDMY2PljO+zXT+YFhFdCCU0NuzUp68PgPvV1tZdACnVyi6h0whrKLbf0CJcGMtYY6Q
hLeF2UsEdsKsLw4YeepC+Nrg4jNzVLoBxRCBb00HANzb1QAAizgMDHYc281MvVUT05GENP1FM3DH
OXP3hnw+mLH2wiAXBHrjAquEY8VxhAv6uZzJBcXXQgEZNfK+sxBuQrMT9rHWDadmfKiAiAhZPG5u
Ie9rsu7N6/7Rh9IPCJtW/WCwW0tzTkOBsuUSwXDT7ORSrRDIw88NatGGq+e/JxJnuHxsoP8cv2nN
id/aN6mtJw2vxy6N3jP7RdPK2kT6xjtXx/UQvuYXMQDAcXneTWlOWLPauXhc1gYhNLdZVCXgOusn
G7HrliaOSauNkjWnlxx7BtssiF9p9qlT4GepSjdz8ONrd3NNuopf/TB9G8CcSAXLQrPJEU1mWZ8J
pXa49UXye9gtSxOQ44DwfiSn5e026sNvnA/ZHXui7fr8Tgu1mUxu5jREncHDYHhOj4FnrxRhaggE
WJQInfCrxEfDFgsnhPJYoVZBRfy2ZLcbe8JKjUFJi1179daHctYrpctxDepz3nlvGZVDUhjsi8wq
EwcY9/sw0sz8zwuAiPkxb/WqtLIRoWFFgOXipwU6h11h1lh5zYDYjClNqLeOgUbbQ561e8/iaxT5
mDG7ronQ8+7NyDZgMbGXa3gpMqIH0oB1fGIJAjHK2fiJMtmaeN0sBU+mH0h3arS4vdq2r7/lpjTI
p2+6ra+LMM4jcJofTZ+QFy40TujTk8WausUik+2c3GeKHBL4eRHPIPLYQluiI6R1Tx2r56b3B60P
Hta/gMWIB5oEY+Rt60E8d1vaXE6hrWOvpLVPnA+0mL8TdfzIlPNpyvi75F6p7HHiUDzR3o1z3Rpp
+8Zby/b8IFfemoaqs54eDowyn7wPtx22mBjVYI7fb6Sp4DKJV1GHnxmHiEhS/e4AY73LXTftmary
n6YcTfBXZ47vEkzcrdA3xBAaWr9k/nkkkfPn+u+zTUrlD2IHLaQkvTdEpDxVf6z4IV1SsgGD6vo9
tWQ5yFe4seVT/1PjSl/u6JdfeRKqF+Z7AKVZI49hRw3TfG5nMoYQ1vmfaCrvAcKlSgxBnIDu1Zgz
rSMiFRH0zbnOBXxYnBrfAQqQU/KoegsjqrBwowOL9E+lxqtsMCskzQaqYu/pIk7o7XuiGOyFBiGh
QqmZXIon/h1URIkFEQXpsfsfZNymKUbsGU5W9gk+ZOH8h16enWyzDd7bcDllI0PZTZarfK2oVCUx
9UEGZaOd2SjWO5BsQmYy6dqIVw6546sycNS9093rpb66DpCiEndejE5NWd8h1KOUj8B/1mJd434p
yviBS+PRjdHezcUDxvj8IunvUEsDBBQAAAAIAHBLfF3lmY907BAAAMoSAABOAAAAQ09QWV9UT19L
SU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2lu
L2d1aWRlLzMucG5nhVh5PJRrG55CKYQIM9nKFoXsDEaRYbJUlkOkqYNsDTpEMij7MpZGkQbTGCrJ
ljVjqWikQ4Ys2WaKjqFhxjLGPr7hnK/zO8vv+/55nuv3zv3c9/Xez/089/VO0nlbC4H9oP0AAEAA
ZnnGDgDYTQIAdn3h5TwAFJfxBAIAB+/Bzpx2uDU8mxcV7PBbTnuLnvwxS17SQVdEsiNJq8QCM0En
2hXaFDJzSyUzpM8xRS1T7tyuppWVJTe8LHoq/SzRday/lpfX+QRbf90Ml+gnElvgObj/aW3X7YMu
pbu4o4Sv+LjIMtjCj7UyPTSDqGRDRgSDuigexDAMJS9HQIwWOw2Xu25BAfTzRFGAKZes9s6wM32G
hh3cY5Clv0yis4WMY7r0U0lTqN4+0kpnbgZunxTsEX9qd1JejmZBfA+vTedDqdg9p7zthBZjSCu5
o8CCb4BYxc2TFrwCd0iAuK+TTpQmss1IUrDpNQUgEIQV0eLzPHMQL/xIX1Nkx4RX4I/pf+Kkx0a4
Cf8kp1CaxgP+2YzuSpq66cReqByHbnuVfFEi1Dt74zUVCfuusjc+A7dLCAT4Y/iB/3y0jWXZFbSR
i+iwX/UIzUA5UxE/aBInjE1YxzHhR85KK2ZHCM13+f8b/780KkUbelzdzq8PqjwBvhV23S+wvA9c
Lq2zkOVvGEdfgBYa+0beHpfKizMKHwjzM4JJkbVnErkgrU2f1m+vtdIPg2uNN57s5kdaAtem9LwC
JJsfYzNnyTpNaWNj84zWSvmyb/yhatDLPRHdTL7ombOW8AiT4ClsAoQcOPZutZayMPdJGdb79Ogz
w8YNjMtFnqHBLdPWPOJuRs5LWS4Gj+63siOOexf8hiBlN9zqRYx0F5eQ61eKet4xTahtsaL0TjS+
1sfxWZWIXXzk0l2ETBq7NzqoKK/GJoX+eSVKXHUDk0kVoxQ9zUfnP6ysqvX56qbetPXBs1ydskBI
tmKzStBg3ydsi8+Q6kmK/m/AdWRt+dart6UcB3z+lNGb03Wg29KMzcVVod0yaaT0MZLq7MVNrKs6
urqFLjVdo4xRZ4zRxxoi0MHF8oihl8yfnvc4a56vp2yORvrQvnk9VaYhee8K/mZ2lWbTX7IcPLuW
wKV3tpfYgxFs6v/cxPw2tIrw1SZ2ZlQXN6xmvLK+6TfSwCp71rgM8G+7N/o1q9qnzWovJTcMSb83
s3iEG3Kff3Oqx0vRkqrmM1bBsPZpI/oKuLJHWRDQgaHzcjCTbGbSEKNra+gByzwFG6gKGT1Eay/+
pSugzpjyrHPbgSgO3i/u6YFisnJ6V3xhrR+H+i1aG0Cw3jKGLoOO7rsrecPjdeBgamZhzkiItsri
NnvzKcHgjbYWtrxPtbzP3DwExFrZwMwrDXwjZMil8UvQqxRgXsX2OdRWXuQxneAHZF1j6/fUfgYj
99XilxuLEX2JSlzx4XXyPunPX6YlCK+cj222Nnm/WTbXjmqfXSMrPPB0SQfNe9wJtBoZUfAp9a36
3Yh9bXUcExW2EgMf1avp/tRPZtUyD9sRp0bCG8gPa3bpbGSqfPUTFPKfnrqf1YqoqotEnh2YP7lb
xkNgLGzc8IXJpXokXS7dsjcuovbwWlwX1epcp/7qypObgsbyAr4ubi4KLvYREe4X0jvN410fNeJP
9z72NNsJHehv67uGvYiVNlorFzOiLE87OqWe3WKHbPBhZS7rFHvadTRZFolq2RX3Jdlmv6Rxxbpi
kZ7f3x8R0XV7EGGEeh1uS47NpWXFRTaDbUUKdDafNcEjvJRHu59Zk0VExHCUZmGXjq9neR59PydY
ksK/Hp5KKvrpiQ4EzGXqfsCUS7TTS25T4m1ZQOD+2D2xe6yuOMaAhpWzV/uSSWEj6JeXriGhU42w
muETOhB7M/Hrwfy+DkjOLXH9jVdsSETNHfN0eTLC6TNc2rfW/dRS5LrMMNz2qJlrTBK2Gxhl/SZW
+yc9y3GVhOnNdl2Q7f7RK7gudJ8d9mpxtoakeuUaGscH6xBgiSUn2b7lzauST03oWVpBkdioJy2V
indLJF+RW20kF+DlBybhZlUf7r3vRkUQzHalkiRSu3lTeziWX4E26u48dekHvsW7yWCMOxXNDB2C
zwfKVltBJ7RMCR7aELnfIZdpTJHyI+5UkhqQs3YWvb34B8xVh21+JygUUO9X0DpGRc/HdxtUultk
lZcSVHlTu0NAs0HHb/OZxqRCR9aeHhIaBn2f8KgOwNKEQfhZLRCWL9qNsmptN9wihy0/Bc91ozzu
LYNW7f5nKKm4HhgyIjZEorty8LR38oH9B2KJ3pz0fgP9sAPwInySFU/L/Y1/VdTnJbdj0ya6tLiX
cioTWZFbUp6DehAtaKzt5Ret5HuHPuc7h0TE8ECr2g/j8GrqrdrgU9ihpdQeBT0QNkW+uETSHDpS
WPpCh7v+JTFaCsi5vlMUcxlOlqS/pwJFYklIZR+X0xbNvWx1k+eUd/gOz5AO7+1dRxG9/oCA2Fpt
88zHwsMK+Hkgzk0ThI2JdaO8sx+FzDWybg26qwDBKtiUkddoitgDMWvzqffIJ+28sxJse+3wRmEw
4DtCAxyAVS4QBu+BTgR9qaAZymqy7lJr2Fmv2to5BIfVNFOZe1zuseaAOPc4p7aLp7xH7IL9vZp2
5fPxIrA9F4xEhMCa+CakCCdD2732985LWC4miY4d2O5MprAexTshd0i1EojdPnt57D6KciOqs7Of
rNZyxdZ+z7w6PwvA7VXcFc5cKQ1AXkPx2rwAKmw7+U0Bf2aKu/0RZY3oLWv2l37+r/hU7pXBuqoK
2mHs3/of+E3ltUE9KBfwnz30H3icm9DsvqsuIBPntmCAM6wXHnYzOQni/JJpamwM9eYcB407bpRT
8RyBANhWCX9M/4Lv1HOOstfXuub5HI2j2pXX7m933PvZqIM4EUm/SNph/D/b8b/gG5yS/shx9G+J
caNICHj8iPkj9N8wVdlrfzQxU17kkuGpqbv7EC1urTBXTIzPIFddgP0v9/uoqKhDn9Rm2Ee1IVSq
j7/9IiKhhyNV8vTfqsAO/2K08CntKAhn5ae9qaqTn0mDumtJ11joYXIEbSpnc3MkNHeyH7xPJW1G
S9o+gcRal+zQ2oXDLxgMWhjH9PBKaVkLe+3CqVqRrsm6V4EyCriiRyzM5gxamH6a+d/uVXWQKlkG
BAUDEG6CrgWVq3aFuGtzHFbX7HskmkryX0X18M5mdUtInZhZU8tibip2NauN5IbsKzeoSJt3paxc
etENKe8Z7V66ztlzpXYvzqbbCp+JPnDcPBMnYtbkBknw0G7ZPn0LBqL41dIAlFrGz+IzvRo+4n5f
PhpqBidpiF3aJQSu4N45aWcuBHrAufDCYPo2C8Jv/4PQXyDnrkBEK5rvGAdrVNAIJ5MpE3mCd2e4
vDh3g/hkUOIm389cfITm+SExrAanmtDHq7sXNBu4pSyTtyvTdSIIAK3ilETQwXfRbuAZLiWzBFgf
pEoylXThqmS4VKztrWjbcZqcNs9e872mE9u0CD8YcirfGfMY9i+0diBHdA4oetsFc+ShoXjPzPzH
mDUmBm9MfytnJs4ISlq3SoN6hyKJ3rFq0hjkkzToVK6CsjF0qhCIcIwuUzKn7iM0r7/J4iGgCmKK
DmhWn7vOzJH83fV9ybhVvz2B78uey2HJmbgjuh3pnAzNq+kfAwsN62y/59gCEC88rLrzyjgY6WWo
FIpjocZZa3DsXH31q4+3ssCzS4ukXxEQIPgGRHwwi52Js5ow8yt3LyZ33QYVzRCKZz227DeDDYKu
JBGU00ENAVjgHiA4rzblaXnqUmPuh5ABtqRfSRc7S419xHMqTMdkbrltW81ikLX6IiOjFpR5k9PU
fjyU3CuVQ0q/DZ9ebXdgwG/nbSxNk5MPlUMcp/1k3ao+uk7A7BL0unZjVW2iix1UHM/izRK3bBm0
aUFCwNRn1hwm8syc4y+j9XQlvxbF6SSqIjk3gj7VeZy4talOWKg/u15PvDnUTqd/hoyiN66Hmbt8
oPOIbF1CNY7PGX9ST3wRz8qCL4RmWvgxVL2MyH5u3l/vKZVE9veNl98f4shgpd1LxQfFpEuRDSoX
Nj45fzG2n7TgjlJHsqOXA+6VbXnPv2qyjaBGlTAnsiPSvMYrp1+Itd2pGMcSY7YmF0FEcQu/msia
5s8IlEY3DYvSIDrkeaE0TPLPh62ZpzSgNK4lPGJ1rnyejnr1RsI9zTjwjQ82n7JUqaGkXvmMuoQ9
adjHHKjBNzl1qfs3Bnr3t3mlahAb8cVEE6pnRpitb5fiyuq+e5cCVCNQJ7aSkvTZHH8hNjI6zAUs
yxfjb4o7unKp9jh8fnBQxsDdk6FeQHc+Ou0U2jQHP/SnWM6eLL0f2bKSCpmY9x+DwBoc0LXXL94+
rkwKiU7aImBH1BF5GzPVL2rfPfyy3IRj1Y7JjG3lXE6oUyt2Zq4L5ksuLRyE/VDPDmvTH7SkxwgB
Q7/K5PuCW2xSiQ+BaF1HPRnN7GJ/hOsg+dCDZelTEjRlCButm3pr+gtGK73bGD30E8f9esqDG71w
JqTBLvRjdllp7ssNfxiostKlNcukzs0Fv+5/f1K6qbjcT+Cvupo3M1yYGK1ikrji9ELm6QedljEW
0h06UmA9h8GFUnT7MIPhNyZv6sB6H/S3GMrCJkoUBAypZj4JZQ8Ky5fCKneUdph7wi0y8qaze1op
xY3feTXBVna+/LASTKtGrgpxQXGlixQElllntIupfYCMFleF/zTGCk3L0HZBa6/UB1c0uqCfx7Nu
Vkpjo7Saq6hXnZjK5YO98f3wQ6whmne4pOVG+HB+ka1nteoHbizw9ipfJvWEAe2uFFrbMgpdWNaK
fl7tiu7DPe9U4jephaPB6UxK0rqhF93o1iiSkrwhnv19wgGOn71xcp7hQ1AibBMSWcsbiVd36se3
T0pmatu1ZBUKtCv0+9bIb3pseUE9IBNVLkqwc9caDTY08DBCcyjMM2cgW40yNHeZXq6ZXN99tw0+
TFaD+Tlibq7+bD2nxMyNERywtC+P3DwNExe8uNXKte7UlVk4tEYfT0vP9+29ebH7YVF41mxUwLs8
n4TnTbOI6WUsqqduObhJw48raah9i5jIlyY7ri6V1/tLPYI1kH6uw/cSal9zLPtrCrzZFs2+2Vc3
XITTC6WcXOgMQBaf7W1zTSc7an1/tKzeYkxTznx0AB51bSk3SU7FVgq0FtdEFVyIDP4+b+MpmGf8
bVwJc9YZbRo7n60YRTofxp6IyfKMqlAhcpuYtkSE9y/kS65/kZkE+fS81ThEPTGjETSdThQ0nH3L
aNTXX4cdp8vo1U9+bBdErS3itj8d4DkyW2+pCU42vjmxJ7NEHDaWOpyepElqXv3kOIRI0Tgyrgo+
Xo4hnIjOBmIc0Z6o+oxLuega1wrkkslg2xmpLc6naEl0VNx7lihZb+ZXd5ZxaHnZkVYF9LNxmRxS
uMw9eR0doZEzBx035ETWZM6Fz6sWNd8wxtkoXnhH6ULQ+0hZA6Svrefs+E/x2QsdR2fj+Nb9TLtY
AmWPVfpET2rYZrw20XYfnw06HXGWTKm1+rnj6s+XLb4hgg9GncuhrHEEC0dwyCns7dmj+aeu+334
fziYjFLo7MhJ0hxP7Oa1kc/hsVJWyvq7aJo65q1UActT0NzRcYv+HySPcObMAhEjM882PqwwR5DB
TnceMBXRmtyD0wC/0poAPpVrt31QuGmhLheyYh2vCMNrmU5o63Jkp84/daFz6xYXwH6gL/C1fP32
n1Qwc9szZaZXov8DUEsDBBQAAAAIAHBLfF174CiqtBIAAL4UAABOAAAAQ09QWV9UT19LSU5ETEVf
Uk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRl
LzQucG5nxVhnOJzr1paQRAlSiE6yM9hKiB5kiG6USCQhRJ0Ig1GiDFETgkQ9Ru+jJ4g62oyyEYYw
jDGIkWHrddREH75J9tn7nLPP2ef6vl/fr/d91/Os+1nP9a51r/L23l0dZkZuRhoaGmaQrqYxDc1p
HA3NqV/pqQKa9+Vn3Glo2MJAmmoPfYlkkr8F4VkeZnOd9YLmXN5pbvDfouwxbNhuPEHaedsuIxvo
yHGxaXL8rrmVMbrY/mHy+9w0TlhVbUrxo83MG3I1hDq2WnRlPB7hS/ucXSuVQpuYdoqOLbV3fftY
eEFhIBq7fbi30XfzfPijlwsbYMY7OBo1WjrmC7L03FchvwzvpU6paXtm6xf4H2vIlhEMhugM+wFY
/vTstMsmkLt8UbJissAMmH3TLWc2Q1ymjH0E4lSIPQM4iD49G6usAVW8gxNX7bv4HZEQ7RC0gv5i
OuTVjwTZd/J+V7S/0nQr4buijn0IVfEsPff3k/9uwvfPq5CX3+W/WfRdHoo45TPztB0DTV2sMsfC
PJoX0871MpInij8blCbbpkJjdvIcWCc9OOkMB6i4/3SVl//AL3GsjO8DXEBGdctBoQYyl0oCe8Wf
vgQ4Di1bGc1KxdORrzEKMxsxZ2JvX0A609eZfzBxLqj+YFL6bS39i3Q7ygR+ZbaVuJjV6Z8GCoFd
r6ow8RtOpH2F+mYhPP8GYfkAZvEmePUsiAjpSwRwdQ3KOABA4zEnolxeWZObTP6L5GDXpXHRqRx4
oj0gkcRNR2b0QBXyiu3NT0hCWfZXiNusunDXRhhJCnRwUOyfkWTV+HUkjpXDHI4OMh37oIbrT+RG
Cap6uj/Pw+Zqx2OCnB5sYfbadwVFzDYLRym3romPGf9NStDH4ln9WTXlbyCw07pQfO+Rj0mAS6Zp
dYGnwOtvYsDKdxv5uab7tWnBA3Udjya56SzXUREgp0veTXBT+bW9+XNLbhiBlo2EnXHvjLj6+pQq
q9ZHgc4XvJqZkgD7Vx55eIfAXXx4lYry8qbBpQWeww1y9MS3Tfo/3bjt6Am1sdEbjCekpjKlhH7N
qP34wYBTDV1XdGAFl2cjtkxLdW8tlWxzcEBIZYIGbGroiBWeYolPwK01+ggg5lOSCqt1060eh7WP
zcWxgYftgX0cauiG8LjHwrLMPH5PPMdDgXmqRJLk6nQnS2/ARDQDfeNz+7PbWrjytf2FPG7N/qDJ
Y5sA27EH6qDNE06/WjfI6mqrlGVtl4xqryRxzRhFnpEjnesjAqc/CYezc9fmtlZlg65CBqqsDlPp
QnZ4A78KGKi7bNkyZi7LFL1kp/rNH+74Dzcq5xqilNjUNFuPeIkheyLlSYet2N15QKlt6orAzScs
d6VYk9nTE86b/Aff/d2n1X7HvIP7F9f8cZacbVfcaZmhCLn0tacDTf93B0f2FMotm35DuAWerFv0
I1Sln9CR4Swqg4qfT9KtPIOSCC/GugQLI2qiT82Fh2uCjItNfA5r9xZV7GMRloPKLgvrPWLdR+Au
MvwrLv8BvhSlFVrbnI5MlzKB42POpbYRpzrYCJGsEStGCSh5pcQklCVcNtjoi7wbKNLd12cytxTA
J5McmwhWcZigJ8rNxQ31LQC0tHd+zho1TIqGOiapp9tJP4MqWph9ent3gGjxRe74oKuteTRxXIOj
FWbZ0b3kwHcO61LKytyha8tvlmv5UahzrCWupRTgQkrfS+2ofA7Cv2o8LEvhpTOBFPfeiyZ3upbu
cNi18t0UGw0iJANOFKpZmxv3GzoQjodyn51qWX6gPGP9QDMepQyo5Q2yI9Ydw/JNFsfe4vfadSTl
6Mtw/RyIAPQZfy9kq63Bg2TKO1JkQsGePstpMeQ2xXY3W7lXgoIDVsyyntnJ3wow1zV2z9dn/r74
7X4kdgUrOddZmCVeLQHjZfc6rgTMZbcQrl5AbjMzTDzdrrZEWUUxbOCVMPctkXpwk2Se2fyavmtq
aDy/X3w2/57ZWiOtNRalEUmoSQ4J1BhVjo0cLdOK8JxIv9YTdC+1yjNYqkYXVz7TBpisDcw40Nrx
VdFI/7UWkRRcvDvNd46ksvz1dfKNrh1XoTFWJ4IyOkth8vE1CIf0ckpP1mlKnl9zg9lyS5WOzb1J
bGAvs/mWnvLkGxHn8z22uMhX2PPzlfK+8w77WuOW1YGTGUsqjH3HF01VpMpwDeAcQejTS/REz6PU
zH4qWS5AFPa4hXKTN7PUhVErEvN/GRwi/y/BAc7T4XH9LTri7KXGuclafwoPQqm76VGOH2nvDeJ5
mhbaCn/OIbY5B/G8kcmLImRpwzm4IAi6Fl4ge71tbXlf22b+9TvT0hcOZl00IeE1pkvRPqLNy4dm
FZiPFaTxypBSaiA8zjVc/EWDrHSjZJMFpZLAshF4bCFoyt7FnIGcHzUtDTS9OFJLR46NPFs/Zk2q
ilvXD9jMFKvAY7V5dUtmS86ir4it/mJnmhEU0gIW7nCBJu/CcTr9prcqOwzh1R0RSRZKQ9cDglKa
RjF7I+6vJAxR2enZYxudMvIcNTPqR08VdOGwmNaW5+7rcoIYn/OMbp9hXtpL7xpdvuXacorAQqG7
OEdt9XkKlvaweGVjI/kY6APCK804gozdvfaVy04JhJS5GKZMHhITSyKAPhKO7aTSpw6Wx54fD3wz
Hu01mHIkfWhXJLHoTX5BFxYXlMOR3s7TT+HJBj8n44eCx6Z9PcfVYCyTHrrmrT5P1g0cx7NOzns0
oPDKdmHl/q+uRHWC395L7wRXfZF4rzG9guY9N/c6IiKnmzHYyNRML9s+cHNKmZKTcbC1unx840qU
J4x/iGdA2XtT3Wkx+aivrfMtnOAyfByyWk9rP6fnL2yuswZMimezVIISg5ip+Vhj9ezYOGcjhTCR
GqpwBtp/sj8yEzvOjaGeDit/RSsIopyNbfH9ue8nb8iR91hqNhcelyvXaKq/v15G6BDlO+jOPGNk
1XAhk7tIqFdlTAT0ByuYW8i6xhOKsO886uu4ZjeeQQM9vTO3c15YW3+AMaHWYA11W99v6JbRsZAk
kYNhYtSLY5cks7M/OVhdb+c/GI+Xirfkpxjid6fi+LMJU+lBOY3zohTfe+CJMFUf1gQCYLkB8Cw6
dkch2vETHAYBCyrUcdlV+HuCRkXnnUDkXkvLfb5qdWX9jpAnGZM+U/rukV8P23OgwZxOwwTw0sZy
jPO4vpJfnBbxcmvR+FwZ3vs48deq4ks5zZUW+vCAKAAF1yy7fVrE9D775Ajsb80XQFvNGwIYUz/R
Zg0qV27G7U1FdcNVg5LwG2FIoGSQY038F9Xrdm1rfeSZu3cTCgyxo6snB0ad+iX1KXW3AFajx8X7
zphPAoEikhJku3jvKsAZsZrpDCJLSaQPaORMsYR3BLV8MVnZtLXNZRhyYfnwswGqNcxttqzFWiCe
rWE5ueviW2Yf05VnEX7BGjq/XN6XTFJNLx8Fn25C3oW7jqhjKg4deplLtsRetaQUfNNiJ1FpER54
4AbitvNcfEJp9NbULN0wShIUkdc0nhkRLnFVbApZCPN2BfeGFffyRf+dMfXxvuuC+btZx95j3VFG
r2KyDqP4zj4qTDhB1Xt4mkSXb7AwEJNmD1/rGSOCx3Ivi4qKStTpiSYSLOAERENkqlhjUf/JCY+h
amDRlzYGKybzfR8/SSu4UoutOJnQgH33Nap+MYvUP65bxfNwblK6yhc6dKVj7XzJIhXWsenRz6Cw
YmiLfY7qTyBhlxJ6nKq4oGtJv9AMfDwaJelnsLKFQbmtXuQk+Hhag/ANH2jVKcRYM6u6Qu7Pfe68
D5MUBzTl3/gJFU4rzz5icWDAD8CR7ytX72EEVPmv9+zEbFgGP1ZsVuKZdwIalqFNnfSsUzaVr4KW
LfykDOFeC1lwgucbwHsd1gjmHowHL5vt9k9GS8Ak/i2R/bjd1THBCveHXhHU7IZvGSxiF46jDO/4
N++uFLLrxLYoY+Zx7jlhRsd7FZf9OQAWXUL5LX7l7D0Mcr5tP0lNEZKOA+kse4+0Hzsg1/d0d4uo
//B2gL22QfH7eroUPtTOsxyfNcj41NqLVst+oY4Yv5Gd2fxhgaPd2RAxyuFnD0Ld++N1ASepRcks
FxasM3rLpvulsGulouziQX3LJwYoyQHH7vqGSjgIsGfGo+ANl7Yg04PdF9RcNNb6vnOnsZopmO1x
7ZO616OARffxOMKHAPDtM2LIJ53Q55xQ22V6ogvH/JYCwiEEtpJMcqE1xH20eIac+mqA40feHJJR
88cJhWYzECkKXN9Fnz16XroLJSBI/gn3nw+K4+jIXUyejXlLaQhS61z1jycs4b7aIHWva+vN0ZEY
Bm4JgjQ9MXv4XajkZ+/mnobqEwUxtQdIjHif/crY6ycspRfXMqszv7obwvwM92TCTPjFxWSFG6PV
9KnNAyQNgR2RlroseyMUMWb3EmGWypCe7Jj24z2LvSIpLA0BdLwhb1f4LGSnoDlMrZfOJVs4CEm1
MyyVgfjgCsRcCDLy7IKsVCjCkYvOsJeOnLvP/XH17R4w7Cokbty28s5lpDC74cBqLjAfEppJVann
s+k99SM/+i9+4hTyKyvyT/5Va+D2YxPIrkqnvXnt+Q47ZyQH0H8vueMqxK8I8heZ9v6DTuDpYPAV
eqLWkcr1ukbrUp5wyjoXyFG7vVOsOvoUe0w9nzH4eCeJnIYRw+i8Gg6fmxnQq34Mq/B1nZ8jdfgY
ARVfvgBARiudXq+luT/d2FwNFFDwaBDN83NbE4tGU7jm4xGWHT0MfgcioBvmXrHoPjSkMsPRjpUs
OoFdkR6fuvejeQr38F/kC23nqePLslXVXIkuFgS1DfYJiiGZPpddY3HLG1iC3TuYn7gBJLNKpt0T
Lyw+qS7cumYTBkOd9/a6Bf+9P6IMNl/+cH03+5NuZHkA/ePcLEnrU3AkDFGgWqBv7O6Umi5+aFdM
aejUmrkCciFGl/y2584+i85vzdCX40UWwzInenriPhGSA2CuNK/Rj3utRyXaVcycaMmqeqfGHVz/
qE5piZzE4zR2/t0RRZDorc6Hl5BinJcaVvaXo9FmTGK3Jx5O6uP9TJxDYAxqTHIrLTE6AwKHO0n6
QfRdfxCXbsRM1tFoc1JGDVhWxozJNyn/ysestK89wvACEzdL8GOMgpCEpej7+o5N7csLcXxizBPd
BtXq6PDBpQdu9DsMaOf7fjn6zDz13nfeWY9L9fLFDbwQqlYjyIj0Pb2x0TewVXPC7/Gn3ufqf63A
snu8WkU/Q9dT5EiMLtV5hrvHbtsU+uThm33fWFNvnCtOpdZdWNBZsf9N7fZPdeLv216l35zReZW2
1MFtuFvlYPW1L/RZGGz9AbToUe9Ngzpt/8GaCDfF8yFFDpFC/1YB/oYi3281+VOU2VVIPRuUM9wN
MiqVAZ2Qlt5eGL7Yd14N/aE9Hw1fayD/GhY1bvWiUSFBHbcmOmnuddTreOrJupKZx741A+tRmNk1
iE/2UBFpIeDywVCvYAp3cQVYj55IqtUnSIPw54C0FOV+oJgIVrc7lmkzjnQVpPWWzKN9V5XnUufD
YYmBI4YsCFp/qS6uPnbyV4HMlElN+MMLXhL5MV8/BoCM11sV7pmnBE3yJc7WFhbLghsBpBrg1Zr+
gUry9fIA8OPc5yDm/CTBQKnWtkxazITzzn4ASI+ZBM9RbLh1/wD6YkZrLCJBRbVf8yKSydlxVuSX
m8eioFOfUpKdl5EjWH4DibFguuId10uNfcHFSGPJaGcueSf+B9q4temC04WWkSkFx7at83rL/ELv
QYTnjvX8iQURaUXEeWr3lqch77/opaX7wkkQFNndw5SsLghq0cKDcm6CGJ0+ZlapoyOGw6ZGddUO
LOGJhVfRzrQDC7rGE45CkQhSu+QDWWNjDkF9fHimcwi5fK2MFbAEpK5YWj9fi+VS4HdUNcO7YzMy
vKc7fGMqBaQfGgnN8b7wF014NO7Lh4KdWUg6zjXVcwalH0UC3i8Ut+itXGpVhysF+1jp6SYX+Lec
H7NecPhsUaGxXVC5I0ffpAS7lwNnFddrsh2caF88J3yoFP0C3YGfNL8tq1jGN9TJSP4k5oUVF5AS
fcuezk6kbcLNxsVHqKYVnktlDNmhG3PTg08f3mSnIzPYH1CCi8p55MPTqESKk45XfHe5iYX5P7ru
gAPKmh1aZ53ljGIn2mllrJmqZaxjQSYdN0dVbep4M8E/GJ+r7L+Pqv4N+k+TqL+edL18Gxo7L5vh
INR0K46aljJB9m1a++4SbYz/Ao5SKfAEY5X0y34E277TJ96L1FXxQaHsa5L9HMDL3z/U+ljUPPtT
eUKKINv90bbfFmUwRiWpZAEUx0JstlmuWUFPGsIxPZ2B24b1z4Y0RAfTvqEEE3oBWQ+/DyZBWnc1
y9VtQv4HUEsDBBQAAAAIAHBLfF2vke5NOhgAAMwaAABOAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9H
aG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzUucG5n
rVl5PJR725eKFkuFZE9mQoqmIVuoozAKpZBhqKxjyT52c+hYKpIbY98yyF4MMmMJIfvYaxgK2ccw
GFnGvHrO0znP8z7n8zzv+3nfv+77vj7357p+n999f5fr+j29ra/NeUTwCAsLCydM57ohCwsrkYVl
35dDewGW/JKDriwsgrGw69fu+ZAoZH9zI5u61hXqxDkp/jvLorb2Cshp6QorC7/47Mk7/bTXCLZr
q0DCCw/5jktpRchLesXnoR+OjrlrpdgaDrQPyN8tPB5tCwUn+mqusNk/c/ftFhOyp3KeOS1Uudiz
LbYBXzDtGVvYCAj0obNexhy/Hehzh/WY/a9X9x8QPE08TWQJZhuNipY0t+addIo1Z8j1XsIm3eKx
n7iFNdWMtXNo5OgiQmDQvdvo4kj+bK1Xh+WttLwOyV/NTAp5zR18tifdTBwjfJp4S2Mg4kdKqZT5
zWLqGUu9WAEkd/4zu07i1Gergi/NOoA9a5eS4WFWzh+1n/xefa/2Ifkfufb9r8IuD6IudPiVs253
wL6Xau0quDisfhcigHLMMEYdu64xIiafGa9sTHkERFgRbn6mmAp8p16PZwQCvdPeLOGvnngRI3hi
VmjspcvrfcEl6i8CzvvWu03RVup3TFY4f4mC8L/mCUYpj5yjxy5V7If3xA906MYNjJcVIQHa7pjG
pdOvBz/gHBXIMnNZK1EMQQ6dnWmNI9uyTg7191GL5cSsT2wKr85ioafBtKwDOZfmegD6C/UrXW4b
c/tSwHME6nTg9wdteuVgxFu1mpn0Eyknh/OwLkEp4jk1b/E8Txo4AslBm+WUcYFwERfztbFUptRk
FvXm4y0h2NMmb/Nq29Lmdem5RrTdp+m5nEi24LqgazL9GocxtMv2xXPSyHiI7auT1Lia3DyReRmE
sIl7/8n6WPl6zS6MQUl72cL6qIpZvyXfSB5u9s2U6oxnO0tLyFWTX03YwjyFpOYym8a+AWF6h6LN
4SZbU/ZP9SoW98HaP9e7Xi2PDqIo4MI9+h9tx+2KI5cTVbowl60vHlpbF5LKj8FaCtOXYtYSsXBn
sLPc2/z5gLrdFTYAO7A7sph82dMB7pTRtwH46dD8XzZ80fvqtVos2WYATFoC3S890Q1aDk/1wIwl
b5WVrvGEKSlvVJ5lypaqwoUSA1gS0AjOF83+sSc752HGMWRxLpcVXSeHu/UbIfnArtEv/RNbcbyg
uThQDkTwAH7CESMDw9/s84t1MXyqt8GhZjsyCEKz1icXrvmGYzmBkoBulmOzz/jOIxG5tGE8pEPf
Oo8x3i6+gRmVt2vo2m+8G6AcSLaGFevOMs4FqoOQX0fLwx9FQ1iKsmSGEB054JvYjGQu0+WKvlfO
/kLxo/faLSoKHmwsn/Cr1814YidsRJ/tvZchgG9UOw5XEgGp3ybl7o6FqtbaoWSRz6TrejKNGgBs
bi8HS3DJfc7K9ecfo+3IUY6izidnx78vJYItE0Zxg09/y6LMb24P1G1zMxVLPiyV9s3UwnrXd5Kj
DPBP90k9tSmYNLqh7ASGdqbfPWVr/88w/jtifsfM/yV87SfwTDQEGE0O0V0yNpPBxqx8EsSSYw6m
GMvvZInL8Zs92dS3jyiKq+kqeAZFTNd7PrceFXT5CYnHnr9NvVZ1qWE72txSskKsM2XtY3GOf11e
eBF3+i/kw7ibqYrVdlUGHCTShVUV1eRHxecQX8dVNFRde/39pQPzTXNVLIzimozdD15QvtQ9DGDF
VNOTd9w/Y4SdH500mWy8qDn+Cd55rwZEER0ss7VP4F7lb8vv9dpPKonFjiZVDUYE7LqTc+mSIosm
ebYzeu4qBvDP0kqZg7iOUArqfvQn0dEltHHfi6B1hmCzKHa2k1iSkhXP5w7OSbL+jOoRlqQg+ycJ
EkBNpSeQbi4FU/M+ILLlFbaUHne2zd/LUjk1z85OB8AHTJsR6ZVP8r1AgeS6cQfk7l1fgBdfDIbK
Q3EdAxF9d2CUBLGPuohj8soIYCjcRRlt/2Ds1txqqMJMbnrk9kQRQzrjt8edO+Iq3p9utK5Wdi0H
UpaT+B5adko5CcQygkFgKa2t4dmI3yZNpXuw0djZHNuCbDPhezoJ607f4DaREEpFpStTvhhyFpYl
GQWZ2T8vBNVxEbTqJDw77xQLGheLgkyrF3tekTOW2wsKks3fMSOG1VoSOx4e/9wS2XvZKhKi5tUY
eHTSNjGrQ/xuA2AYpn3w/tB1kXgs13HAQUFNBjwHgfk1fo2kd4Gl4bAXMxTjSND6s+/StZk2k+z1
DAu4B/2wGDJ8aWOFTi87sQ69IQcW072tIrk4RGxzOB84Ls4UEjUFeGVhtI74S4FnQNIg4u6iFoAN
a3e9IifBvDqJiySG5L7NANc8NnObjXRf9bZ4yHJfk9BpWS40dl6vJ2IsNslxzENdMDX2LEyAn+It
GgsSMYmY9BXfZH9xDvtmrqmhw92g2IUMN4wI6mb+Qoop4LE32VwR4IyPK1I0Y/dFFq9+JeAMAWOl
xdH487COwZaVmsu6L7FeSEV+feKRU64Bk7TUUzC8yaqUYjAqp2YtTW7UY75yBTizTlspCnxyIi2F
ow/7Dnf3aLrHpySy/2rofs3KQQrFZ+xYrTpltrr+wyyMUPkWXvZh5jDMj2RHSqzl795ZHVS/l04Q
5tu1rXM1Im6+gbQ4bQAg6qmuy2dhkJZTVnB/IatHIJiaZvbikrvn0QQQtV45za7ls9+i5+fdp68C
Bkfo9m67lDlVDm/ldx1fj9R5kTjG3+U8BXl9crV01RnuQjzHmV6srbaMnTmZE/6Z4rhslEHaJ6Lh
+2mzJqlDZYBWP2mQsfXZ+1isM2FTvDkAOnu2frny7tDtzb4J1VDZsuW2h268YQqeCsvzZsw6z1kK
czCbr89MTiYGwOzbyJIxnydUfmvcvxd6RV/H5h7AH6mdZc6Jk9V9rjev0d/njt82HCIOBuXrPLyv
2cRz7P+LgzLdfScysG+uzBhGtXKW8PtOw5OyXJYhl9M9ijF5Xb0WU9V+pUrnWbvwgCP4X3hqL+NP
g+A52MZw/lLf7uugxXxDslrVHUZlxl8tllEl+rP632Pq2phibAZfe1OZizhn/9IiRak83MGyf6Ax
r+nfaSwRf4W4v/hdSLha0aB3s0uiSTtPNDywdNI1npBa6diNVvfUAu7NZDNK40oTSNzTen5TQ324
ziC/j1tfpD8MfAt+0QvsaEuqF5LNoplfk6bmLQuPWbnrO/uS0HqlMgCWMMGsKUxF6L01ji+guaRl
iLybra2dGhgMXrJA+z+j9NJGtRk5ApRXHjIT3+Qvo70X3H2HKTR6QgWqZaRStOexHMzZLqE6wxQt
g/iaoSxc9MJkCZRXwoXb4IE7+OOuQ4CAy5RlehxAht5Y6WNbuAEDbNLqPJHRfCmCCMVMisrISPOf
VGn3d6oEsORs+BAHhZblzGzXb9hXnIuQta9s8vtA/4JilgOotULqsBT9tPIFtbvq/oPnmeNmUZsz
H1VZNVVKK0U2M61uR2FKbRgkeRhEOvq3g6it0VNWL15HQxzXtPfYRrzqlNWtbqGqrXF5SKG+dcNX
ULMwMzBNcAOUTMM3BzdluVuugEOnNFTOlt4qt4iNhLQckFocigOt25+BWZhFQWwjQPl297GIw3ht
HWBDuzLhNCwZGQnhcYommEvb+xVSkVaRn3OCWhKVRgJ48KWj8a740RNH7urFbchqF15mr7ppGPII
SxgfQUOsFtA9ANZObJsWMOTd491T6RgwocFE0ScqH5uY6nGgp8M7wvPWy5nrVTh6R7d14Ih/in/3
Ps4mmuFRRVaJnh1CEk49oGNTc/+qre5WwMOu6nzJyTolR3S3ZJYQFB3RLYK6Y7j9jb3MkP+Ann7C
PzJ7gDfAuPYQwVRQOfPVx7gdOieR5INQ00xRVBg9Fdv/fuENZFOC16c7sbgs6qVFRUr6wCOrae7e
gu2bbtA1rcHUFL9LJZhFW3tGK2Y1nK0g2r+beNZw/GQ30etMFAR2RA0ZqSx2e/zU33WgLCMrEC3f
kriNK3Md/yEUP5Xgzfa/KkGIAKkZihPdYCzYzJUPsCfrqIpF00o1rPua5XJC/R4/in3TeoLXZXjI
m/Lk2gXMqLefnpvIhd5CiQVtDn9ykOXslmzFmcn9qOo50Mv8BzMIkTOgQQc/Y0NANBYrKfyiykUW
1qsLxF26cu592dn51zgzCDAgM5G3FlLVzB20XYubXuRR7+MiUycpFBvwvJ2txXCddFyjPxZtvox5
8+G4u2DXmWdCaILPu6zJmRohXulwUJuciWGuwW+g0AMkMRdrsyIpza3dpU1pUyAObDMlZl/USE3/
cE4c3ZwFbe/q6oACJS/vmbDDIfCCVebr9Y8K2h8fyj9PWnom8LekNvhCTI2zeEf3eXclJUk94JIs
iXrFdrs08xjST2stvdN8NR0UOiWmVPAyBMPNLtehVlHn5QgT31JmHkVqA/O0qxtHRlwd1pt3g4eF
xcN7ceS18lDxhUaj1vG0wO1nYbCKCktgyIZfOSjBWLfvSHgaAQAjq0k6bX7lXi8ThnQNhcA6fXhc
iuZROBuHUp2br34kiFzoC8L1sVI27tPZK/laFbT2FgzmCxOHbBRMUkvce5xERlYaA5/kYBSGe/Q0
KtbaXjmzIQ3NSfkHe5QXO5dqNxuDxUfm6ZifWgZGRlhkoNZGLR9ZDxsUYc6v+P4CpNOTLttSQ6HM
gArua16bCC6rOmNoITIdMu0WpYZCuuDkRxLlprZJMeUyC/MGdG/lxyOeu60N9WPfvoPfO45Vxz5v
9HwOmYYO+jGt4QEvGYgXp/Z+puJa8oKsdrC6XSRk2hdmWL9DEKaXKrWgxFTk20sOkBvBbdsuLYkU
C2BKJPtzS6JbpawqotI/V8pyvVINvuioGsC+kYUIStB08N++Bv0IyJMWirX2eZdExGC7J8syXE7Q
Z+f0eRbhKNXVq7ef3xhzO9gx9R7iazBYovi9ShwYUJhujPA7rqkavjXGwmQwGkfUalepD4G1PJPk
LS39zcxEraO5ihuOtNFXaxcJgZx183dVMycluW/Ov/la9+VlSQqBVEcoK9K8wFTdXcvPYBBinUZU
HaWnU64pboZWpZWFPa06YWsP1dO93HJqdS6wQRxRJTvoZBX5NooIDqfyis7+SNfSSOVNTs2PqdPb
o1V0nqufR/3Znpz8NP8eok3F1abRB420dwL4E+oaPgYpic3Djyt+iDIfPe4OlxmXxiH76l0eZcvi
QTXaVGssVAOdyaqyEP+ucsYrdcmzGsybm+z6hPtKjxhaDY5wSN4qca69fdzXeE+seR9jr5rMfic8
4WdoqGFH2KNfv+wW/bQmZOhndRD/S+u4yECGaXBaoL5WR2VLASZjxaLC0b5K0NLATHPVbPz0X4oq
SeK+ucxekxwpGVUG7tlq46tuNhgxQr26YJBcdeVCT/q7qYvmMlD5bA7bfyv3f3Tvf63Zf4YzQ3wm
ZjT9uyW/+3+RfOgfY1cSdxXabi5zk0tR0GoSkuDgSypoen7FhArG3cj0LfwQf+I/2IyS5WKX8TKm
04iJhffMHRVWxLdpuJoz99Z9DyfuMjZy2RRJw6+m9VnFeKdI/2O0ea/xnIeKwrLLprrNWWK8jXWe
VwcYOdea1vqJXuO6lv3lkjeU+mU+QTJNtmw7h7lJ+xDPMKi9nnbYE/x2wnHna1ycSuX0mRFczTql
uSqhOqE/1k5RdHxi88y2o0btwsRT5iDuKC9+MUDqmi8ukdb4iU/Q7bE+dAQ1k+ruabhRNFWbPbur
oXskcd1Nl4bgTRbAA7fsV69NAAob0Zg/2h1nbRSX/f3szWVego2Hgyf518oFWhXl8qK+x2Pwt7Sq
+TvT7gErRZh61Mlvb+IXXRv41lJQMMo8oqaMOh2iDkZOK8FWtWZghgkXDgY//tnquJPeaHSt/Aqq
la+gavNdrNE3MfvlYWKWmlnKSmu3XtU30z+7GZJqCwfZXxzcLau80FSVqiF/0cU2hpPQnwqHUfWc
T2rHJGXJuIQNhWSRAuoZL4YlS+ZyYla1ur3sK/P0ZrmP94VGvLyXx7ndn8odMFZLN+mSeeSTlHVH
pbWFHd5U7hR992cfgnKI9Oj4vRcxs25aks8zFkwhFCgrTMtqgwWTIcyFzbuWsViqqvUnug1szmF+
9JI5MJWwUPMQnXy3cI1xgZr3oZMYLxWkWZUFFayLAcH6oa82rKeTN0DS98J1R0IZSP1LvFpP976d
yiV1JQtxD4+waR3doZTiJzU4Y2BpUDWH0rQrL9nCo6EYd9XkW4iEhzFPvgGTXA66Mf9t0nSbDazb
J0X1bdpA7EgHzVZs720g7G55qCDPbPvqbh45Iw7r3Wihi9Hyrx2U+tLNt6d4Di8UmN3JXWHxE2wh
e9Xp9zduW7MikEHpx07IwZ4leiET74RzbhwM9ySPGgHy7o7jrsxpiZMWBP7w/tvX3nEjasMTtomv
rx9+Gy7FugdKFCg19xDfc5eiezmVc6MutpxdgskK8je53oSx/TE8+wMIe+gI/ovwX8CmZLIhQx0u
jU5ovTdfzrda00lkga5FtX3rTzS6EZvLzryj9D8ZPLhKyPmgrx0/5FnxlholjXjNGowK9c5mVdm5
39aTpFjUZK0o11FVF9ix26Fk6UtO086UMcLwJTNfv/WCAwM7HdBgKoEO67+gKgTypYxOGGvKD88j
/YmtybGWedeqzlfTSwMoP6YPHq24ETHtzML7VVuF6FPw/J7ExQwf5fWv+4A4J7V5LoVTn5Fkdxh8
y20Gsum4ky12MKE6xZfdpP7KnHxwyaPx6NEggmOG+MCeNcUa7nXM3s+SmU4fRYbMHt9jlalrEdOH
5Vs5ypbpdZiNW5jTk1PTrxBWvp/sIUwc3DrW37fdJRfPiHzCVm3GCb/l+3DxSJSSYl6SM8FDX1kl
39+YNtYAZJ8rrrAo68q606dRHE7TrrLF38zw3HiNUdAkBEgh4R6M5rIiGyPLiMPO6jrmZdO7vfpy
t/v2zKajvFj6oyon/agSISIKsVtJDiMju4sTswrfkylDIo4g5Grww6ySwDMwEt5rWkkR75NxkKJl
XlRNPEdjnYnqjgVi0aOGn+SLGcfnRsbMVJRdlMwTNGVs7fnbP9aPuBZ9jLlTfRQkrZ+N2D5CktN4
GY8/be+OPytKvGrVSSVnnnduEVNVZNjO8L+uteok1vIbTrwKcq7+6XpPfn6j2pU/uA4d7L3AJczF
8Gsbfke/ibqhYtMpyOjd28uPF1oSb3o9bleYxqFbHWu4CHlSN3NWx3lPJuYqtHxiReiihl/3ncxd
m8jpyv14NEBXQiQFLL2GhUwHXA2c2aOGZ6quaolZpbKgeq2oZ8L5kO/LkoaNNvwGRF0BUb4Hpjxe
A2nt7k4BmQpXCj8eHc2HdF9Qva5TMLjmFMMZvuBu3yyId4hMFRjWXF3Y8FhxbuQSqGQ3XfKkaEKn
0WroecduuYsIvTSzsJvAjnuaonBpRxaf42z7RLEMEOd1DRgo2iYNFDNFlxZIM6npx2slocM1M8ah
EeNE59nIMBeQcv372yLu4QtniDn3zLbB0hD0GYH4cvu6Hld+DbuyMSeRqZyKSrmcBPIrLu0W9lYZ
68fdROE8fp/SMeker+Oz59zt3pM2+vtP8lu/s5uqGQwUqv6uLPHTpUk3krxO93DOX5T/yTapFl/+
YBn7zyXPr5rE/Gl3Nr2E3ECOkYUZHrhhsyjWJfPjErBghKGZjwlD0XiMiduOBdb0P91seyH3ZlDY
cTdNIYXzpuzI3ioKaKQBnfHcu0d5+Aoxskzlb1xCS0e55vDVhSDkStNDI6bytIbBoacJoBudePlO
pbr3MWbbYduKYm/fRA4bNRQ5bLYqvUrFONH5zb/f2RryCszdnd+lvsCjvCjMFt2coJB6tzqS48nc
5Adhsvyr5HfvW6U1N8EfRM8QlyZFSo21tcINw2kjMa4kBZHVqHja4QXmkRvvuJz7m8xxpEecCAFH
0yFiUdZ/HCTIfunV+OJiNGlnFcaWmOVinSuoIQT998cJswvWbjkH8KSLovLdmCvUVmM16kxW1DcY
NKGVcaqSXVaZY1g3U8CmJA7MPvnT1fyVffm/nWD897CsPm/TonL88iPhNmiwLSg/JIX28HwDxz8b
pRKONo6iPOOnAn97DlDI0fpxvdUrai4u1/L8Cs/eu9CDd0RYuxLvCLHqvVKruoTJH5JodSnwIaE9
5VpeXIFqQmE8dqx6uTBoMNt9zX9ZVNUKk2B3C5UtfaTvxzEV7Ib+9ZJfHoT8F1BLAwQUAAAACABw
S3xd7huHXXIJAADEGgAAUgAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRy
aWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9pbnRlbnRfZ2F0ZS5sdWGdGftv2zb69/wVBA5D
7EZW7ba7bq1pwE3d1HeJnXPc3g7DYNASHWmVJU2kHWtB9rffx4+kJPrRHC5AbL6+95N0p0OuokzI
qw0rQjJOJU/lFZOcXLMl6fo90umQbLVK4pS/FBELsweSF5nMZJlzj6QZCfk2DjgZv5z6Z3B2nOYb
+Y7IeM2FZOucxClZx0GRCR5kaSg8ch2nmx25mZM5oOh8IHwLJEkrByY6LPx9I+RaLQRZVoRxCqyI
NmKebiSiDrJ1nnDJQxilkgWSbDmcDKQgWZqUPplk5B6IbwpOwljkTAYRcjr6Op5eXs2GH/yzJAtY
QlBOSh6f3uPQXyziNOQ7WFJTc2i1SQMZZ6nCJVs7r2yTggNyEIvJyBd/FLD6YndRvoAdnob7YKs4
jSVvbSswpTmYUnqebtZLXpwTloZkS+kWB4iVLQUc6eM42tzzY4jjVMQhb+Xesn1G4M+gzxHLEj9z
fzegS3/XtbO+mvXMrFR7pd0r1V7ZO1OUKhqolpQ/tB68yFsxITUpJgQHsY1oD21EYWaRnj0MNOJo
0NUwmnsBH5yiXOs4VWjbL3vdt6+aEggOHiCZZMuEtx4fKByikach8dMTSSYFfXzCAe16q4KtOXwn
wOECdtI48RCj+lsC5W88pCuWCO4FEUsSnt5zPKREovhBZbHhT54SuH2og3cFB65aWhLBk5VvWXhf
T2nXTBpsmBWHKqLHUIFgC5Ufq82CiE2eJzEXZBuLGGT3iHLHXJ1JZVIqTDxQfp9maScDp09Ynsfp
PZGsuOdSYJRcWkokFoQRAfsJ72wEJzkv1rEQIJKKBgmbQcLiNUQ3iSD2HxjEC9vICIjFAVOi+3tK
YMW6VUmikDwccwe1jKZHR6/OK4dHk543vaXa9vkuj0HLbQflwfYAsCP8wU4Hdvr0xy7+aSSrrCAL
D2IBclCcs7gQrccaDtJTIWt/8BVHInpqkzCrfMewgZIsj0ugwqu9t9DbWyj3T5Q9I2eDiEI0oDpq
FEg93vX6FN3owW7ahcie6ParwFawfSSBFJSz1fHHvCV9TgVNAzBFHDMI6BI5YWbCFBeYP3CnVDtl
txEhtc8/Ih3KPI2fLj3wJIhIsJhnrEcP7Pl0diTn5VmcypZC7wkv0MTiFbqzdT/h7xxlC79st4ly
a5tfrEYAEA73UQAYDIyKcVba5XJgFI0YAj9OtyyJQ0wX7/cxam5z+rijgNAr4bN8ajIZgIoLIS0y
nND8PQxVztAjlFHQ3gnsIcVCBMm8o6GAEGRvOykrpYSQgRWdys8q1HZw0UN6kIyp/roI1cKa7YTk
ucnSbNeqlrywXfNaeddhtjQFuRV4UmCObpaAcFNgdqFSANPoGo3dlEtqtYRxjtRwiHJbmTvmEEhv
Ja+WoBCD7brNsiMLFt9H0shpahPQeqkX9s+Hu1NMHNI/gC2fgW0wWsNC6h7tIEXHqvlRLq+AEpby
dwQCA87F99AMJZDKJL8vYllCBuTBNwGixbAPlQBanwYXWNTQdVeV/oziB7TXU0nSWez3MHXWSQn5
1X4yoD+5rUm4aw/oqzfdF7r2qZrsALoHX7+o56WOTWsPyHH+z/tEjbP16dtX+wS0bAVnIkutn1cx
aYNcbdLz8eTr8Hr8cXE3+teX0eRydK79FXoAhDH104WZfh3Nroe3t+PJ1eJyOpkPL+cOmA5hwXm6
QLM35qWLafjL+G4xmc4Xo19ur8eX4/li/hlWjiFt7ZlAuyZgxn5LkakM13uF1c0l9fHLbDgfTyd7
AmrT9d+4hz+N/r34OL6bjyeX88XtdDyZ37kSctkHKg29u/B3n6ezucJwez28HN2MJq4s1q79rv/2
pz17zGajqy/Xw9nidjj/vMesMfng57+fpAyQV6PFp9nwZrT4x5eb2xqDPVI5+vmn4d0cdH0DlMYf
rkeLu/ls+s/RudIl+MUcuD626+ZZdc0ArUO5pwY//Q4sYK5OnaDerMLQZul+tEkwom7drBw8cvO4
ugvBRUc1cNVVCBSffeMEsylM2UpCQwlQBCotYTo1r1mprkxis4bmUPpNfMO0bCBjUvJ1Lu1hAaff
EyzLQDQRGTSOnBXCQXKkza2iWklbq9NEObI6gLrvYzOgO0bRVwumA6gQ2NRgbjwme0LfopG03U2V
Y9WebjYwgGpVWxub0vqobw46T6qhvlGoDyhdUKE8Y1X95TWcoh7WV41K/oWSGXL2n9DlqKFXFT07
8FShg39vryZ7VamyA8/W47oMVwRP16kjhVJXxQZw+RzwQUmtgcFGSRzEcqE40BnRq9ZKu1aC/iSL
Ux4u4H4fowYCH24j4cJu1Ch33T1+bIEvj2+U3q5Hj5Rmrzy2XD4daVRWnIctUDo0+GDbkHtQSDb8
aF8phdNWAoQzV9DOgsbUdkNXOZq9S5qrob2eOg3l45PjrSqzNi6WNlacNUyWz+CvEDrXVCksERCK
mluHkofS1/8T2gbbioJKKHf/mSw+zqa3t6OP79TbCwCXaUAiXnBHIoPG6c9rLAX/YwOZoHI2KE8P
AIeX2JcG5bIk6v3KwVrFodHUwF21CaYWzs1cTb2jSl67VlQ5GdXz5q27YTbR9PoCgcPB6141/qH3
F+3+P1p1iNRvDoh032+avtNogmn9cvFrNfytKZZyeKsW93GjCUGFg71Sx4/fUceAdg83a97stUr4
wV9O8agk9gN7j4R4hZOI1dOZx7zt6JRjJiavdj2833SrLNrIYc0/0w8aYMuO+facjKXPPB1jMWLg
Qtp8zrZpdJBnSju946rAC2lg1O8HPr4OGV9wkR84BLcF7nv4mnfXQwyNue3LtFVfK+c14zdHLVwd
NKR22jq6O4M7sJ3ukWzwd4z3fay2zhj+NW5baI4L9ZxZmjKbsZH9IBV2DzO5v989XPT2Qi7INqmk
9QVHv0gJ9SCl36Pq+FLvTo7FNCx+XvQwIx6GdLaRtBHzCj32LicpnB2GXqCC7sCi37EKMDTo2ScM
Gzcn1a9F0hY4jtScan3vdmWujf4Os4OZlHpiOHFj9CQ/puOdmYPN3xmIegLFXzeCLOnoO+VyI5ER
voXuMg24ei6N8VcS/xTqO5WlyBo6xk2hnmczbNaxI19mMiJsB6QituVkCbKRbCl4seWqgwVRYmF/
1vBPKarSkWmkG9fPvfexkwpALPrxGeHAj379G3xc9H5Ddz7ygoMpyKmOpwOt7rdPRdup6Gv05sDO
0ZZd93Fmhj/U/BdQSwMEFAAAAAgAcEt8XXTutNXzAQAAcQIAAGMAAABDT1BZX1RPX0tJTkRMRV9S
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
AP8w/xKC7v6/qv4CUEsDBBQAAAAIAHBLfF0NQWlU8wEAAHECAABhAAAAQ09QWV9UT19LSU5ETEVf
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
0R/mX0LI1f+r6i9QSwMEFAAAAAgAcEt8Xe2rAT7TAAAAXQEAAFMAAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9r
ZXlyaW5nLmx1YXWPT0vEQAzF7/0Uj56dZVlEBPEkyx4WRdY/F/HQTtPZYDszZKaFIn53U93iQTan
kJf3e4kx2B1DyruhkgbjJeJQd2wxknDLtsocPD5oEvZuVRiDR+GxyoTEzuts1hLuX56e8bB93R5Q
q5SDUAM15iNhz77pCEEWtFAMiXVnOgFDM9glB5wQhVoSRdzgcLcMhXLF/gfbTWgV17OT3/ts6KN2
NXecFaqrg3h8FtB6K938n5v/M1GzzGa9uTLr6/IdtzgnriL15cV/gNiz9j/pZP4qvgFQSwMEFAAA
AAgAcEt8Xc6fJ6gtAQAAKQQAAFUAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
bnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9jb25maWcubHVhtZPdasMw
DIXv+xQh113c/TIKg72JcW2ReHWkIssdZezdp27d1ow0UEZ9JfA5R5+FxSCFsXqbVXqCE2dD5Oqp
qk2PYko2TfAbJtt2lKUtjkM9/9Sm6AEzWAbfgV/bDJ4wZLXeLoYKn0jvmVJaOS2EErBDDwPLwUOY
IoL9tgK6VYKgCuECoxKGNmbhnS2c9tydyCYvjWH32rRRurIqGVgbCaA0nnoTyHe0v9lG8/usq3XE
kMD0LqI5hOefonnJhPUoQI4tOh0iXJhA+9TTE+gjM/FfDB9Q6QOkuOUGQbTjNMDzP0ZwYYSTM/BO
f6HdE07+XTO0Tb3pK1Ebnhd4kjDv0NssTuCcwCPbeGzLbrBJD4u7xxPLpBIEL1ZiD1RExfejOiFx
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
geb8pP0K7XlRobmzqNffvNw5nLjexf6k9g9QSwMEFAAAAAgAcEt8XQr+x8rXAQAAAwQAAFMAAABD
T1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUu
a29wbHVnaW4vbGljZW5zZV9nYXRlLmx1YZVSwY7TMBC99yssn5yV6wLiQqQcQhWJinZXSsQeQFC5
ziS16vVEjgOqEP+O27jd7a6WXXJyPO+9ec8z0ympvLS1NGiBGK3A9kBkLTsPLiXodKutNKSscvLz
PQlI0uvWQk0ctLr3bk86DLS9mBhUAegQfVbDZmhFC17bBtlbTiuaiB4HpyDthw17l6R30qsto0xc
zRKaRPIq+/0nHu+klS24+NcMVnmNlgRNlkxI+HRzwhC/BRv8+MHZ8x3Y+giL/EyjwA4so7POoZoN
va4pp25Dz2oWPWlGLXAOHaNVUS7y5frLdX6bL5b5x2VBk0fCPTgtTcaa1IGsGb2SAYKOUJqkQ9eB
Y0naHiLTbz/y6dc30w/fQ9vYtEmVwR7uA0W1jNL/9aHQNrrNamy0AXYYghA0jnM9FoUZZGwcvXt0
4a2eIcXqyEot/GKjzKgQn/kZbqw+4fIoyg94PqYd9S6nNzmEO898JdQW1I41GPbnYQDccck3WRfO
hp3gLDmJHXclfcDNMu8GOD7dxdRxd7FCjTQ9cLpczIvrqljPPxXzz+uiLG/KlFAhPIa117Zl8n4I
kSnHDnzzOEC/t4o9tc4Vr1+wf2DeWKNtWJPXGf+Xv7Hl0V28Wk3+AlBLAwQUAAAACABwS3xdvvx/
LSUOAABuLwAAVgAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2Rj
cHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9saWNlbnNlX21hbmFnZXIubHVh1RpNb9vI9e5fMWBjQEpo
RXbc7caJAygSYwuWJVcfab22l6DFkUyYIgWSsqNd7KKn3gssUPS47bm3AgWaY/pH0l/S9+aDnOGH
7N1FD00AmZx58+a9N+976IdTxyc9b0qDmJ46gTOnETkk3363pY81bNsLXPoB5vSJrS2foRhav510
h1YHF28R+Gf4HM6ehdHCSQyTGDGNPMfHp+kqTsIFjfDZi+MVdW0OQj8svYgaJkcxo06yimiMMxKd
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
dGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9tYWluLmx1YbU8/W/cRna/+68YEBDA
TSjqw3aQk8IUsizbgm3JlWSnbZISXHJ2lycuueWHZDWwUCBFD0VxQIIeUBSHoucEwaG9S5uiBYra
KPqDjPwfur/k3nszQ86Q3JWc5tKevJx582bmzZv3TS4vs7vbTw722W5a8rQ8nMQ8idiau8qWl9kB
DyKesyCN2P0kGwYJE/3uDejcy1iczqqSjfNgOIzTscNGcT49DXLOeBSXhcOSOORpwVk4CdIxh4Ys
Z/wk4icw8qc8LOMsdW8kWQiIP4qjMS+3s7QM4hTm9FjO/6KKc25bVbxySr0roeqWDfWzNZBonu4+
DtJg3EFQxVPRXkPe5SewOh0sopYaYOcE6NFCw7GththNR9ljXhSAt3+9MQBMBUA9CLaIZLqTPZ+7
R+wfZs/rIcmo0GGTeFiswJ/jLKfzWYb+BjYbt3YvWmqAO3db8w7jKK578yzDPUd8WI1dWA7uwF5z
rENr4BZZlYd8o6iG9vpgYxqU4cS2bPedlUE9/H5QIimibBQn3EZkrmvFxFn+GPrcpApaJ1B04MU5
+LOcWo0hT5JqHKcwosUuG/w5zBF9lgZT7llRCGPFrDip5cSFH2Whn6XJmTcKkoK/UOslrvbESlzB
zsjteoPrEz5fICzoAvhjGngjHrEUCCYvRznhqUJpbkmA+2Kw2NEmg8HGxDT8mjN7ckrYNP5PbueR
uG+y05XXT+21iiPeXhcvyirn/hj7DEo/nUVAurwFX0yDvPQr6jPAD3ae7B8cwcFYK9O0XKmKlfuT
rCjvV0Ee+Qd8luVlsSJEDPKIpVhg93DrzqMdfZxs8nf3jnb2ju5vHe0o4GICoiUC2Lc4Ljx/v8zj
5qwkFiT2DQb/1Vg/y06Bk7w0Tpw4LcogSXgkuMUhxNjzgoa85cE1a/DkZHhizamNqpREIS4PUNgl
MLNTcBAEUTGgCWuptlFMslNbkzsbKT/9DAd4NKqMpzyDpcrRKG9vvhj0zcWfx0VZ2LOgnIg5cg6c
kKKscYMSVjusSi772bnHYPN9aHBCoNV0ZvMTgUcAlB4/cbFTEaw8m8HOBp5npdV0CPKoOQFt9vLD
tVXtPzpcEDQTd5RkWQ7jcUd6wzsSXsyNC1TzeXhe4mgkcnxWEJKjeOiVmViQXbrwiPhLtzzx4be+
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
yP5hADpK3QNlPCSBM7ucHjpValEuCm1UqaxTKwdP4TTm6ZfoPi+iAnRD665VBW5PXw4vvtBpVKMv
eDkajSj9i6e3xqrfeO7U5Paq4QGKEmu+oN8hp7BQP74UwAVeYITBx0qO52pjIbioNVlh+wpjKGgU
n2Dgr9KGmjuepBUP+liZhyLkRXPD8v/NSi5zPgzICmwII1lQet6zCqvQPkMT2BiP8iZZwHnQzAEM
dMatp1/REv0xsDNr9uAejelUBDPnSuxM/Wh4e4NmqvqTFTQi9BLeFsDlwDXYBze+DAbvU5mqepRI
3yXjkrMDWQHdvWgiVzba5LcwmirueCnIILij4HwyDafCRZVth/el0NsT4vvenht+kWJwvLJbmBBJ
8aMZ9uLoWnscVrs5AXYOQcXmG+e0SLRluncgzNUZt4C8BRNxm+bWIKH897Q+n61Oz+YXn+Ll/RL1
sQ5HfPVh9XZ2MT//dLZY3OA7rokw6LyxnCAeLk54sMJhtL64+nbb5XxxdjpPhh9bEOwOD13qwVjA
ItyNg5idcfu5lbJ5IK5pYoi63PVk8Y0yxBI9yG2u0WQL7hyMMUbz9XEi+5Rejo/XsTEcPA4f6+hS
ps1ufdTnkpOQLmegD9oUGql1/fmAp0Zq2g2eWdm7HB27Hl/YBU5lYgJpLC7vXeqBoCbC6P8qslda
dxfME1ppQDP+IG7l8VIL1LTmvhmFsTf0YK4NCobpJN7io2hFVca6O8WocrQ8wHRxhZkvzlPoZMxc
0+7K35vi95J/aOGxfxQH99CVlC1GDbJ9H28uw3Q7ZRuHFMX5gG0qyxYOoyYUFgB9nM+mF1eri//h
lxCU8mbMCI2TjWehE8Sfu1B9Fa6Z/wVQSwECFAMUAAAACAC9S3xdZB3lIpsFAACCDAAAUAAAAAAA
AAAAAAAApIEAAAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xz
L0dob3N0R3VhcmRfSW50ZW50R2F0ZV9JTlNUQUxMLnRvb2xQSwECFAMUAAAACABwS3xdcikUMSUC
AADWAwAATwAAAAAAAAAAAAAApIEJBgAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50
c2hpZWxkL3Rvb2xzL0dob3N0R3VhcmRfSW50ZW50R2F0ZV9SRU1PVkUudG9vbFBLAQIUAxQAAAAI
AHBLfF1/rBfjsgIAAAkFAABRAAAAAAAAAAAAAACkgZsIAABDT1BZX1RPX0tJTkRMRV9ST09ULy5k
Y3Byb19pbnRlbnRzaGllbGQvdG9vbHMvR2hvc3RHdWFyZF9JbnRlbnRHYXRlX1JPTExCQUNLLnRv
b2xQSwECFAMUAAAACABwS3xdEdrZ1ncAAACUAAAASgAAAAAAAAAAAAAApIG8CwAAQ09QWV9UT19L
SU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9CT09UX1BS
T0JFLnRvb2xQSwECFAMUAAAACABwS3xdpbefb20BAACjAgAAUAAAAAAAAAAAAAAApIGbDAAAQ09Q
WV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9E
SVNBQkxFX0FVVE9CT09ULnRvb2xQSwECFAMUAAAACABwS3xdSxpajTkFAACoCwAATwAAAAAAAAAA
AAAApIF2DgAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0lu
dGVudFNoaWVsZF9FTkFCTEVfQVVUT0JPT1QudG9vbFBLAQIUAxQAAAAIAHBLfF3Pb6dZ6gIAAF8F
AABOAAAAAAAAAAAAAACkgRwUAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGll
bGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFUExBQ0VfTEVHQUNZLnRvb2xQSwECFAMUAAAACABwS3xd
WwgzrRgCAADeAwAATgAAAAAAAAAAAAAApIFyFwAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9f
aW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9SRVNUT1JFX0xFR0FDWS50b29sUEsBAhQD
FAAAAAgAcEt8XbMzNDvFDAAAfiEAAEYAAAAAAAAAAAAAAKSB9hkAAENPUFlfVE9fS0lORExFX1JP
T1QvLmRjcHJvX2ludGVudHNoaWVsZC90b29scy9JbnRlbnRTaGllbGRfVVBEQVRFLnRvb2xQSwEC
FAMUAAAACABwS3xdCMeQfvMBAABxAgAASAAAAAAAAAAAAAAApIEfJwAAQ09QWV9UT19LSU5ETEVf
Uk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9VUERBVEVfUkMucHVi
UEsBAhQDFAAAAAgAcEt8XaZwVQuEAAAAsAAAADkAAAAAAAAAAAAAAKSBeCkAAENPUFlfVE9fS0lO
RExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL0JPT1RfU0hBMjU2U1VNU1BLAQIUAxQAAAAI
AOpLfF0QWdN/TwQAAH8HAAA0AAAAAAAAAAAAAACkgVMqAABDT1BZX1RPX0tJTkRMRV9ST09UL0do
b3N0R3VhcmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TUEsBAhQDFAAAAAgAcEt8XeaG3JMSCgAAxhgA
ADgAAAAAAAAAAAAAAKSB9C4AAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRy
aWFsL2Jvb3QtbGF1bmNoLnNoUEsBAhQDFAAAAAgAcEt8XRd7Ih74AAAArwEAAEYAAAAAAAAAAAAA
AKSBXDkAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvLWlu
dGVudHNoaWVsZC1ib290LmNvbmZQSwECFAMUAAAACAC9S3xdQvXfmIQAAACvAAAATAAAAAAAAAAA
AAAApIG4OgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9p
bnRlbnRnYXRlLmtvcGx1Z2luL19tZXRhLmx1YVBLAQIUAxQAAAAIAHBLfF2NMTcJOQQAAHQNAABV
AAAAAAAAAAAAAACkgaY7AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlh
bC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZGV2aWNlX3Byb2ZpbGUubHVhUEsBAhQDFAAAAAgA
cEt8XUnHXHN6BAAAiggAAFQAAAAAAAAAAAAAAKSBUkAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hv
c3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9nZXN0dXJlX2d1aWRl
Lmx1YVBLAQIUAxQAAAAIAHBLfF3Tf7wrsgQAAPsLAABWAAAAAAAAAAAAAACkgT5FAABDT1BZX1RP
X0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVn
aW4vZ2VzdHVyZV9wcm9maWxlLmx1YVBLAQIUAxQAAAAIANxLfF3NmOxsux4AAEhoAABUAAAAAAAA
AAAAAACkgWRKAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3By
b2ludGVudGdhdGUua29wbHVnaW4vZ2xvYmFsX3NoaWVsZC5sdWFQSwECFAMUAAAACABwS3xdy2Dh
/fMKAADpDAAATgAAAAAAAAAAAAAApIGRaQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJk
SW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzEucG5nUEsBAhQDFAAA
AAgAcEt8XcgiKnmECgAAAAwAAE4AAAAAAAAAAAAAAKSB8HQAAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS8yLnBu
Z1BLAQIUAxQAAAAIAHBLfF3lmY907BAAAMoSAABOAAAAAAAAAAAAAACkgeB/AABDT1BZX1RPX0tJ
TkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4v
Z3VpZGUvMy5wbmdQSwECFAMUAAAACABwS3xde+AoqrQSAAC+FAAATgAAAAAAAAAAAAAApIE4kQAA
Q09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRl
LmtvcGx1Z2luL2d1aWRlLzQucG5nUEsBAhQDFAAAAAgAcEt8Xa+R7k06GAAAzBoAAE4AAAAAAAAA
AAAAAKSBWKQAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
aW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS81LnBuZ1BLAQIUAxQAAAAIAHBLfF3uG4ddcgkAAMQa
AABSAAAAAAAAAAAAAACkgf68AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRU
cmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vaW50ZW50X2dhdGUubHVhUEsBAhQDFAAAAAgA
cEt8XXTutNXzAQAAcQIAAGMAAAAAAAAAAAAAAKSB4MYAAENPUFlfVE9fS0lORExFX1JPT1QvR2hv
c3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9rZXlzL2dob3N0Z3Vh
cmQtcHJvZC0yMDI2LTA4LnBlbVBLAQIUAxQAAAAIAHBLfF0NQWlU8wEAAHECAABhAAAAAAAAAAAA
AACkgVTJAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2lu
dGVudGdhdGUua29wbHVnaW4va2V5cy9naG9zdGd1YXJkLXJjLTIwMjYtMDgucGVtUEsBAhQDFAAA
AAgAcEt8Xe2rAT7TAAAAXQEAAFMAAAAAAAAAAAAAAKSBxssAAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9rZXlzL2tleXJp
bmcubHVhUEsBAhQDFAAAAAgAcEt8Xc6fJ6gtAQAAKQQAAFUAAAAAAAAAAAAAAKSBCs0AAENPUFlf
VE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3Bs
dWdpbi9saWNlbnNlX2NvbmZpZy5sdWFQSwECFAMUAAAACABwS3xd8Tp8Ur0GAAAYEwAAVQAAAAAA
AAAAAAAApIGqzgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNw
cm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfY3J5cHRvLmx1YVBLAQIUAxQAAAAIAHBLfF0K
/sfK1wEAAAMEAABTAAAAAAAAAAAAAACkgdrVAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
cmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9nYXRlLmx1YVBL
AQIUAxQAAAAIAHBLfF2+/H8tJQ4AAG4vAABWAAAAAAAAAAAAAACkgSLYAABDT1BZX1RPX0tJTkRM
RV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGlj
ZW5zZV9tYW5hZ2VyLmx1YVBLAQIUAxQAAAAIAHBLfF3cJC070woAAMYpAABWAAAAAAAAAAAAAACk
gbvmAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVu
dGdhdGUua29wbHVnaW4vbGljZW5zZV9zdG9yYWdlLmx1YVBLAQIUAxQAAAAIAL1LfF1EZ4uQYhkA
ANVTAABLAAAAAAAAAAAAAACkgQLyAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
bnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbWFpbi5sdWFQSwECFAMUAAAACABwS3xd
OShYQhMNAAD0LQAAVQAAAAAAAAAAAAAApIHNCwEAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1
YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL29ubGluZV9saWNlbnNlLmx1
YVBLAQIUAxQAAAAIAL1LfF2c2epd2QYAAGsPAABTAAAAAAAAAAAAAACkgVMZAQBDT1BZX1RPX0tJ
TkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4v
c21hcnRfdXBkYXRlLmx1YVBLAQIUAxQAAAAIAL1LfF21CnHvCAAAAAYAAABVAAAAAAAAAAAAAACk
gZ0gAQBDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVu
dGdhdGUua29wbHVnaW4vdXBkYXRlLXZlcnNpb24udHh0UEsBAhQDFAAAAAgAcEt8XUXD5Q73CAAA
/hIAAA0AAAAAAAAAAAAAAKSBGCEBAFJFQURNRV9WSS50eHRQSwUGAAAAACYAJgBOEgAAOioBAAAA
