#!/bin/sh
# DCPRO IntentShield 1.1 Beta 5 r2 - network OneClick.
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
line 2 '1.1 Beta 5 r2'
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
cleanup(){
    rc=$?
    trap - EXIT HUP INT TERM
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
        if [ "$STEP" -eq 9 ] && [ "$elapsed" -eq 90 ]; then
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
    repos=$("$KPM" -y list-repo 2>&1 || :)
    case "$repos" in *kindlemodding*) ;; *) "$KPM" -y add-repo https://repo.kindlemodding.org/manifest.v2.json || fail "KPM repository";; esac
    stage 3 'Updating KPM package index'
    run_busy '' "$KPM" -y update || fail "KPM update"
    stage 4 'Downloading / installing KOReader'
    run_busy '' "$KPM" -y install koreader || fail "KOReader install"
    detect_ko
    [ -n "$KR" ] || fail "KOReader root not found"
else
    line 9 'KOReader already installed.'
    echo 'SKIP: KOReader already installed; KPM steps 3/4 skipped.'
fi
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
    D="$Z/config/defaults.lua"
    # Exact old default schema only. Do not silently write partial settings on future schemas.
    for anchor in 'local library_font_default = FontLanguage.supportsBundledFonts()' '    and LibraryFontPath.BUNDLED_DEFAULT or "default"' '    navbar = {' '            "books", "authors", "series", "languages", "home", "continue", "favorites",' '    library_font = {' '        font_face = library_font_default,' '        font_size = 18,'; do unique "$D" "$anchor" || fail 'ZenOS defaults schema changed; not patched'; done
    if grep -Fq 'custom_tabs =' "$D"; then fail 'ZenOS custom tab defaults changed; not patched'; fi
    echo "Verified ZenOS $ZVER and Navbar schema"
    # Fresh-install defaults only; no modifications to existing user preferences.
    awk '
      /local library_font_default = FontLanguage.supportsBundledFonts\(\)/ {print "local library_font_default = FontLanguage.supportsBundledFonts()"; getline; print "    and \"fonts/readerly/Readerly_R-Regular.ttf\" or \"default\""; next}
      /^    navbar = \{/ {n=1; print; print "        custom_tabs = {{id = \"ct_1\", type = \"plugin\", label = \"DCPRO IntentShield™\", plugin_title = \"DCPRO IntentShield™\", icon = \"settings_lightning_bolt\", plugin = {key = \"dcprointentgate\", method = \"__menu_submenu\"}}},"; print "        next_custom_id = 1,"; next}
      n && /show_tabs = \{/ {print; print "            ct_1 = true,"; next}
      n && /^( +)(continue|favorites|authors|series) = true,/ {sub(/true/,"false"); print; next}
      n && /"books", "authors", "series", "languages", "home", "continue", "favorites",/ {print "            \"books\", \"home\", \"ct_1\","; next}
      n && /^    \},/ {n=0}
      {print}
    ' "$Z/config/defaults.lua" > "$Z/config/defaults.lua.dcpro"
    grep -Fq 'key = "dcprointentgate"' "$Z/config/defaults.lua.dcpro" || fail "Navbar anchor"
    grep -Fq 'fonts/readerly/Readerly_R-Regular.ttf' "$Z/config/defaults.lua.dcpro" || fail "Font anchor"
    grep -Fq '"books", "home", "ct_1",' "$Z/config/defaults.lua.dcpro" || fail 'Navbar order anchor'
    lua_check "$Z/config/defaults.lua.dcpro" || fail 'ZenOS defaults syntax check'
    mv "$Z/config/defaults.lua.dcpro" "$Z/config/defaults.lua"
    mv "$Z" "$P/zenos.koplugin" || fail "ZenOS install"
else
    Z="$P/zenos.koplugin"
    ZVER=$(zen_version "$Z") || fail 'Existing ZenOS version unknown'
    version_at_least "$ZVER" 4 3 || fail 'Existing ZenOS below 4.3; upgrade using upstream before retry'
    check_zen_capabilities "$Z" || fail 'Existing ZenOS capability mismatch; not overwritten'
    echo "Existing ZenOS $ZVER preserved; configure Navbar/font through Zen Settings if desired"
fi
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
BOOT_STATUS='Auto Boot: not supported'
if [ "$MODEL" = 'Kindle Basic 2022' ]; then
    line 7 'Checking Auto Boot support'
    if /bin/sh "$TOOLS/IntentShield_ENABLE_AUTOBOOT.tool" prepare; then
        BOOT_STATUS='Auto Boot: ready (opt-in)'
        echo 'Auto Boot job ready; existing markers unchanged.'
    else
        BOOT_STATUS='Auto Boot: preflight refused'
        echo 'Auto Boot preparation skipped/refused; see boot-install.log and boot.log. Normal installation continues.'
    fi
fi
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
    grep -Fq '# DCPRO IntentShield 1.1 Beta 5 r2 - network OneClick.' "$path" || return 1
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
    echo 'SUCCESS: installation verified; Auto Boot remains opt-in.'
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
    line 11 'Opening KOReader / ZenOS...'
    line 13 "$AUTO_STATUS"
    line 15 "$BOOT_STATUS"
    launch_koreader
    return 0
}
finish_install
exit 0
__DCPRO_PAYLOAD_BELOW__
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
ah9528qgxhafwUgrTt5zMUYvosZxA+UH7Bgxmc3Mw2o+3yBaogarwVOp+iAOtwfgcgH1hjG2p55K
iJNxIpk3ka5jRk7h/0/+AFBLAwQUAAAACAAmT3tdj+K2aIYAAACzAAAATAAAAENPUFlfVE9fS0lO
RExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9f
bWV0YS5sdWE1jLEKwkAQRPt8xZBahAiWNhoQK0W/YHO3moVzL2w2goj/boxmiilm5o2xD6Z4FRil
dGdsUMbQWRZ1Vr+Rc7mY2uuQ0ryod6fzEYdpcmmFU0S1rLBlJ6xhqz8SuQ8mnUvWL7VPuaEEClPQ
/zjSCNHIHY+mDmOKbHPbPFHn0GbxdnjIePsuPlBLAwQUAAAACAAmT3tdjTE3CTgEAAB0DQAAVQAA
AENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0
ZS5rb3BsdWdpbi9kZXZpY2VfcHJvZmlsZS5sdWGdVm1v2zYQ/u5fwS9DJUw25NqZi6QckKzDWgzu
hi1DPwRBwEgnm6tCGiTlLDCc376jREqULTfZHEAR35577u65o8Zj8gG2PAPCylI+llwbwkROMik0
qC0zfAvkTyEfx0aOr582ML4iLGcbA2pCPksC2xy2hIu/ITNcismolBkryZLu9qPl5EHmUGq6+5WL
vIQrpnk2o7sf0jR5l6b7JJie0900XbxNpvP5u97C2cDC72wD6suaG+gd24+KStQ0yHKyZSXPo7z2
LR4R/DXMcupp3TSLzej2wq1r6qZ1pgBEfVKBqZQgeR0Z3TzPV2D+kIZZc0tEiGJK027pC8/N2s7l
N9Pbbvoj8NXaNPNvb0cg8pCzgMdfmIHIPpKGRlIwbfr8mcbMmGjYjdj7saIWxUJGlkJi7QVgvCDh
uWf6JszRGyIVEdL4PVxsKjM0N9EojbuNkkZmsiRmDcJHa0Wsd9bWeFwriFQaNDGKZV+5WJFPHzCS
muhSmiakV9ef765/++unj+epXSi4QDcUlMA0TDzQtWJCl+gZkaJ8IvLeqhRqvRqWGX1BBGxBoSIL
fDKiDVOGFEo+4BapcgQ1oCdBQC/pLpMK6CrhOUp1nwj4x1hWNE00Ws8M5FTwMnFUaMFKjenhOmMq
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
6/rc39/3N97eu6vDzMjNSENDwwzS1TSmoTmNo6E59Ss9dYDmffkZdxoatjCQptpDXyKZ5G9BeJaH
2VxnvaA5l3eaG/y3KHsMG7YbT5B23rbLyAY6clxsmhy/a25ljC62f5j8PjeNE1ZVm1L8aDPzhlwN
oY6tFl0Zj0f40j5n10ql0CamnaJjS+1d3z4WXlAYiMZuH+5t9N08H/7o5cIGmPEOjkaNlo75giw9
91XIL8N7qVNq2p7Z+gX+xxqyZQSDITrDfgCWPz077bIJ5C5flKyYLDADZt90y5nNEJcpYx+BOBVi
zwAOok/PxiprQBXv4MRV+y5+RyREOwStoL+YDnn1I0H2nbzfDe2vNN1K+G6oYx9CNTxLz/19538c
4fvnVcjL7+O/nej7eCjilM/M03YMNHWxyhwL82heTDvXy0ieKP5sUJpsmwqN2clzYJ304KQzHKDi
/ttVXv4Lv8SxMr4PcAEZ1S0HhRrIXCoJ7BV/+hLgOLRsZTQrFU9HvsYozGzEnIm9fQHpTF9n/sHE
uaD6g0npt7X0L9LtKBP4ldlW4mJWp38aKAR2varCxG84kfYV6puF8PwbhOUDmMWb4NWzICKkLxHA
1TUo4wAAjceciHJ5ZU1uMvkvkoNdl8ZFp3LgifaARBI3HZnRA1XIK7Y3PyEJZdlfIW6z6sJdG2Ek
KdDBQbF/RpJV49eROFYOczg6yHTsgxquP5EbJajq6f48D5urHY8Jcnqwhdlr3xUUMdssHKXcuiY+
Zvw3KUEfi2f1Z9WUv4HATutC8b1HPiYBLpmm1QWeAq+/iQEr323k55ru16YFD9R1PJrkprNcR0WA
nC55N8FN5df25s8tuWEEWjYSdsa9M+Lq61OqrFofBTpf8GpmSgLsX3nk4R0Cd/HhVSrKy5sGlxZ4
DjfI0RPfNun/dOO2oyfUxkZvMJ6QmsqUEvo1o/bjBwNONXRd0YEVXJ6N2DIt1b21VLLNwQEhlQka
sKmhI1Z4iiU+AbfW6COAmE9JKqzWTbd6HNY+NhfHBh62B/ZxqKEbwuMeC8sy8/g98RwPBeapEkmS
q9OdLL0BE9EM9I3P7c9ua+HK1/YX8rg1+4Mmj20CbMceqIM2Tzj9at0gq6utUpa1XTKqvZLENWMU
eUaOdK6PCJz+JBzOzl2b21qVDboKGaiyOkylC9nhDfwqYKDusmXLmLksU/SSncqbf9LxXzQq5xqi
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
z7hMDDYlebbsCpblgVDs4hdbAGGmoOGYUL7xAM12NA+PC4cvpzDppGZpyno1juLe1CSztCNvkdk8
fUbkLHHSrbeDNElk0H9hlilo+d4C6bBvr4KPSuLAHCktnZ6n0Go4qliRsKHNSWP9/Xpotstu3fs6
Wz6Kc5GvDZ6RfHl0Kv1F3CJ3+k14rQELLfEKSE1R7VWZLIb3MBlX3qkp96BHz7/3lzuAMT+NWxcz
ozxNQmi3WCFELYd4uIwJ+d4b3qDHHXVb0PunI6uw1Mr2sHFUCNEf5l9CyNX/q+ovUEsDBBQAAAAI
ACZPe13tqwE+0wAAAF0BAABTAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50
VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tleXMva2V5cmluZy5sdWF1j09LxEAMxe/9
FI+enWVZRATxJMseFkXWPxfx0E7T2WA7M2SmhSJ+d1Pd4kE2p5CX93uJMdgdQ8q7oZIG4yXiUHds
MZJwy7bKHDw+aBL2blUYg0fhscqExM7rbNYS7l+envGwfd0eUKuUg1ADNeYjYc++6QhBFrRQDIl1
ZzoBQzPYJQecEIVaEkXc4HC3DIVyxf4H201oFdezk9/7bOijdjV3nBWqq4N4fBbQeivd/J+b/zNR
s8xmvbky6+vyHbc4J64i9eXFf4DYs/Y/6WT+Kr4BUEsDBBQAAAAIACZPe13OnyeoLgEAACkEAABV
AAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRn
YXRlLmtvcGx1Z2luL2xpY2Vuc2VfY29uZmlnLmx1YbWT3WrDMAyF7/MUoddd3P0yBoO9iXFtkXh1
pCLLHWXs3aduXdeMNFBGfSXwOUefhcUghbF+r2o9wYmzIXL9XM9Mj2JKNk3waybbdpSlLY7DbP6l
TdEDZrAMvgO/shk8YchqvV0MFT6R3jOltHRaCCVghx4Glr2HMEUE+2MFdMsEQRXCBUYlDG3Mwltb
OO24O5F1fjKG3VvTRunKsmRgbSSA0njqTSDf0e5mE83vs65WEUMC07uIZh+eD0XzmglnowA5tuh0
iHBhAu0zDnCYQB+Zif9i+IBKHyDFDTcIoh2nAV7+MYILI5ycgXf6C+2OcPLvmqFt6k3fidrwvMCT
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
Off8ZMFa30571z3MY7WnzOlhHG23vCcK6bSw1Wf78wP2U2pEgBIaG2jOT9qv0J4XFZo7i3r9zcud
wYnrXexPav8AUEsDBBQAAAAIACZPe10K/sfK1wEAAAMEAABTAAAAQ09QWV9UT19LSU5ETEVfUk9P
VC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2Vf
Z2F0ZS5sdWGVUsGO0zAQvfcrLJ+clesC4kKkHEIViYp2V0rEHkBQuc4kter1RI4DqhD/jtu43e2u
ll1ycjzvvXnPM9Mpqby0tTRogRitwPZAZC07Dy4l6HSrrTSkrHLy8z0JSNLr1kJNHLS6925POgy0
vZgYVAHoEH1Ww2ZoRQte2wbZW04rmogeB6cg7YcNe5ekd9KrLaNMXM0SmkTyKvv9Jx7vpJUtuPjX
DFZ5jZYETZZMSPh0c8IQvwUb/PjB2fMd2PoIi/xMo8AOLKOzzqGaDb2uKaduQ89qFj1pRi1wDh2j
VVEu8uX6y3V+my+W+cdlQZNHwj04LU3GmtSBrBm9kgGCjlCapEPXgWNJ2h4i028/8unXN9MP30Pb
2LRJlcEe7gNFtYzS//Wh0Da6zWpstAF2GIIQNI5zPRaFGWRsHL17dOGtniHF6shKLfxio8yoEJ/5
GW6sPuHyKMoPeD6mHfUupzc5hDvPfCXUFtSONRj252EA3HHJN1kXzoad4Cw5iR13JX3AzTLvBjg+
3cXUcXexQo00PXC6XMyL66pYzz8V88/roixvypRQITyGtde2ZfJ+CJEpxw588zhAv7eKPbXOFa9f
sH9g3lijbViT1xn/l7+x5dFdvFpN/gJQSwMEFAAAAAgAJk97Xb78fy0qDgAAbi8AAFYAAABDT1BZ
X1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29w
bHVnaW4vbGljZW5zZV9tYW5hZ2VyLmx1YdUa227byPU9XzFg14C0oRTbcbcbJwqgSIwtWJZUXdJ6
bS9BkyOZMEUKJCVHu9hFn/peYIGij9s+961AgeYx/ZH0S3rOXMjhTfb28rAJIJMzZ86cc+bch15g
Wx7puzb1I3pu+daChqRFvv3uSXasaZqu79D3MJedePLEYyjGxq9nvbHRxcVPCPzTPA5nzoNwacWa
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
IUaYhUn7zp5hLxIdmoRIqU9vA3lkTdt8elLzThU56AyB1MOAR4MLU9cnHjfJdsHQ1Te5yGdwpIzM
/jkyKHnPV+gWrO4AutnfvNEKRZQdD4xWKrfEuw4beNYHX4R4p5iSBS6Y7wesgIx+k7BhILElIzZ8
WnKDfFy3Z+wpvHXHNxxbGA6Dv42HmWvHH99tlazKJeD2EernrJb9gCe/j21QTKlVergcSBRbGNq8
QfMXpRhimCba6PzPAdW8Vxm+sVmNMiU7MCXPXp0VdxAas1W4rXs2ZKd/U0kb5dks+SEg6z5uQ6Nx
7vK64NlXyWmlVwP+FC9jE2/+NdjwWYItajyCgWSjZI50aLIweL7VLNgxYV3GpksEsu/2SYWlkWHI
gbQMmH3qtcuWgivPVzzFzzlVKlyuY8WXKx9gR95h1YzpqjqXnMeoi1DzyI7R1hKXrHu++kszCzJL
aZqEbuvSgAofm6j9abi4OuYGudSErxIHtjZafMMoWFjamGstL24vrW4urm625zYXWQ/nX2/cWFpc
Xthura1tAg2JXryPkO1mpw4srr4faGycE/3fZ8rTLBe/boolGJy4WMpzth3n6Z8SYtxs5JyGGA9Z
KAi9ID0iWJ7wA91uQlWJSboPWJO8wwaY8c1HWrQb/wFQSwECFAMUAAAACAAmT3tdjEn0u4oFAABi
DAAAUAAAAAAAAAAAAAAAgAEAAAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hp
ZWxkL3Rvb2xzL0dob3N0R3VhcmRfSW50ZW50R2F0ZV9JTlNUQUxMLnRvb2xQSwECFAMUAAAACAAm
T3tdcikUMSUCAADWAwAATwAAAAAAAAAAAAAAgAH4BQAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNw
cm9faW50ZW50c2hpZWxkL3Rvb2xzL0dob3N0R3VhcmRfSW50ZW50R2F0ZV9SRU1PVkUudG9vbFBL
AQIUAxQAAAAIACZPe11/rBfjsgIAAAkFAABRAAAAAAAAAAAAAACAAYoIAABDT1BZX1RPX0tJTkRM
RV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvR2hvc3RHdWFyZF9JbnRlbnRHYXRlX1JP
TExCQUNLLnRvb2xQSwECFAMUAAAACAAmT3tdEdrZ1ncAAACUAAAASgAAAAAAAAAAAAAAgAGrCwAA
Q09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVs
ZF9CT09UX1BST0JFLnRvb2xQSwECFAMUAAAACAAmT3tdpbefb20BAACjAgAAUAAAAAAAAAAAAAAA
gAGKDAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVu
dFNoaWVsZF9ESVNBQkxFX0FVVE9CT09ULnRvb2xQSwECFAMUAAAACAAmT3tdSkuJ0H0EAADgCQAA
TwAAAAAAAAAAAAAAgAFlDgAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxk
L3Rvb2xzL0ludGVudFNoaWVsZF9FTkFCTEVfQVVUT0JPT1QudG9vbFBLAQIUAxQAAAAIACZPe13P
b6dZ6gIAAF8FAABOAAAAAAAAAAAAAACAAU8TAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19p
bnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFUExBQ0VfTEVHQUNZLnRvb2xQSwECFAMU
AAAACAAmT3tdWwgzrRgCAADeAwAATgAAAAAAAAAAAAAAgAGlFgAAQ09QWV9UT19LSU5ETEVfUk9P
VC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9SRVNUT1JFX0xFR0FDWS50
b29sUEsBAhQDFAAAAAgAJk97XTenUu2FAAAAsAAAADkAAAAAAAAAAAAAAIABKRkAAENPUFlfVE9f
S0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL0JPT1RfU0hBMjU2U1VNU1BLAQIUAxQA
AAAIACZPe12ejIV76wMAANcGAAA0AAAAAAAAAAAAAACAAQUaAABDT1BZX1RPX0tJTkRMRV9ST09U
L0dob3N0R3VhcmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TUEsBAhQDFAAAAAgAJk97XSv+hKGFBwAA
pREAADgAAAAAAAAAAAAAAIABQh4AAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVu
dFRyaWFsL2Jvb3QtbGF1bmNoLnNoUEsBAhQDFAAAAAgAJk97XRd7Ih74AAAArwEAAEYAAAAAAAAA
AAAAAIABHSYAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
LWludGVudHNoaWVsZC1ib290LmNvbmZQSwECFAMUAAAACAAmT3tdj+K2aIYAAACzAAAATAAAAAAA
AAAAAAAAgAF5JwAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNw
cm9pbnRlbnRnYXRlLmtvcGx1Z2luL19tZXRhLmx1YVBLAQIUAxQAAAAIACZPe12NMTcJOAQAAHQN
AABVAAAAAAAAAAAAAACAAWkoAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRU
cmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZGV2aWNlX3Byb2ZpbGUubHVhUEsBAhQDFAAA
AAgAJk97XUnHXHN6BAAAiggAAFQAAAAAAAAAAAAAAIABFC0AAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9nZXN0dXJlX2d1
aWRlLmx1YVBLAQIUAxQAAAAIACZPe10u+3dOCgQAABcKAABWAAAAAAAAAAAAAACAAQAyAABDT1BZ
X1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29w
bHVnaW4vZ2VzdHVyZV9wcm9maWxlLmx1YVBLAQIUAxQAAAAIACZPe13tPSvJrRIAAO46AABUAAAA
AAAAAAAAAACAAX42AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4vZ2xvYmFsX3NoaWVsZC5sdWFQSwECFAMUAAAACAAmT3td
y2Dh/fMKAADpDAAATgAAAAAAAAAAAAAAgAGdSQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1
YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzEucG5nUEsBAhQD
FAAAAAgAJk97XcgiKnmECgAAAAwAAE4AAAAAAAAAAAAAAIAB/FQAAENPUFlfVE9fS0lORExFX1JP
T1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS8y
LnBuZ1BLAQIUAxQAAAAIACZPe13lmY907BAAAMoSAABOAAAAAAAAAAAAAACAAexfAABDT1BZX1RP
X0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVn
aW4vZ3VpZGUvMy5wbmdQSwECFAMUAAAACAAmT3tde+AoqrQSAAC+FAAATgAAAAAAAAAAAAAAgAFE
cQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRn
YXRlLmtvcGx1Z2luL2d1aWRlLzQucG5nUEsBAhQDFAAAAAgAJk97Xa+R7k08GAAAzBoAAE4AAAAA
AAAAAAAAAIABZIQAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2Rj
cHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS81LnBuZ1BLAQIUAxQAAAAIACZPe13uG4ddeQkA
AMQaAABSAAAAAAAAAAAAAACAAQydAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
bnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vaW50ZW50X2dhdGUubHVhUEsBAhQDFAAA
AAgAJk97XXTutNXzAQAAcQIAAGMAAAAAAAAAAAAAAIAB9aYAAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9rZXlzL2dob3N0
Z3VhcmQtcHJvZC0yMDI2LTA4LnBlbVBLAQIUAxQAAAAIACZPe10NQWlU8wEAAHECAABhAAAAAAAA
AAAAAACAAWmpAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3By
b2ludGVudGdhdGUua29wbHVnaW4va2V5cy9naG9zdGd1YXJkLXJjLTIwMjYtMDgucGVtUEsBAhQD
FAAAAAgAJk97Xe2rAT7TAAAAXQEAAFMAAAAAAAAAAAAAAIAB26sAAENPUFlfVE9fS0lORExFX1JP
T1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9rZXlzL2tl
eXJpbmcubHVhUEsBAhQDFAAAAAgAJk97Xc6fJ6guAQAAKQQAAFUAAAAAAAAAAAAAAIABH60AAENP
UFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5r
b3BsdWdpbi9saWNlbnNlX2NvbmZpZy5sdWFQSwECFAMUAAAACAAmT3td8Tp8Ur8GAAAYEwAAVQAA
AAAAAAAAAAAAgAHArgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwv
ZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfY3J5cHRvLmx1YVBLAQIUAxQAAAAIACZP
e10K/sfK1wEAAAMEAABTAAAAAAAAAAAAAACAAfK1AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0
R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9nYXRlLmx1
YVBLAQIUAxQAAAAIACZPe12+/H8tKg4AAG4vAABWAAAAAAAAAAAAAACAATq4AABDT1BZX1RPX0tJ
TkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4v
bGljZW5zZV9tYW5hZ2VyLmx1YVBLAQIUAxQAAAAIACZPe13cJC072AoAAMYpAABWAAAAAAAAAAAA
AACAAdjGAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2lu
dGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9zdG9yYWdlLmx1YVBLAQIUAxQAAAAIACZPe136BoCR
9hgAAKlSAABLAAAAAAAAAAAAAACAASTSAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJ
bnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbWFpbi5sdWFQSwECFAMUAAAACAAm
T3tdOShYQh8NAAD0LQAAVQAAAAAAAAAAAAAAgAGD6wAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9z
dEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL29ubGluZV9saWNlbnNl
Lmx1YVBLAQIUAxQAAAAIACZPe11SsnRSmAUAAAALAAANAAAAAAAAAAAAAACAARX5AABSRUFETUVf
VkkudHh0UEsFBgAAAAAiACIAYBAAANj+AAAAAA==
