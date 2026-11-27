#!/bin/sh
# DCPRO IntentShield 1.1 Beta 1 - network OneClick.
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
line 2 '1.1 Beta 1 | Basic 2024'
line 3 '--------------------------------'
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
    grep -Fq '# DCPRO IntentShield 1.1 Beta 1 - network OneClick.' "$path" || return 1
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
    line 15 'Auto Boot: unchanged'
    launch_koreader
    return 0
}
finish_install
exit 0
__DCPRO_PAYLOAD_BELOW__
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
AHtWel3Pb6dZ6gIAAF8FAABOAAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hp
ZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9SRVBMQUNFX0xFR0FDWS50b29shVRdU9swEHz3r7iahAAd
2ylvbZrMkJIJDJR0DH0otJNRrHOsRpE8khygH/+9J9uBQjtt/BLrVre3e3feeZEshEpsEexAWinQ
St7DrXAFnM1SZBwNZFJb5AOQuGTZPZSyWgoFC5atqhKEBV05Kzi2ARsHFh1EWAXpbHY1TNbKJZUd
wPjocjIMO/4wmRbaumnFDD9VDpW7MoLJcADp5MMsvfoTNU+x1MbZpIFPmcMwWK+4MBCVQPD6HiXA
O8xgNNqeJFSPY1LGUi9DOBztvgpybSAHEpCURmfJTT96/eUgydZcCoUD4DoA+t1AZChvHsIX+PED
Mq2cUBXWsc2ws+cM9D73+/0e+OdtAz0cJRw3iaqk9Jfe7NfwjFmk+Cb0pAeyYl+FOzC1tTG9HewD
ZoWG3jtv82+u63Up0SG1IxfGup4XJxy8GtAfy7KAa4XBWTqsFa188ta2lW6yh9sDvCPTrNDKPsYe
lIrci80Ju3qIxrbwwnd3fYjXoba5dDwAV6DykW8UOUtbi9rigCrqrAZUc1MgwdQDrEmY1+/bjAnP
qBGi7uuS+hqvdBNJllIvmJzbQqDk3qqW6Xtr2GnTW2hm4rKGPfcKfgaz8+PhM8KlH6ylHyyifiAM
g1Yt3XhGdf5k9Jn0Nt0DW1gi3pL1PdmYqPygJ82yRI9MUWePkzx42f3UXXd51D3pvu9e7kedjud9
QQtDzOMnZgbrzbYaHwpKQzbl0Ovaz6rXoEew5WPWRS1ps5qxu3MhbfWxsGwh0XcNNDmkS0ejwCRc
UxcXWrt65wdQGrRoNgjeUw+kNaahX1pgigPVzuKgGRbcDtbk4mh8PplPT2aXV9OPR+nx/HpyMR9T
6HFOag3/RZOKf8RjyzbIw3qqdqBthmJOULW2YFzfgi9dZOi/R745UaOJt9otlsyweplIAkcrDPI4
qJsbPm3uWhMVOA2dcQznlFJZ9J+KXFAeg47RZ4LHcPFX9ko5XWUFAcLA3qss+AVQSwMEFAAAAAgA
e1Z6XVsIM60YAgAA3gMAAE4AAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGll
bGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFU1RPUkVfTEVHQUNZLnRvb2yNU1Fv2jAQfvevuKZVWZGC
2d62jElkjRgCFQl466rKOIZ4MXZlO5RO/fE7xylVtWpa8pDkvu/uvnznOz+jG6mpq4gTHlLRkOVi
sR7Rvfa0cRnk41UxSi5CkE4q4/ykYbacai+0X1vJVELOodCusQK0eISJMhum6MYYD5xpjQ/nmfWw
EVuDHCucN1bqHSixY/xpQLxpeAVdi+vpapzPi/vpzbq4Wa9+TIv59X2OSPI+YzJeFwmxe0i3L4Ti
5u8Kk/kiH8+Tf1HaJgQ1whakBvpgDae3w/TzXZ/yfamkFhmUhgBet5BarLVN4A6en4Eb7aVuRIsd
RhcfvIXez+Fw2INwf43UT99oKQ5UN0qFpC9XLZ0zJxA/JKFpXzXsl/R9K1gp7AC/+lcgeGWg910Z
JM4WyxaCrbTO9zIQR+nhY4YvjnFSGi1IjgI481g0zI4q5nwavU43jNfNw8Af/XtyOil5KyVmJ7TL
3IXR78LoU5SE/YKwN71v4whyumdSB+mdOZFFZstRa24di7djqE380dNcxBGPlZNGu1fsZLrcQtej
PqEDV4U2l5cBKlvoQTU7qR2GM/CV0AH5jchs+UZQBqjoos7QyWgb0vSJ1hY8w3VoIy81aclffcDz
MahNRN7+6v4QXfy/VBLnO2997tZDlBnEFVtVUqgSw8FVB6V0bKNEOYAFRtsl2zNb44EIi2ZFKnTE
e8Q9aU7+AFBLAwQUAAAACAB7VnpdN6dS7YUAAACwAAAAOQAAAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL0JPT1RfU0hBMjU2U1VNUxXN2w3DIAwAwP9OwQKJ/AAM44Cx
lUgRVE26f9Vb4ECgd9faBxH2UdFK0Uy9ay0Sk0ZzMWSL2bgRFJTuA7HJUBBJHEJf69mu9p167Pfx
ImglAaVKaDYkMqO7i5so11xIkQq4pMHJIuRoUs0RJANzTtxCGPr+rO2cj83nPk67xvY/dl3TXz9Q
SwMEFAAAAAgAe1Z6XeKhulmGAgAAUgQAADQAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
cmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TZZNdbls5DIXfu4q7gXQkkZSo1QT8dY1x7MBxH7r7Mkkx
mcG8XAi44MdDnkPUKdnFBi6MqZAMorulr05DsnVV7NiHjmhuQCjukTl63zDbouN4fomHfL/8lG/M
vAcq48Dc1GW1pd2Z3XOyC+lSa9LbSqCQJI2iKQYBtUjI4zhdbiqX57cf57j4B3Nw9DSGFcQsXW1t
IInwxKkqsUr8tL3EV+wOKMR9bATHuQRoHcf5+ojr4/kkj/ggzsE9OJgcd2PcSosbD5ZJxn3O0VoN
Mlqyd/C2J3QBgMkFpol+HH/Hr7e/Tj9ub4/TT7n70+v95k+jjfnU+PtrvHxDbi5rYIHmolV1LCU1
YmcSZ/M1SavVRl4rmJGzKzVBrDFHrv+3uNt/Gtjsw6CKmqkNqHEntSUce6JOqi7DpIeIaJm4s+2A
8pTKl56l6k+D+tzP19PHWvqqyuFlN7QoPvc1IUczyqY4UbqMYdi950TgjTjmiBrOlWDwPo7L2eL6
Fs92u+b5E7pplhOLdpY/DVblo5IzDQH2XNtgzIwYYKs31PTGUhrHMge3wPEv6P3X6+P2Cd3lNM09
slnsBiFNlcxHmvbus5aw1t6+p9cDW04bDik9B6sqfEH/ycR7IEzEs9cduC2oXLWySPpopRneVxs0
hetIxqh0kAPxcLSeFW79Qr7IVU5x/xQalLpmX0TaICugusi0gtHBYDkIyLa+UqduBjXCtdEhaL/H
fX5R3x63e2E/8yvU1We2Bh0ooY2SVHcHQxYrEXTL+tux1don7oiZdapq22r61o7jRc7Xz+Mitwqk
s7IjG5RSDqVcLmBKQmI0I81aD0fC3XHpBLJKk9WVH8ftejlf4/mPzg/ob1BLAwQUAAAACAB7Vnpd
K/6EoYUHAAClEQAAOAAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFs
L2Jvb3QtbGF1bmNoLnNotVh9U9s4Gv/fn+JpCjVJ13bITjtXsulMWALNQAkXYG/uKGUUW060sSWv
JZOmZb/7PZJsx4FyvZu7KzO1Lel5+z2vyssXwYzxQC6clzDhFIhSNM0UZDSHmRDqJ+ACciozsuLm
XSqRZYzPQS0oDFPyVXCIc5LSlciXviOpAq9wLoZXHwaa80Egzf+FzIP6RS/1gX7JRK5AH3Wmk8nV
IEi5wn3U5DqTiuBeStZg32Y0FjmFQqJeqAK+MgmpKLiikQ/n9B7Xw5wShSbY9UwwrnyHDbrOasES
CjfQ2mEt8BIF77pw24dIOID/bsCLcEurEEQiLFLKlWzBLbx6tbV3shBSnRQkj8YolaurnJGkPDdD
0UvDjQ129vbY6/12uw8yoTSDfScSnDr/tZiHB4SMKeg509HFZHo1eEJwN6UaUhlYyhNEo+Wky4jl
4GWav6FrNTidTU4G1Xqg/e0nYt5CXV+AFyMF7peiNXp7qxC8EH4pN9oWzLdv3vz81h5K7ysa8/Cz
nN4zUciWQ7/QEN6/L3d771/tOyhpr/0Nshz9FIO7K2FXfuKulhNpP7qvd//u7abebgS7Hw52Px7s
XrptzbnT6sOfTkxYoumRDbSmo+Pry9EBmD1rmz7zcXI0Gux82z/wslzM6J/O5Wg6Hp6hi1SuIXc/
5VriLwFuhxh6LELVgojeB7xIEm3RQRvD8SKnsY67tcTk8MSK0wikKPKQSh+uLw8Bo08yTARFvygd
mAQiRuYc/cJCiEmSzEi4BMGTte8c/+3ucnI9/XU06AO+/zY8ux4NnHBBw+VdyWevDd9MMCVkRpPB
zn4f7klS0MFOzyyXxyTasUHPQmfOoYdhnmPoeSMB7t7nh5vPXe+df9u+wcft60/+9nOveml3XKSU
aJ0rg8+G6LYTBGZRp6pXlJCUacO1wFKXMkxyqoqcQ9eqr12zsXfHmPN97d0tVg+A/nG1RfjXbhlm
L2GI3ElEZpjLFn1YMbWAUPA4YaHCohQIrEp5LUG7ggsFAhdyFkWUw2yNzqk84peGNEUP4I2//xe/
DGgdZOAeszxdEaw5lr1aEI5BRkJVnRU5kHTG5gXGeiXdNcwfW9/wuaV1MJKR/D4GxiGgKsRYpEqt
Sy6+wogyy42FunSxWLsh1wbELV3SUD8OW7FU7mFSLRA87bNeufQk0nXqJJI+cRvqVnByj1Bo7PFU
zGxJQ/GhSFPCke89JCwLvTlVOtcyaDDX2W5VM0pvq2eoyszaqLy3zQyl+Ch8v/fWt0frjHtqhIPa
WVy+IqMK7Rodo8IG8bKGWq5NjFtg2tGMSOoV8jsHaic864h61+SsTeAfe2GLKkTxm6xGfd1TxiNM
ABs87sP2N7idbXqbOLpEVaVJd1BvlTOlfXmAGfVHwTCysRljDmHd1NmE4U6URlfEcIQVHDNtzGPh
P2FtzY4rFH+dnB+Ppx/vxudXo/Oryw/j0dnRHXrAKlf3OnRvSNS/S9QAqK3T0y1N/y7KNW5PUgD2
jOWleTQyncTi+oTDc1mAqCBj2dfRx+J1ExvQSVAOIFsQpiRf0twkTb//RFKn/YNs06VFlzBbbrac
3XrEj0oS1guYBPph0hTfT6cDU2aiRswvhS6nqFu1gBFCuSmDm71HpUa7Oqp3fbnYDDB2K0uKOUMG
Xyl2P38p7HeQEsb9pCDPHY9CzHNmppY5QrghnCdiRpI7uWA0iUoOj/xeZvrptNWs2R+LRLEMwTqd
TI2yaDmOkkli3CLdmhyh2YmcEjODV5l0dlYwWXfS7faGF50H8/yrfr4rv9/p7zb0+9qVVvIhkdj1
e91eD1upHt5wxKEx+2L8aCKH0chFCuOwm60i9S+7T7nVZIMzJqWbJtMYO9DCKrJ+Q0OOx6OjQS2o
7J9mwVLqmc/080cwVuj9BP+gfHKpw9EOl5fGI5AyKbHxuk6jETDOVKgS2K5sll812TdC3HUqAtxS
2EDr60Q9xvyBA4kmC/KCcy1uw3Bz+HcxM9hUZ6z9Fzgano1PPlzdTU7xYhCh0XoqNG5HWw3+eqEF
LwZgpsTGqN1tbA/MfaiJTcGXHIdBw9V1moVwdD48PBttl7RD3NgO/2ePnpxNDnXkNWSZMSbDyw6i
69r5nFYsjsaXPxD3/OmT4dVoS5DuFTkN9ci0LouX62hmA1u17aiM7TDAHU6TIEevi9RcHu6+Oz+X
6WQV0i3MfejcvCBePPSOccL0buvMMQCPj7aCo8oTe41pBSrNbLXwbLmwlcEz7H3BQ9ra2EISXafW
1aUWwVMLbIFajItj/Qm7p/oyiaP59RgUSykogTdNDGUKJSVGNNYMsXqMibRHzTG89ZqLXq/7nwXB
/82HIUEckgTtjYpc39UjmpD1/yrPuMCexedYUetM063FDrAmOm7sxSFMo4Rx2rxo6wkpLnXFNokz
e0HtlcbeydxP3W7XTP3mlvnsfFTNRSagOtgWfmeqUzYl/Oo8dNxml3LrEKu7gf5poYoP7cfSlCrc
TCPQBcQ9IwUPF7oeSH3F2PQTzyOSZH2NxwYc/fMIFsOorKRNl5g2jjGb1yxcey0uf4ExJNu91Ypw
/glQSwMEFAAAAAgAe1Z6XRd7Ih74AAAArwEAAEYAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0
R3VhcmRJbnRlbnRUcmlhbC9kY3Byby1pbnRlbnRzaGllbGQtYm9vdC5jb25mlZDBbsIwEETv+Ypp
ihCoCoYjRT21FeqJqvRUxMHEm9qqY0f2hqQSH1+T9AfwxbMe+83I93jtGwqmJsfSPuKcdPULWXIr
LSLLwG0DOicb3iHN38SoTKg7GWiRKYplMA2bZOYvz+8fO7w5Trf32pBV6Q0VUXvGF7ndHla2rtQU
8mxAX5GDIIUqyJo6H36ykZghLfO0HPZOG0s4IJ+YHIVlrJc4YjpNR3coKojasWij2GofedvKoMYW
n8FIK07eczFGL6LGcQPlB+wYMZnNzMNqPt8gWqIGq8FTqfogDrcH4HIB9YYxtqeeSoiTcSKZN5Gu
Y0ZO4f9P/gBQSwMEFAAAAAgAe1Z6XfgYYViEAAAAsAAAAEwAAABDT1BZX1RPX0tJTkRMRV9ST09U
L0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vX21ldGEubHVh
NYzBCgIxDETv+xVhzyL0A7zognhS9AuybbSBmi7ZVBDx363VncMcZt6MkhUVeHVQJXgn2EAf/KSZ
xUjshkb9qrXXktJCDLvT+QiHhlwiUwrg1g62ZAjuzweavfJknOU72ac8YgL0LZh/I5QALIEmqiYG
ShhIl3Z8wpB9zGyxPLjevrsPUEsDBBQAAAAIAHtWel2lHOgaBhEAAOk1AABUAAAAQ09QWV9UT19L
SU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2lu
L2dsb2JhbF9zaGllbGQubHVhrVptb9s4Ev7eX6EvgaSuotjdZrtIqgJu4qZGnbiwnRZ7uwtBtihb
G1ny6cVOrmh/+83wTaQku+3hitaVyCE5HM7LM0OdnhqjtCRpOVvHJAmNvtszVkm2CBIjWJZxlhqr
oCSucZcZZBeSnRGn/xDacbbKg4X7LMmWQHs/MjwjJ/+u4pxYZhWfVfEmSIMVyU2bk1yTXbwkKllI
WyTBcAdsNKYh2CYpbki2aRCsoImU+ZOkmccb0qApoUn2v71u9C7iMJa9SVSo3Um8KM7g5yHLSRCS
/BT6JW2eZaUXkkW1clekjNMos/qOOTNtt8iqfEkuimphvbAvNkG5XFum5T4/s+utgFS9MIvihFg4
keuaMT0Hn8o7qQJJOgYhpUWTOmGtbfKZ92VFUq/n4PntiBcFSUEcTu7xyb6KQxnNPPNsk5ZnVXEG
L4O346E/upsP7+Y3g/nQ5GSD+/mkphveKWSz96Ph+Nq/GU/eDsaCfjr8OJnO6xE366wob6ogD/0p
2WZ5WZwxrUMxiEFRlTKNI49xURbW1oaDKKs8xVNxg7LM40VVEuz45qVxYpA0bA4tljkh6eSDZT8z
4A/rLTymey7rpT18Zov3bLKQJJ5nfojTMCFvgyJevjSNLDcO95+bthGkoVGw3wvQgWlWBsjGLVBb
tuf16q7PcViusa3fe/Wibn5P4tW6pO0vX/7+rGNHIAiibqb0iIsKTZviyCiftsQqYQIzrTYLsDej
XJNU7K980yd9th6o4dqNkizLgRy3pjY875PfbCpQMS2bhq0ZOAuvzNj8VukWZInjS7fc+fBsO0pf
pXbii32J0wWUhYXGW4CL/rLAVenK+E9ue3aRZCsriVO+eZijIEnkogmorGUPzs7bwlNiyX53n8cl
ceS7g9OAyfyVmoybNCthILKJTzs2HyWHRf0ogDGhV+YVOcRbUWZbC1xCkaXOAyFbPydFteGs0onQ
BMXDL/1L1qhaJG/awsxxukJ95i1o0MorrKS8gWmU+CpkgvwrDCg7YQ1sLfVg2aSgQDkjvh9dVGmx
XJOwAudS99qXCqk0N3WSTZbGZXZ4Gt4vJuKvnVPtgwdycB7sFJPgc/cMebDdwp5Qze5H7jpAOx2l
26qkYcXzNCq+VJuMUmV5vIrToF5EHaschqBTD6ShpPhKNdkc3l07pgvHWYAfS1dce2xQSycP9h50
sWML9ti0zNIStKWQ7aIBOxeg+g8k9FekAEMiNRHvQBoWvOsu/g5ybBpLlFTFujaWDoplkhVEo5DP
8iwaBoLsksdSc8OoyXC84PXm2XYDcvgUF/EiIeAaoc2yVZ0GWs1XwDKOeuw8AnvbYPkAKAPsFsJz
+KcJR1ScsVjN/6ti8+9LoGSqkbtxWpRBupT+U7SH2RLsBQAIviKrngWNcQCHh44it3W/mm2dXHKj
NKIqNGQRxsWWQoCdQ4dRtpwHiCS6a+OuQLglxWNoSzc1PwkKxvTOLYtT2fT6vId/mmo4+zD6CApX
Ej+JN3GJDrExrzisB/BgX7423BRtvuQ0qo+jQ+F0Uzj1ebx8sIQA+LmqHAP5Nw9+cKfq7N/Y9D8q
AGmZig+VHTI6kDzn8aGDo5oyzfZOTnfT0F2FeY5LACbZkkeJN1jLHvewpQrzzWMn3XkCfA1/CR5o
RcKOY9B2iAfq4fkqgQStW335pd8axxYcXM1Hkzt0Pqhz6BzgESfjj9Il7dzHvt1ufOrbLVHgTAA5
Pg5uhgxwaAS1WEPv7TV4mHh7DXia8jmKbuM8Bzwd3o/GwVNWlbBE+PiaYSVzDz6NAi8T/COoJyzC
mrC3jx2n/dZaaMZU1u4uJntm0PU7mPyO5ACVsQ225Ge5PJbQOw1bImcmjeMvWICgscGiv6Dge8u8
ycrsE0w9JYnphA3xEIi4tYhuh3f3EpMdm3O2zva3JK3Mo9PNhuPh1fyAzE9PjSHsPQO8lRosnQCJ
wzGsIVT9ByMIgOEyByNzqPYGxnb9BFAW7T3Yuq35wJ4LEE57+yzwmA5kGhBiYKzpbLPCw/wMKb48
eqhLzpOH2uPsIRlZe72vDmIJDxM0FyzFsr8e3+nVdDIeH9jpD3JW7OMt6eKtx3jr1bzBbP6P7CEU
igzt4ZNQ2xRymjXTW0j+4BHoWJzxKMwOFgWq+ZP9XRkoukhEhOA6zmFrw5+8G9yP544IMprtgu+z
L1aYhpp//pX/lf4Npm2AfjEvwlCsKUYC7q0SsDjJAl2+EcsAnjCZEy1cq65aOHWEqhjOjsYuCbeV
XTG2VjRbxOcjMWrb7bMxf8m23zwBoBVYTNE1Zp0u6gsmYw5mXg7FyfZBUC5wtwLKcV5lP12oRWcX
sihnWedRkMZB6qYkTwC0IG/UGnZBUumStqxA5JXWAp9A3PD/rzYNQNj5q+x8+Yr3nv8qHl6Kh1e2
bR/htfRo3imzpVIEvGXroBZB6INadJySALSeeOAhisfmisNtPJKLiJDQKh0qIx0W0QIHR7a6MwB3
NyWbIAZ2aPEK+kFJQ1I8pUvHWCYkyA0BqniQ5LGBlneMCLDz2pDI+iCo6NaBH9EkZqHXw9kfd1cA
/ArCyju1rISh0f8jkLHvYInNiLdBnBcWyMg2wkznTOYG2psS/oXkRNdr77yNBJmLcGFNcFCWeTW5
mwNQcE5C56Sgv/DX7Uf0x3QQLsAPT3nBk1U5rXTA4zaDSIOd4aNDXZytOTFgZgecbMDHINjnSPWx
xx+exMNjX7T02y6facxa86WP9hvvxXPdu3YMgtBfNnzwG+/X5/pM2jiMosUy2BKhKIVR7jOYDrH5
FmIE6hMLowWeVUKiEtMZ48X5CcZehgn1aIpSAEbqQozKzLmUQe+19+K336VE2NsReFXEKxaH3vS+
B5CkCrPik3hzcQrwlPArk4g3dW9ZNFIL3vra+71X5xet9b5jRTSTyCtyMJFo/ulOLNSEwqMJRdM3
EXqOpt1YWy3AbIK0ChI/iyKt4qNbqPqnCy3W/uELPRL8ccBCUW5fVVcwnF0NPg79wfTW7F6hE/5r
VR/lTNfKhptZpsMSWw7REZhw6NiJuaRy5t0qqrmP1lIM5B6fGINHfngSTPAF5LObKEh6yVYZLshL
qyDg6MLCCaoy0wpxQj06ckhx1Bodxg1/G4caJSufm7xubiANGv02z1awVmE2Aievs4fOfv0kiu3u
ck1AcXFNLZYL2iPrXRgqnoM5tSLt8YS0Y1YQerBAtAXUcap4ZX4V0wQ0vPodY4GMVnWx2Kw2QkRY
AQ8kp6hwEP5TFeX7LHuwv3mmOChTjuyouB0klPC+m0IgaL23Y8vaNj9MpiwnH3wctY4uS0JP25sf
LuGYfZZIYdz24RgCWeoDeqrZ8L+b7VORUspXAWTpbZpPdVVRbbzT2DxANmEduSVBJ1ETslsVtaQW
eXHmZuBkeR8k72egMFnhhsCuZZ78cbI5Cf2T9ye3J3gx5Zr8ogaRNyQDgVIQj7qkh9WvKg12gNFR
cUwd29EKYHTZKp2r/vVYIZzFgKYbVkd3eWy1si3mq03fU5/VFbib8Pj/YjKAp73LBrASDRx1yndR
dhHvtCzzc4iwUc9vlq6UMtF8MJ076t1s3+2fLkgZ9B12hg67lFIdhHpbRSs5AqdpVFwClECVlk6j
i9Vu53u0kpokTVSumtDFAfdQB3HfIbtWdWmmueyOUt7MFYmoM8MJLpvp8UzNjYG2lRbDEH6NY0K3
mvu2UvDLxnapUmnAXb8N6PByAuhIGm1E+45BimfjEK0EICVDq9ToCAmWyEpmnNhI+OI5NGepqIdw
qUiNlk9okh2VR94kOKz5EEQHL0/4FhQn1UJ32nVQd524o6hAq8ZinoMF4R8p03bw/k2/HxI1jCP1
Cc6/rFB0gclO0fLd6diAuYjWIuKSP053QRKHP7tO4zLqyI1p+xLo2DUp544O4vLR03+NEazV8Qu9
UWq9cLTLwYZSfY+Sbop6rzcKIuWXlHpmQJMCXV8U3nEEZNeHJCo2cdngSWDNetU6oivQsgVUqwI9
vaVcEPMm1Z104VU14jV9cp3JidgmIhPfJF/DdGroyWE503Z566qOoVP5YqjdhbuzdEoZ6N4P1WV9
Q8izqMTUC2J6Df5pAL2W3ULjyh6lN5Ac6xURHREcySnlJKqu1I00LreSSsGB6ldUqWEO0mMi/o7u
nztyrVrx8d/pqYFSMAZ48lgOM1ICmRNg9AjvtA1q/SJfMKI820BjUS2XkIFEVWKEADjxCtTFmeZr
wnildQrIRAmWvDAO5090M9sMZnrC1CyOYpg/Z0U0OCW8J8BPWHbEbX6Hgmc4hpi6KVaMd3jwZEjF
1o5KM/0Equ/0z3s9FbaCC4q4C+L41anxK1UWvtUapkrQ/UC3EOla0LzgM6IL+g2IpSDh05PN6Ulo
nLy/OLm9QDSMHDrAuMM/DIku6EU3U0X9fBTdR/YGSZLtiTBn4faYeuCnUnanzmiaXPsbvV2akdyb
1q1E/8anTiopX5V/Kea6Z+FyhbkFralDSuM+ZNukgshuHhzb/Njr5v1kNr+5H0yv/X8N7/y3kwlW
EjpkM0N7+MRUK7RaqFGXnwy0h1PvRpJGLeFHkmtmMnQ6obrmeHQ1vJsN/enw3f1seN3KresYpi8N
RvUuzovyFNwBYYDaoN+AGS96L14aCMov6Cob6ENVfML6QEmWED9TeMHCbmAssgoP1qBJpKvsCcd7
xz40002HehwSOiEMixM1lNMe6mMcnJOe6W/0iqDnoEywUROSdpvE/D9ug84jMPEhyNHy7ML/SnHT
FMYfTqeTqSZqvoGD4j4wM+0Tk/M5+F2H2KzJMiN/cnf5djAbXeHx+G+H84H/W292iaYJZz+7vx36
k3fvWFWsHqF135nsQoVvoktjmPxtW/MCnC+WeXb6Du7i26ahh0nlI4ifsZlGFO0ySf37ilZobk+k
JINBWZLNtiyoTmEBvmFhVIZ42+GPR7ej+aVRwbmK2tmG3m63wCpY13XGbplozpEan+PTdzH9iIIh
BDCelJT7LH8w2Bc5qvVADxgF/HJL4EV7B7/t5aPO6m+RFZnTgbKgBG9uXFxlaQpmC8rZrivJTd4N
558n0w/+4OPIv78bfBqMxugjf2izjOclcLwUS3G+GwzgjjR2lzUUl0MbjH0ejOb+59G70cGFI1i4
KqXXkLKKovgM23UJRYp8sNfNq3SUzqrFxzxD6NFdmqOUcVGTXWcpacuzjjxSeaji/IRU20m4pqTe
QcXll2W1p8KFqaUbnLD+cE4d3QAxYHxckF3ScTpSW35tA5YrHbgTMMt2GCyTcQ2J1Niu8YpuajwX
EFCv3NDJsbhj8Jm1bt5G+zu8WbOZMWVLONQMH+LQQRR4xOIbZGiGltder6mhYDfDKRO1/w6OuOFT
cZoDF8nC3XnwTzkGYDApvJ6q48LhYlfH52diom/eIeepGCqCCzwqUGH1qJvqjarQKmDwwe0rsqY4
Pk7GYxYnces0hNSl6gUB+ACaT+MvVZ3GTQtnHtwofgmMqyHzDyKHAK1Eh7Gs8hw/b1wGwJZB0XFe
tC5ZFO5xy23Wmbjpb+ODMxjGOr1X541TZ+Y1nny+5N9A8ZSjANumlSv9xgf/6IlTH40j6dp25w50
fVEvzugnA/Rc6CVOQEUSRCALOK04CY11UBhRnMYFrH3JJQihHGJQDM6D3p/C+ZSV8rlAZ5YrUvNG
7K7RVldgVq+6Dguh+UmOmkX/3zCFaKDjBRPd1tJBV9c0miWdDp/YNb4GfLUtahVgOUjgKQp7D34u
1QFQ2riU1oWPfv60CZ4WRJd0zb1q7odlxKlqCbXRbvt8/rdqCv7jfMye/RdQSwMEFAAAAAgAe1Z6
Xe4bh115CQAAxBoAAFIAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlh
bC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vaW50ZW50X2dhdGUubHVhnRn9b9pI9vf+FSOdVoHG
uNB2r7stg0RTmnKXQi6hvT2tVmiwh+Ctsb2egeCNsn/7vXkzY3uMSU+HFDJf73Pe59DrkctNKuTl
juUhmSaSJ/KSSU6u2Ir0/QHp9Ui6XsdRwl+IDQvTe5LlqUxlkXGPJCkJ+T4KOJm+mPvP4Ow0yXby
LZHRlgvJthmJErKNgjwVPEiTUHjkKkp2B/J5QRaAovee8D2QJJ0MmOix8PedkFu1EKRpHkYJsCK6
iHm+k4g6SLdZzCUPYZRIFkiy53AykIKkSVz4ZJaSOyC+yzkJI5ExGWyQ08nX6fzi8mb83n8WpwGL
CcpJycPjOxz6y2WUhPwAS2pqDq13SSCjNFG4ZOfgFV2Sc0AOYjG58cUfOaw+P5wXz2GHJ2ETbB0l
keSdfQmmNAdTSs+S3XbF8zPCkpDsKd3jALGylYAjQxxvdne8DXGUiCjkncxbdZ8R+Bj0GWJZ4Xfm
H0Z05R/6djZUs4GZFWqvsHuF2isGzxSlkgaqJeH3nXtv462ZkJoUE4KD2Ea0+y6iMLONnt2PNOLN
qK9hNPcCvjhFubZRotB2Xwz6b17WJRAcLEAyyVYx7zzcUzhEN56GxG9PxKkU9OERB7TvrXO25fA/
Bg6XsJNEsYcY1WcFlL/xkK5ZLLgXbFgc8+SO4yElEsUvKvMdf/SUwN1jHbzNOXDV0ZIIHq99y8K7
akr7ZlJjw6w4VBE9ugo4W6jsWG3mROyyLI64IPtIRCC7R5Q5ZupMIuNCYeKBsvskTXopGH3MsixK
7ohk+R2XAr3kwlIikSCMCNiPeW8nOMl4vo2EAJGUN0jYDGIWbcG7yQZ8/56Bv7Cd3ACxKGBKdL+h
BJZvO6UkCsl9mzmoZbx6NPTyvDJ4vNKzurWU2z4/ZBFoueugPNoeAXaEP9rpwc6Q/tjHj0ayTnOy
9MAXIAZFGYty0Xmo4CA85bKyB19xJDaPXRKmpe0YNlCSVbsEyr26jYVBY6FonigGRs4aEYVoRLXX
KJBqfBgMKZrRvd20Cxt7oj8sHVvBDpEEUlDGVvkf81b0eyqoXwBTxDGCgC6RE2YmTHGB8QN3CrVT
9GseUtn8A9KhzNP46coDSwKPhBvzzO3Ro/t8fNYS87I0SmRHofeEF2hi0RrN2Zqf8A+OsoVfdLtE
mbWNL1YjAAiHhygADEZGxTgr7HIxMopGDIEfJXsWRyGGi3dNjJrbjD4cKCD0CvguHutMBqDiXEiL
DCc0ewdDFTP0CGUUdHACe0gxEUEw72koIATR206KUikhRGBFp7SzErUdnA+QHgRjqv+dh2phyw5C
8sxEaXbolEte2K14La3rOFqahNwJPCkwRtdTQLjLMbpQKYBpNI3absIltVpCP0dqOES5rcw9cwik
t5KXS5CI4e769bQjcxbdbaSR0+QmoPVCLzTPh4dTTBzTP4ItvgNbY7SChdA9OUCIjlTxo0xeAcUs
4W8JOAaci+6gGIohlEl+l0eygAjIg28CRItgHzIBlD41LjCpoemuS/0ZxY/oYKCCpLM4HGDorIIS
8qvtZER/ckuT8NAd0Zev+8917lM52QF0D756Xs0L7Zv2PiDG+T83iRpjG9I3L5sEtGw5ZyJNrJ2X
PmmdXG3Ss+ns6/hq+mF5O/nXl8nsYnKm7RVqAIQx+dOFmX+d3FyNr6+ns8vlxXy2GF8sHDDtwoLz
ZInXXpsXLqbxL9Pb5Wy+WE5+ub6aXkwXy8UnWGlD2mlcgTZNwIz1liJTXtzgJWY3l9SHLzfjxXQ+
awior2742j38cfLv5Yfp7WI6u1gsr+fT2eLWlZDLIVCp6d2Fv/00v1koDNdX44vJ58nMlcXe67Dv
v/mpcR83N5PLL1fjm+X1ePGpway58tHPfz9JGSAvJ8uPN+PPk+U/vny+rjDYI6Whn30c3y5A15+B
0vT91WR5u7iZ/3NypnQJdrEArtt23Tir2gzQOqR7avDTJ2ABc3nqBPV6FoYyS9ejdYIb6ubN0sA3
bhxXvRA0OqqAK1shUHz6jROMpjBlawkFJUARyLSE6dC8ZYVqmcRuC8Wh9Ov4xklRQ8ak5NtM2sMC
Tr8jmJaBaCxSKBw5y4WDpKXMLb1aSVup03g5sjqCvO9jMaArRjFUC6YCKBHY0GA6HhM9oW7RSLru
poqxak8XG+hAlartHZvU+qA7Bx0n1VB3FOoLUhdkKM/cqv7n1YyiGlatRin/UskMMftPqHLU0CuT
nh14KtHBn9fIyV6ZquzAs/m4SsMlwdN5qiVR6qxYAz6ZqDqnUmoFDHcUR0Ekl4oDHRG9cq2wawXo
T7Io4eES+vsINRD40I2ES7tRoTz0G/zYBF+0bxTeYUBbUrNXtC0Xjy2FyprzsANKhwIf7jbkHiSS
HW+tK6VwykqAcOYK2lnQmLqu6ypDs72kaQ1te+oUlA+PjrWqyFprLK2vOGsYLL+Dv0TotKlSWCIg
FDVdh5KH0lf/E9oa24qCCii3/5ktP9zMr68nH96qtxcALpKAbHjOHYkMGqc+r7Dk/I8dRILS2CA9
3QMcNrEvDMpVQdT7lYO19EOjqZG7agNMJZwbuep6R5W8cm9RxWRUz+s37obZxKvXDQQOR68G5fiH
wV+0//9o1SFSvTkg0qbd1G1HfUwRTKuXi1/L4W91sZTBW7W4jxt1CCoc7KU6fnxCHSPaP96seLNt
lfCDv5zkUUrsB7aPBH+Fk4jV05HHvO3okGMmJq72Pexv+mUUrcWw+sfUgwbYsmP+e07E0mce21jc
MDAhfX3Otil0kGdKe4N2VWBDGhj1+4GPr0PGFlzkRwbBbYJ7Cl+9dz3GUJvbukzf6itlvGb8uvWG
y4OG1EHfjq7OoAe20wbJGn9tvDex2jxj+Ne4baJpF+p711KX2YyN7EehsH8cyf1m9XA+aLhckO4S
SasGR79ICfUgpd+jKv9S707OjWlY/D4fYEQ8dul0J2nN5xV6rF1OUnDENzwqpzu60SduBRgaDewT
hvWbk+rXIukbaEdqTnWe6q5M2+gfMDqYSaEnhhPXR0/yoz6QWm7MwfrvDEQ9geKvG0Ea93RPudpJ
ZITvobpMAq6eSyP8lcQ/hfpWRSmyhYpxl6vn2RSLdazIV6ncEHYAUhu252QFspF0JXi+56qCBVEi
YX/WaMeP7ZLRkSmka+1n433spAIQi358Rjiwo1//Bl/ng9/QnFtecDAEOdmx+akcraq3658nI05t
bHIZsNNasus6zszwh5r/AlBLAwQUAAAACAB7VnpddO601fMBAABxAgAAYwAAAENPUFlfVE9fS0lO
RExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9r
ZXlzL2dob3N0Z3VhcmQtcHJvZC0yMDI2LTA4LnBlbWWSuZaiQABFc76ic08fNgEJJiiwEJTVYinJ
WISCEhEQEb9+uiedG71zX3q/v3/Q4MFyv/xIsy396wQvv+6bcSxL61vgajUdCG0O6sJpIIAGAJ4O
Ljvw+zf16WdDwKfN+3M97ha1rOIETW8R+AwN+we5z4I1mWp8yfRuOgxXHWyrquOXbC3lqdPlQqRN
nCRmOOfiKlhliMSGvK6ASB7jipuAgvK1qdhjr1y49/3ZwRLVTc/CrevI+yXtW9x85ts9IsCH/Tgt
4iwKXv+wC3ZJmGkQcqUzWx6zd2mVduGgVXU7yRWNo4OxwemyIVP6IKUfoVbH+eeNA3ka0eX0Mqbc
sxkO9IuRyhx6ousFkAFHPJmpTAlxEB5yfFAKa1j9Unj7w8MOm9oWR7EqZZlH5otzEVOnfI3ROzmG
uJHOTrf0qu7Mrcs9lJEOHIRNwtK0goIoX4cOmkc7gGoF58wDgoRJwUQ3qwl3yZbalE2yUy7d/LHL
rmsZUDWlXlnSsS6CzvJr9YSesxLvb/qQlcveqM+bHbcwWVUYYnKIxPwYe/InwfO5HtNTl2J7RbGo
3wG75TUgeaZUKVh1pKR4EPulsqmCrVTkGTkYrKfKhbsOOSQbd5WU8UZ7R5+9S+W53ASv87pg0+4r
xQS1owEA/zD/EoLu/r+q/gJQSwMEFAAAAAgAe1Z6XQ1BaVTzAQAAcQIAAGEAAABDT1BZX1RPX0tJ
TkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4v
a2V5cy9naG9zdGd1YXJkLXJjLTIwMjYtMDgucGVtZZK5lqJAAEVzvqJzTx+glC2YoIACC2QpFgEz
ZKekkUVs/frpnnRu9M596f38/EFFJnY//Fg9Ye3DRtmv+2QcjNWxh67a0Kmlnak8ORUSZEDoaTCT
4e/fNfbPRnDUXe6YPbvhAHOxLPKv7mAwUSIunnf3g1Uz9NOJG1salcXVI1PbUcJJfIXP/XLzJsgF
ANTDfNQ6+7zYuO7fmqEemaCPOVnzkc5N48M7T5mWn5v3ZSHmSxlvS/XCLVdpOwe4sbGqqV+MQV/v
fH+4yjoW6coEI54C1UQ7CnrH+hry1LDzWW6zqI/q7G77SgXC1mwMpRThtu2IjkOnOjzf5sG6zSxg
zmuydaYb47RnswkLh3Fv+zehQVHKSoGVKs+4TAw2JXm27AqW5YFQ7OIXWwBhpqDhmFC+8QDNdjQP
jwuHL6cw6aRmacp6NY7i3tQks7Qjb5HZPH1G5Cxx0q23gzRJZNB/YZYpaPneAumwb6+Cj0riwBwp
LZ2ep9BqOKpYkbChzUlj/f16aLbLbt37Ols+inORrw2ekXx5dCr9Rdwid/pNeK0BCy3xCkhNUe1V
mSyG9zAZV96pKfegR8+/95c7gDE/jVsXM6M8TUJot1ghRC2HeLiMCfneG96gxx11W9D7pyOrsNTK
9rBxVAjRH+ZfQsjV/6vqL1BLAwQUAAAACAB7Vnpd7asBPtMAAABdAQAAUwAAAENPUFlfVE9fS0lO
RExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdpbi9r
ZXlzL2tleXJpbmcubHVhdY9PS8RADMXv/RSPnp1lWUQE8STLHhZF1j8X8dBO09lgOzNkpoUifndT
3eJBNqeQl/d7iTHYHUPKu6GSBuMl4lB3bDGScMu2yhw8PmgS9m5VGINH4bHKhMTO62zWEu5fnp7x
sH3dHlCrlINQAzXmI2HPvukIQRa0UAyJdWc6AUMz2CUHnBCFWhJF3OBwtwyFcsX+B9tNaBXXs5Pf
+2zoo3Y1d5wVqquDeHwW0Hor3fyfm/8zUbPMZr25Muvr8h23OCeuIvXlxX+A2LP2P+lk/iq+AVBL
AwQUAAAACAB7Vnpdzp8nqC4BAAApBAAAVQAAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFy
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
WV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0dob3N0R3VhcmRfSW50
ZW50R2F0ZV9SRU1PVkUudG9vbFBLAQIUAxQAAAAIAHtWel1/rBfjsgIAAAkFAABRAAAAAAAAAAAA
AACAAUQIAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvR2hv
c3RHdWFyZF9JbnRlbnRHYXRlX1JPTExCQUNLLnRvb2xQSwECFAMUAAAACAB7VnpdEdrZ1ncAAACU
AAAASgAAAAAAAAAAAAAAgAFlCwAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hp
ZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9CT09UX1BST0JFLnRvb2xQSwECFAMUAAAACAB7Vnpdpbef
b20BAACjAgAAUAAAAAAAAAAAAAAAgAFEDAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50
ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9ESVNBQkxFX0FVVE9CT09ULnRvb2xQSwECFAMU
AAAACAB7VnpdKJtt/zsDAABnBgAATwAAAAAAAAAAAAAAgAEfDgAAQ09QWV9UT19LSU5ETEVfUk9P
VC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9FTkFCTEVfQVVUT0JPT1Qu
dG9vbFBLAQIUAxQAAAAIAHtWel3Pb6dZ6gIAAF8FAABOAAAAAAAAAAAAAACAAccRAABDT1BZX1RP
X0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFUExB
Q0VfTEVHQUNZLnRvb2xQSwECFAMUAAAACAB7VnpdWwgzrRgCAADeAwAATgAAAAAAAAAAAAAAgAEd
FQAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNo
aWVsZF9SRVNUT1JFX0xFR0FDWS50b29sUEsBAhQDFAAAAAgAe1Z6XTenUu2FAAAAsAAAADkAAAAA
AAAAAAAAAIABoRcAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL0JP
T1RfU0hBMjU2U1VNU1BLAQIUAxQAAAAIAHtWel3iobpZhgIAAFIEAAA0AAAAAAAAAAAAAACAAX0Y
AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TUEsB
AhQDFAAAAAgAe1Z6XSv+hKGFBwAApREAADgAAAAAAAAAAAAAAIABVRsAAENPUFlfVE9fS0lORExF
X1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2Jvb3QtbGF1bmNoLnNoUEsBAhQDFAAAAAgAe1Z6
XRd7Ih74AAAArwEAAEYAAAAAAAAAAAAAAIABMCMAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RH
dWFyZEludGVudFRyaWFsL2RjcHJvLWludGVudHNoaWVsZC1ib290LmNvbmZQSwECFAMUAAAACAB7
Vnpd+BhhWIQAAACwAAAATAAAAAAAAAAAAAAAgAGMJAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9z
dEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL19tZXRhLmx1YVBLAQIU
AxQAAAAIAHtWel2lHOgaBhEAAOk1AABUAAAAAAAAAAAAAACAAXolAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ2xvYmFs
X3NoaWVsZC5sdWFQSwECFAMUAAAACAB7Vnpd7huHXXkJAADEGgAAUgAAAAAAAAAAAAAAgAHyNgAA
Q09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRl
LmtvcGx1Z2luL2ludGVudF9nYXRlLmx1YVBLAQIUAxQAAAAIAHtWel107rTV8wEAAHECAABjAAAA
AAAAAAAAAACAAdtAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9naG9zdGd1YXJkLXByb2QtMjAyNi0wOC5wZW1Q
SwECFAMUAAAACAB7VnpdDUFpVPMBAABxAgAAYQAAAAAAAAAAAAAAgAFPQwAAQ09QWV9UT19LSU5E
TEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tl
eXMvZ2hvc3RndWFyZC1yYy0yMDI2LTA4LnBlbVBLAQIUAxQAAAAIAHtWel3tqwE+0wAAAF0BAABT
AAAAAAAAAAAAAACAAcFFAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlh
bC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9rZXlyaW5nLmx1YVBLAQIUAxQAAAAIAHtW
el3OnyeoLgEAACkEAABVAAAAAAAAAAAAAACAAQVHAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0
R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9jb25maWcu
bHVhUEsBAhQDFAAAAAgAe1Z6XfE6fFK/BgAAGBMAAFUAAAAAAAAAAAAAAIABpkgAAENPUFlfVE9f
S0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdp
bi9saWNlbnNlX2NyeXB0by5sdWFQSwECFAMUAAAACAB7VnpdCv7HytcBAAADBAAAUwAAAAAAAAAA
AAAAgAHYTwAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9p
bnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfZ2F0ZS5sdWFQSwECFAMUAAAACAB7Vnpdvvx/LSoO
AABuLwAAVgAAAAAAAAAAAAAAgAEgUgAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50
ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfbWFuYWdlci5sdWFQSwEC
FAMUAAAACAB7Vnpd3CQtO9gKAADGKQAAVgAAAAAAAAAAAAAAgAG+YAAAQ09QWV9UT19LSU5ETEVf
Uk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vu
c2Vfc3RvcmFnZS5sdWFQSwECFAMUAAAACAB7VnpdEml73TcaAABMWAAASwAAAAAAAAAAAAAAgAEK
bAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRn
YXRlLmtvcGx1Z2luL21haW4ubHVhUEsBAhQDFAAAAAgAe1Z6XTkoWEIfDQAA9C0AAFUAAAAAAAAA
AAAAAIABqoYAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
aW50ZW50Z2F0ZS5rb3BsdWdpbi9vbmxpbmVfbGljZW5zZS5sdWFQSwECFAMUAAAACAB7Vnpd9TYg
1hoEAAA5BwAADQAAAAAAAAAAAAAAgAE8lAAAUkVBRE1FX1ZJLnR4dFBLBQYAAAAAGgAaAGsMAACB
mAAAAAA=
