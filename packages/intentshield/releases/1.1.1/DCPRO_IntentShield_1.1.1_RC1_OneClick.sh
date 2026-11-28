#!/bin/sh
# DCPRO IntentShield 1.1.1 RC1 - network OneClick.
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
line 2 '1.1.1 RC1'
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
if [ "$MODEL" != 'Unsupported Kindle' ]; then
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
    grep -Fq '# DCPRO IntentShield 1.1.1 RC1 - network OneClick.' "$path" || return 1
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
AAAACAAmT3tdRfEBXIMAAACvAAAATAAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZElu
dGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9fbWV0YS5sdWE1jMEKwkAMRO/9itCz
CP0ATy2IJ6V+wXYT3cCaLWm2IOK/u652AjnMvBklyyrwaqBI3IPgAC36WROLkdjdGbW7mt5yjBsx
9JfxDKeKXANTROj25WDsuz+OtHjl2TjJt3GMaXIRnK/G8us4QWBBmqk8MVBySLql0xOG5ENiC3nl
MvtuPlBLAwQUAAAACAAmT3tdjTE3CTgEAAB0DQAAVQAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hv
c3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9kZXZpY2VfcHJvZmls
ZS5sdWGdVm1v2zYQ/u5fwS9DJUw25NqZi6QckKzDWgzuhi1DPwRBwEgnm6tCGiTlLDCc376jREqU
LTfZHEAR35577u65o8Zj8gG2PAPCylI+llwbwkROMik0qC0zfAvkTyEfx0aOr582ML4iLGcbA2pC
PksC2xy2hIu/ITNcismolBkryZLu9qPl5EHmUGq6+5WLvIQrpnk2o7sf0jR5l6b7JJie0900XbxN
pvP5u97C2cDC72wD6suaG+gd24+KStQ0yHKyZSXPo7z2LR4R/DXMcupp3TSLzej2wq1r6qZ1pgBE
fVKBqZQgeR0Z3TzPV2D+kIZZc0tEiGJK027pC8/N2s7lN9Pbbvoj8NXaNPNvb0cg8pCzgMdfmIHI
PpKGRlIwbfr8mcbMmGjYjdj7saIWxUJGlkJi7QVgvCDhuWf6JszRGyIVEdL4PVxsKjM0N9EojbuN
kkZmsiRmDcJHa0Wsd9bWeFwriFQaNDGKZV+5WJFPHzCSmuhSmiakV9ef765/++unj+epXSi4QDcU
lMA0TDzQtWJCl+gZkaJ8IvLeqhRqvRqWGX1BBGxBoSILfDKiDVOGFEo+4BapcgQ1oCdBQC/pLpMK
6CrhOUp1nwj4x1hWNE00Ws8M5FTwMnFUaMFKjenhOmMqdyMh1QMr3cBGma4m9l9yj0a+gtu2r822
Cb88V6DB2NhETVbsD20WE8uoWY0wo/VUw84NOo5uImTqpnp83VyPdW3SJylgVQDkkUnM0ybJUBwJ
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
+d4b3qDHHXVb0PunI6uw1Mr2sHFUCNEf5l9CyNX/q+ovUEsDBBQAAAAIACZPe13tqwE+0wAAAF0B
AABTAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRl
bnRnYXRlLmtvcGx1Z2luL2tleXMva2V5cmluZy5sdWF1j09LxEAMxe/9FI+enWVZRATxJMseFkXW
Pxfx0E7T2WA7M2SmhSJ+d1Pd4kE2p5CX93uJMdgdQ8q7oZIG4yXiUHdsMZJwy7bKHDw+aBL2blUY
g0fhscqExM7rbNYS7l+envGwfd0eUKuUg1ADNeYjYc++6QhBFrRQDIl1ZzoBQzPYJQecEIVaEkXc
4HC3DIVyxf4H201oFdezk9/7bOijdjV3nBWqq4N4fBbQeivd/J+b/zNRs8xmvbky6+vyHbc4J64i
9eXFf4DYs/Y/6WT+Kr4BUEsDBBQAAAAIACZPe13OnyeoLgEAACkEAABVAAAAQ09QWV9UT19LSU5E
TEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xp
Y2Vuc2VfY29uZmlnLmx1YbWT3WrDMAyF7/MUoddd3P0yBoO9iXFtkXh1pCLLHWXs3aduXdeMNFBG
fSXwOUefhcUghbF+r2o9wYmzIXL9XM9Mj2JKNk3waybbdpSlLY7DbP6lTdEDZrAMvgO/shk8Ychq
vV0MFT6R3jOltHRaCCVghx4Glr2HMEUE+2MFdMsEQRXCBUYlDG3MwltbOO24O5F1fjKG3VvTRunK
smRgbSSA0njqTSDf0e5mE83vs65WEUMC07uIZh+eD0XzmglnowA5tuh0iHBhAu0zDnCYQB+Zif9i
+IBKHyDFDTcIoh2nAV7+MYILI5ycgXf6C+2OcPLvmqFt6k3fidrwvMCThHmL3mZxAucEHtnGY1t2
g016WNw9nlgmlSB4sRJ7oCIqvh/VCYlLR6rrm3n1UX0CUEsDBBQAAAAIACZPe13xOnxSvwYAABgT
AABVAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRl
bnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfY3J5cHRvLmx1Ya1X60/jRhD/nr9iZXSSE0wgz+tx4kMC
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
a0kvZfyzCTsP4NNP4INS5aPShxZ0HmyWixOVj8moLRUr/+Ijll9WrMn2BRNeP+BsWN7vfFbOX4Wy
eStwdOaSUPe39zM9KtMb210ZXMfdGg2Y64jeiouFbnSP9s1LV1+Yt7D0GLXQaHWrtXbzpHXQax70
dqu9Qj3L2929VrPdOKkdHva0myBCz+1t09jNg/8e3W0f1qptHer/zBTJyqFGkWlVZ/FzfFV0Eemd
5uusYInQwkYvpjgVNEqx0VXAkeu/AVBLAQIUAxQAAAAIACZPe12SjrPAhwUAAF4MAABQAAAAAAAA
AAAAAACAAQAAAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMv
R2hvc3RHdWFyZF9JbnRlbnRHYXRlX0lOU1RBTEwudG9vbFBLAQIUAxQAAAAIACZPe11yKRQxJQIA
ANYDAABPAAAAAAAAAAAAAACAAfUFAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRz
aGllbGQvdG9vbHMvR2hvc3RHdWFyZF9JbnRlbnRHYXRlX1JFTU9WRS50b29sUEsBAhQDFAAAAAgA
Jk97XX+sF+OyAgAACQUAAFEAAAAAAAAAAAAAAIABhwgAAENPUFlfVE9fS0lORExFX1JPT1QvLmRj
cHJvX2ludGVudHNoaWVsZC90b29scy9HaG9zdEd1YXJkX0ludGVudEdhdGVfUk9MTEJBQ0sudG9v
bFBLAQIUAxQAAAAIACZPe10R2tnWdwAAAJQAAABKAAAAAAAAAAAAAACAAagLAABDT1BZX1RPX0tJ
TkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX0JPT1RfUFJP
QkUudG9vbFBLAQIUAxQAAAAIACZPe12lt59vbQEAAKMCAABQAAAAAAAAAAAAAACAAYcMAABDT1BZ
X1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX0RJ
U0FCTEVfQVVUT0JPT1QudG9vbFBLAQIUAxQAAAAIACZPe11LGlqNOQUAAKgLAABPAAAAAAAAAAAA
AACAAWIOAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50
ZW50U2hpZWxkX0VOQUJMRV9BVVRPQk9PVC50b29sUEsBAhQDFAAAAAgAJk97Xc9vp1nqAgAAXwUA
AE4AAAAAAAAAAAAAAIABCBQAAENPUFlfVE9fS0lORExFX1JPT1QvLmRjcHJvX2ludGVudHNoaWVs
ZC90b29scy9JbnRlbnRTaGllbGRfUkVQTEFDRV9MRUdBQ1kudG9vbFBLAQIUAxQAAAAIACZPe11b
CDOtGAIAAN4DAABOAAAAAAAAAAAAAACAAV4XAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19p
bnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFU1RPUkVfTEVHQUNZLnRvb2xQSwECFAMU
AAAACAAmT3tdpnBVC4QAAACwAAAAOQAAAAAAAAAAAAAAgAHiGQAAQ09QWV9UT19LSU5ETEVfUk9P
VC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvQk9PVF9TSEEyNTZTVU1TUEsBAhQDFAAAAAgAJk97Xb9b
GOnoAwAA1wYAADQAAAAAAAAAAAAAAIABvRoAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFy
ZEludGVudFRyaWFsL1NIQTI1NlNVTVNQSwECFAMUAAAACAAmT3td5obckxIKAADGGAAAOAAAAAAA
AAAAAAAAgAH3HgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvYm9v
dC1sYXVuY2guc2hQSwECFAMUAAAACAAmT3tdF3siHvgAAACvAQAARgAAAAAAAAAAAAAAgAFfKQAA
Q09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm8taW50ZW50c2hp
ZWxkLWJvb3QuY29uZlBLAQIUAxQAAAAIACZPe11F8QFcgwAAAK8AAABMAAAAAAAAAAAAAACAAbsq
AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdh
dGUua29wbHVnaW4vX21ldGEubHVhUEsBAhQDFAAAAAgAJk97XY0xNwk4BAAAdA0AAFUAAAAAAAAA
AAAAAIABqCsAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
aW50ZW50Z2F0ZS5rb3BsdWdpbi9kZXZpY2VfcHJvZmlsZS5sdWFQSwECFAMUAAAACAAmT3tdScdc
c3oEAACKCAAAVAAAAAAAAAAAAAAAgAFTMAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJk
SW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2dlc3R1cmVfZ3VpZGUubHVhUEsB
AhQDFAAAAAgAJk97XdN/vCuyBAAA+wsAAFYAAAAAAAAAAAAAAIABPzUAAENPUFlfVE9fS0lORExF
X1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9nZXN0
dXJlX3Byb2ZpbGUubHVhUEsBAhQDFAAAAAgAJk97Xbvbk6csFQAALkQAAFQAAAAAAAAAAAAAAIAB
ZToAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50
Z2F0ZS5rb3BsdWdpbi9nbG9iYWxfc2hpZWxkLmx1YVBLAQIUAxQAAAAIACZPe13LYOH98woAAOkM
AABOAAAAAAAAAAAAAACAAQNQAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRU
cmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ3VpZGUvMS5wbmdQSwECFAMUAAAACAAmT3td
yCIqeYQKAAAADAAATgAAAAAAAAAAAAAAgAFiWwAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1
YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2d1aWRlLzIucG5nUEsBAhQD
FAAAAAgAJk97XeWZj3TsEAAAyhIAAE4AAAAAAAAAAAAAAIABUmYAAENPUFlfVE9fS0lORExFX1JP
T1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9ndWlkZS8z
LnBuZ1BLAQIUAxQAAAAIACZPe1174CiqtBIAAL4UAABOAAAAAAAAAAAAAACAAap3AABDT1BZX1RP
X0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVn
aW4vZ3VpZGUvNC5wbmdQSwECFAMUAAAACAAmT3tdr5HuTTwYAADMGgAATgAAAAAAAAAAAAAAgAHK
igAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRn
YXRlLmtvcGx1Z2luL2d1aWRlLzUucG5nUEsBAhQDFAAAAAgAJk97Xe4bh115CQAAxBoAAFIAAAAA
AAAAAAAAAIABcqMAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2Rj
cHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9pbnRlbnRfZ2F0ZS5sdWFQSwECFAMUAAAACAAmT3tddO60
1fMBAABxAgAAYwAAAAAAAAAAAAAAgAFbrQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJk
SW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tleXMvZ2hvc3RndWFyZC1wcm9k
LTIwMjYtMDgucGVtUEsBAhQDFAAAAAgAJk97XQ1BaVTzAQAAcQIAAGEAAAAAAAAAAAAAAIABz68A
AENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0
ZS5rb3BsdWdpbi9rZXlzL2dob3N0Z3VhcmQtcmMtMjAyNi0wOC5wZW1QSwECFAMUAAAACAAmT3td
7asBPtMAAABdAQAAUwAAAAAAAAAAAAAAgAFBsgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1
YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tleXMva2V5cmluZy5sdWFQ
SwECFAMUAAAACAAmT3tdzp8nqC4BAAApBAAAVQAAAAAAAAAAAAAAgAGFswAAQ09QWV9UT19LSU5E
TEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xp
Y2Vuc2VfY29uZmlnLmx1YVBLAQIUAxQAAAAIACZPe13xOnxSvwYAABgTAABVAAAAAAAAAAAAAACA
ASa1AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVu
dGdhdGUua29wbHVnaW4vbGljZW5zZV9jcnlwdG8ubHVhUEsBAhQDFAAAAAgAJk97XQr+x8rXAQAA
AwQAAFMAAAAAAAAAAAAAAIABWLwAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVu
dFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9saWNlbnNlX2dhdGUubHVhUEsBAhQDFAAA
AAgAJk97Xb78fy0qDgAAbi8AAFYAAAAAAAAAAAAAAIABoL4AAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9saWNlbnNlX21h
bmFnZXIubHVhUEsBAhQDFAAAAAgAJk97XdwkLTvYCgAAxikAAFYAAAAAAAAAAAAAAIABPs0AAENP
UFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5r
b3BsdWdpbi9saWNlbnNlX3N0b3JhZ2UubHVhUEsBAhQDFAAAAAgAJk97XXLj/f90GQAA9VMAAEsA
AAAAAAAAAAAAAIABitgAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFs
L2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9tYWluLmx1YVBLAQIUAxQAAAAIACZPe105KFhCHw0A
APQtAABVAAAAAAAAAAAAAACAAWfyAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRl
bnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vb25saW5lX2xpY2Vuc2UubHVhUEsBAhQD
FAAAAAgAJk97XQxH9OmtBAAALAgAAA0AAAAAAAAAAAAAAIAB+f8AAFJFQURNRV9WSS50eHRQSwUG
AAAAACIAIgBgEAAA0QQBAAAA
