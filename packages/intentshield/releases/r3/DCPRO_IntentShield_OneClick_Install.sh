#!/bin/sh
# DCPRO IntentShield 1.0 Final r3 candidate - network OneClick.
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
line 2 '1.0 Final r3 | Auto license sync'
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
    grep -Fq '# DCPRO IntentShield 1.0 Final r3 candidate - network OneClick.' "$path" || return 1
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
ABZKel3Pb6dZ6gIAAF8FAABOAAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hp
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
Fkp6XVsIM60YAgAA3gMAAE4AAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGll
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
e8Q9aU7+AFBLAwQUAAAACAAWSnpdN6dS7YUAAACwAAAAOQAAAENPUFlfVE9fS0lORExFX1JPT1Qv
R2hvc3RHdWFyZEludGVudFRyaWFsL0JPT1RfU0hBMjU2U1VNUxXN2w3DIAwAwP9OwQKJ/AAM44Cx
lUgRVE26f9Vb4ECgd9faBxH2UdFK0Uy9ay0Sk0ZzMWSL2bgRFJTuA7HJUBBJHEJf69mu9p167Pfx
ImglAaVKaDYkMqO7i5so11xIkQq4pMHJIuRoUs0RJANzTtxCGPr+rO2cj83nPk67xvY/dl3TXz9Q
SwMEFAAAAAgAFkp6XTuX3XuEAgAAUgQAADQAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
cmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TZZNNblw5DIT3OcW7gDPir6jTGCQldRpjdxvtziK3D9sO
xjOYzYOAB31VRZY8NgK7mK6FkC224jDNZYvcBdK10QyyHMbDMzk4iNvW+gdAx/H8uu7+/eWnfxPB
zMg+YVio51JIyQ0e6W2HKITu1nuAL0C2npZ7ebKMHdz8OE4v1/CX5/cf5/UyP5hoC3Ya9SVmDkUf
JL7W3KwRvnrhNUf32dcAeiQBHEyTtTtJP47z5b4u9+eT39cHUdGg0plMHq0yhXRrhuYqaaCKrZkZ
tm0TaLahBE5EagUW5Xkcf69f73+dflzf76effptPb7frfMKG+tTs+9t6/cbWpnfkAmmXXvfMy+pa
Y2+x3WZXiZIaNYO+zNg2hDRnrpi4+/8lbvkfgVTApLrUat5IFVeldbc1lEOlVDAdlrsH+h67jUVt
T+E9YJerPwL1uZ0vp4+xQK+bOCOY2iq+QVfa2FJ2C1Z2cMRkmLCVyQYzKq4KN0MIbRzHyznX5X09
5/Wyz5/QIVqb6LXf2k+jbgMRQJOJhvaRhLqrd5QdGseezbw8Ys9JMxfjv6C3X2/36yd01KZFB+6W
azRa3iIkJ+4MgKk1hN7HmENnHR5VTZy0HTZaRNAX9J9OPAqR7nNXLfvMTtWrVitywFae6THaJerW
eSFWO2SSGE5O2HNrfCFf/eKndfs0umRHV+gi0WhXQaNLRhUDKKlPcvKR0HdoDKNI4T540pLxqLt+
Ud/v11thP6jODbQ0R7UStMPw6i+2qGVv6imPJDUE8l5PjTnHCC4VJAxbGOX11c+Xz8clM6uQ08Im
W1I5tRWy+3TKEBdP0bUzG6zJwgO4h5JktSkZ+Tiul5fzZT3/8fkB/Q1QSwMEFAAAAAgAFkp6XSv+
hKGFBwAApREAADgAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9i
b290LWxhdW5jaC5zaLVYfVPbOBr/35/iaQo1Sdd2yE47V7LpTFgCzUAJF2Bv7ihlFFtOtLElryWT
pmW/+z2SbMeBcr2buysztS3pefs9r8rLF8GM8UAunJcw4RSIUjTNFGQ0h5kQ6ifgAnIqM7Li5l0q
kWWMz0EtKAxT8lVwiHOS0pXIl74jqQKvcC6GVx8GmvNBIM3/hcyD+kUv9YF+yUSuQB91ppPJ1SBI
ucJ91OQ6k4rgXkrWYN9mNBY5hUKiXqgCvjIJqSi4opEP5/Qe18OcEoUm2PVMMK58hw26zmrBEgo3
0NphLfASBe+6cNuHSDiA/27Ai3BLqxBEIixSypVswS28erW1d7IQUp0UJI/GKJWrq5yRpDw3Q9FL
w40Ndvb22Ov9drsPMqE0g30nEpw6/7WYhweEjCnoOdPRxWR6NXhCcDelGlIZWMoTRKPlpMuI5eBl
mr+hazU4nU1OBtV6oP3tJ2LeQl1fgBcjBe6XojV6e6sQvBB+KTfaFsy3b978/NYeSu8rGvPws5ze
M1HIlkO/0BDevy93e+9f7Tsoaa/9DbIc/RSDuythV37irpYTaT+6r3f/7u2m3m4Eux8Odj8e7F66
bc250+rDn05MWKLpkQ20pqPj68vRAZg9a5s+83FyNBrsfNs/8LJczOifzuVoOh6eoYtUriF3P+Va
4i8BbocYeixC1YKI3ge8SBJt0UEbw/Eip7GOu7XE5PDEitMIpCjykEofri8PAaNPMkwERb8oHZgE
IkbmHP3CQohJksxIuATBk7XvHP/t7nJyPf11NOgDvv82PLseDZxwQcPlXclnrw3fTDAlZEaTwc5+
H+5JUtDBTs8sl8ck2rFBz0JnzqGHYZ5j6HkjAe7e54ebz13vnX/bvsHH7etP/vZzr3ppd1yklGid
K4PPhui2EwRmUaeqV5SQlGnDtcBSlzJMcqqKnEPXqq9ds7F3x5jzfe3dLVYPgP5xtUX4124ZZi9h
iNxJRGaYyxZ9WDG1gFDwOGGhwqIUCKxKeS1Bu4ILBQIXchZFlMNsjc6pPOKXhjRFD+CNv/8Xvwxo
HWTgHrM8XRGsOZa9WhCOQUZCVZ0VOZB0xuYFxnol3TXMH1vf8LmldTCSkfw+BsYhoCrEWKRKrUsu
vsKIMsuNhbp0sVi7IdcGxC1d0lA/DluxVO5hUi0QPO2zXrn0JNJ16iSSPnEb6lZwco9QaOzxVMxs
SUPxoUhTwpHvPSQsC705VTrXMmgw19luVTNKb6tnqMrM2qi8t80MpfgofL/31rdH64x7aoSD2llc
viKjCu0aHaPCBvGyhlquTYxbYNrRjEjqFfI7B2onPOuIetfkrE3gH3thiypE8ZusRn3dU8YjTAAb
PO7D9je4nW16mzi6RFWlSXdQb5UzpX15gBn1R8EwsrEZYw5h3dTZhOFOlEZXxHCEFRwzbcxj4T9h
bc2OKxR/nZwfj6cf78bnV6Pzq8sP49HZ0R16wCpX9zp0b0jUv0vUAKit09MtTf8uyjVuT1IA9ozl
pXk0Mp3E4vqEw3NZgKggY9nX0cfidRMb0ElQDiBbEKYkX9LcJE2//0RSp/2DbNOlRZcwW262nN16
xI9KEtYLmAT6YdIU30+nA1NmokbML4Uup6hbtYARQrkpg5u9R6VGuzqqd3252AwwditLijlDBl8p
dj9/Kex3kBLG/aQgzx2PQsxzZqaWOUK4IZwnYkaSO7lgNIlKDo/8Xmb66bTVrNkfi0SxDME6nUyN
smg5jpJJYtwi3ZocodmJnBIzg1eZdHZWMFl30u32hhedB/P8q36+K7/f6e829PvalVbyIZHY9Xvd
Xg9bqR7ecMShMfti/Ggih9HIRQrjsJutIvUvu0+51WSDMyalmybTGDvQwiqyfkNDjsejo0EtqOyf
ZsFS6pnP9PNHMFbo/QT/oHxyqcPRDpeXxiOQMimx8bpOoxEwzlSoEtiubJZfNdk3Qtx1KgLcUthA
6+tEPcb8gQOJJgvygnMtbsNwc/h3MTPYVGes/Rc4Gp6NTz5c3U1O8WIQodF6KjRuR1sN/nqhBS8G
YKbExqjdbWwPzH2oiU3BlxyHQcPVdZqFcHQ+PDwbbZe0Q9zYDv9nj56cTQ515DVkmTEmw8sOouva
+ZxWLI7Glz8Q9/zpk+HVaEuQ7hU5DfXItC6Ll+toZgNbte2ojO0wwB1OkyBHr4vUXB7uvjs/l+lk
FdItzH3o3LwgXjz0jnHC9G7rzDEAj4+2gqPKE3uNaQUqzWy18Gy5sJXBM+x9wUPa2thCEl2n1tWl
FsFTC2yBWoyLY/0Ju6f6Momj+fUYFEspKIE3TQxlCiUlRjTWDLF6jIm0R80xvPWai16v+58Fwf/N
hyFBHJIE7Y2KXN/VI5qQ9f8qz7jAnsXnWFHrTNOtxQ6wJjpu7MUhTKOEcdq8aOsJKS51xTaJM3tB
7ZXG3sncT91u10z95pb57HxUzUUmoDrYFn5nqlM2JfzqPHTcZpdy6xCru4H+aaGKD+3H0pQq3Ewj
0AXEPSMFDxe6Hkh9xdj0E88jkmR9jccGHP3zCBbDqKykTZeYNo4xm9csXHstLn+BMSTbvdWKcP4J
UEsDBBQAAAAIABZKel0XeyIe+AAAAK8BAABGAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1
YXJkSW50ZW50VHJpYWwvZGNwcm8taW50ZW50c2hpZWxkLWJvb3QuY29uZpWQwW7CMBBE7/mKaYoQ
qAqGI0U9tRXqiar0VMTBxJvaqmNH9oakEh9fk/QH8MWzHvvNyPd47RsKpibH0j7inHT1C1lyKy0i
y8BtAzonG94hzd/EqEyoOxlokSmKZTANm2TmL8/vHzu8OU6399qQVekNFVF7xhe53R5Wtq7UFPJs
QF+RgyCFKsiaOh9+spGYIS3ztBz2ThtLOCCfmByFZayXOGI6TUd3KCqI2rFoo9hqH3nbyqDGFp/B
SCtO3nMxRi+ixnED5QfsGDGZzczDaj7fIFqiBqvBU6n6IA63B+ByAfWGMbannkqIk3EimTeRrmNG
TuH/T/4AUEsDBBQAAAAIABZKel2hwC9KfwAAAKkAAABMAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9H
aG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL19tZXRhLmx1YTXM
QQoCMQwF0P2cIsxaRA/gygFxpTgnyDTRBmpaOqkg4t2t1cniL/5/JLOVrPDqoJ7inWEHPbmUo6ix
2g2N+1VbryWERQz78+UEx0ZGLxwItuvNHxLPLksyifq1hxAnDICuFfNPoxKIEieuoQaZkTgv6/SE
ITofxXx5SH377j5QSwMEFAAAAAgAFkp6XXvo3A+KEAAAyTQAAFQAAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ2xvYmFs
X3NoaWVsZC5sdWGtWutv20YS/96/gl8Mki1NS2nSFnYYQIkVR4hsB5Lc4O56IChxKfFMcXV8SPYV
yd9+M/viLkkp6eGCRCH3MTs7O4/fzPL83JrkFcmr+SYlWWwN/YG1zugyyqxoVaU0t9ZRRXzrjlpk
H5O9leb/IqzjYl1ES/+HjK5g7MPECqyC/LtOC+LYdXpRp9soj9aksF0x5Jrs0xXRh8WsRQ0Y74GN
FhmCbWrEDaHb1oA1NJGqeFZjFumWtMZU0KT63163epdpnKreLCn17ixdlhfw80gLEsWkOId+Nbag
tApisqzX/ppUaZ5QZ+jZc9v1S1oXK3JZ1kvnhXu5jarVxrEd/8cLt9kKSDWIaZJmxEFCvm+n7BxC
Ju+sjtTQKQgpL9ujM97aHT4P/lyTPBh4eH57EiRRVhJPDA8EsS/yUCbzwL7Y5tVFXV7Ay+jtdBxO
7hbju8XNaDG2xbDRw+K+GTe+04bNP0zG0+vwZnr/djSV42fjT/ezRTPjZkPL6qaOijickR0tqvKC
ax2KQU5K6pxrHHlKy6p0di4cRFUXOZ6KH1VVkS7rimDH1yBPM4vkcXtquSoIye8/Ou4PFvzhvWXA
dc/nvaxHUBYdWxqTLAjsj2keZ+RtVKarl7YV5bFV8t9LOOEZrSJc5BYGO24QDJquz2lcbbBtOPj1
RdP8gaTrTcXaX7787YcefmGbRGe1CoiP6sqa0sSqnnfEqYCAndfbJViTVW1ILrmv3gzJkK8HSrbx
k4zSAoZbtDAafhySX1wmLkmWk+FrRt4yqCin71R+SVY4v/KrfQjPrqf11XonvrhXSC5iLCwN3iJc
9KclrspWxn9q2/PLjK6dLM3F5oFGSbLERwXXWaOP3j7YwVPmqH7/UKQV8dS7h2TAIP7Ibc5NTiuY
iGzi057TY8Nh0TCJYE4cVEVNjvFWVnTngMGXNPceCdmFBSnrrWCVEUIDkw8/Da94o25vomkHlNN8
jdoqWtBctVdYSXsDxa/wVcoE+dcY0HbCG/ha+sFyoqBABR/8MLms83K1IXENrqPpda+0ocqYdCJb
mqcVPU5G9EtC4rWX1CF6JEfpYKckgs/9FIpot4M9oZo9TPxNhGY6yXd1xYJGEBijxFLdYWwULdJ1
mkfNIvpc7TDkOP1AWkqKr0yT7fHdtWf7cJwleKl8LbTHBbX0iugQQBc/tuiATSuaV6AtpWqXDdi5
BNV/JHG4JiUYEmkGiQ4cw0Nz0yXeQY5tY0myutw0xtIzYpXRkhgj1LM6i5aBILvkqTKcLGoyHC94
vQXdbUEOv6dluswIuEZoc1xdp2Gs4StgGU8/dhFfg120egQMAXYLwTf+hw1HVF7wSCz+q1P7n1cw
kqtG4ad5WUX5SvlP2R7TFdgLwAt8RVYDBxrTCA4PHUXhmn6V7rxCcaM1oiq0ZBGn5Y4F+L3HpjG2
vEcIJKZrE65AuiXNYxhLtzU/i0rO9N6vynPV9PrVAP+01XD+cfIJFK4iYZZu0wodYouuPKxH8GB/
fmm5KdZ8JcboPo5NhdPN4dQX6erRkQIQ56pzDMO/BvCDO9Wpf+Xkv1cAyjI1H6o6VHQgRSHiQw9H
zcicHryC7aaluxrzAnUACHIVjwpN8JYD7mHHFOZrwE+69wTEGuEKPNCaxD3HYOwQDzTA89UCCVq3
/vLTsDOPLzh6t5jc36HzQZ1D5wCPSEw8Kpe095+Gbrfxeeh2RIGUAHJ8Gt2MOeAwBjRijYO31+Bh
0t01oGXG5yS5TYsC0HL8MJlGz7SuYIn46TXHSvYBfJqN8rPBP4J6wiK8CXuH2HE+7KyFZsxk7e9T
cuAG3byDye9JAUAY22BLIS3UscTBedwROTdpnH/JAwSLDQ77BQU/OPYNrejvQHpGMtuLW+IhEHEb
Ed2O7x4UJjtFc76hh1uS1/ZJcvPxdPxucUTm5+fWGPZOAW/lFk8WQOJwDBsIVf/BCAJQtyrAyDym
vZG12zwDkkV7j3Z+hx7YcwnC6W6fBx7bgzwCQgzMtb0dLQPMvnDEn08B6pL3HKD2eAdINTbB4IuH
WCLA9MsHS3HcL6d3+m52P50e2el3clYe0h3p423AeRs0vAG18Hv2EEtFhvb4WaptDhnLhustpHbw
CON4nAkYzI6WJar5s/tNGWi6SGSEEDouYGvLn7wfPUwXngwyhu2C73Mv15hk2v/4o/gj/yeYtgX6
xb0IR7G2nAm4t87A4hQLbPlWLAN4wmVOjHCtu2rp1BGqYjg7GbsU3NZ2xdlas1wQn0/EqF2/z8b8
he6+BhJAa7CYoWvMKX3UF0zGPMy8PIaT3aOgXOJuDZQjXW0/fajFZBeyKG/V5FGQxkHqpiVPALQg
bzQa9lFWm5J2nEjmlc4Sn0Dc8P/PLgtA2Pmz6nz5q+h99bN8eCkffnVd9wSvVcDyTpUtVTLgrToH
tYziENSi55QkoA3kgwhRIjbXAm7jkVwmhMRO5TEZmbCIlS8EsjWdAbi7GdlGKbDDSlPQD0oak/I5
X3nWKiNRYUlQJYKkiA2seGMlgJ03lkLWR0FFvw58jyZxC70ez/929w6AX0l48aaRlTQ09n8CMg49
LKBZ6S5Ki9IBGblWTE3OVG5gvGnhX0pOdr0OXnWRIHcRPqwJDsqx393fLQAoeGexd1ayX/jrDxP2
Y3sIF+BHpLzgyeqCVTrgcUch0mBn/OQxF+caTgyY2QMnW/AxCPYFUn0aiIdn+fA0lC3DrsvnGrMx
fOmT+yZ48aPpXXsmQeivWj74TfDzjyYlYx5G0XIV7YhUlNKqDhTIITbfQYxAfeJhtMSzykhSYTpj
vXh1hrGXY0IzmqIUgJGmEKMz80rJYPA6ePHLb0oi/O0EvCrTNY9DbwbfAkhKhXnxSb75SAI8Jfyq
JOJN01uVrdRCtL4Ofhs0+UVnvW9YEcskipocTSTaf/oTCz2hCFhC0fZNhJ2j7bbW1gsw2yivoyyk
SWJUfEwL1f/0ocXGP/zJjgR/PLBQlNsX3RWM5+9Gn8bhaHZr96/QC/+Nqo92phttw+0s0+OJrYDo
CEwEdOzFXEo5i34VNdxHZykOck8TxuBRHCeCCb6EfG4bBSkv2SnDRUXllAQcXVx6UV1RoxAn1aMn
h5RHbYzDuBHu0tgYyYvjtqiKWzgGjX5X0DWsVdqtwCmq6LF32DzLUrq/2hBQXFzTiOVy7In1Li0d
zwFNo0h7OiHtoQpCj5aItmB0mmteWVy0tAGNKH6nWCBjVV0sNuuNEBHWwAMpGCocxf+qy+oDpY/u
18CWB2WrmT0Vt6MDFbzvHyERtNnbs2Vjmx/vZzwnH32adI6OZnFg7C2MV3DMIU+kMG6HcAyRKvXB
eKbZ8L9PD7lMKdWrBLLsrixkuqqpNt5YbB8hm3BO3IGgk2gG8jsTvaSWBCn1KThZ0QfJ+wUoDC39
GNh17LO/nW3P4vDsw9ntGV47+ba4hkHkDclApBXEkz7pYfWrzqM9YHRUHNvEdqwCmFx1Sue6fz1V
COcxoO2G9dl9HluvbEt6jekH+rO+gnATgfhfEgN4OrhqASvZIFCnepdlF/nOyjJ/DRG26vnt0pVW
JlqMZgtPv3kd+gOPn54n4VegewexMVbB0YVgjjGl5XbTOFYgzbI22NYt4/KI1TexOfTIvlM0mhue
uKdCN/dlfunNkcBVO+ud6ykvjO1kuzBF3M7Y0K2ntJ3M+qq1XaYrBh43i/w9zkviFzXGmNG9OlDi
2XrEyOyVZFjxGf0bwcpXxW0OG4lYvIBmmssyh5CKUlT1hJbWU1AUTZLDhg856OidiNiC5ns6oM24
5ekv//bUClgxWNI5Wuf9nuprD+9fzWsfWZo4UXYQ/KvCQx9G7BWt2J0Z8rnldxaRN/NpDgl+Gv/V
dVp3TCcuQrt3O6duPwV3bJKQj5nVG4xgCU7c001y54Vn3Pm1lOpbI9mmmPd6owFNcfdoAn6G9U19
0XjHGZA0H5Oo3MRViycJIZtVm0CtIcYO/qxLdOCOdu8rmnR30gdD9UDW9slNgiZDlgw4YpNiDdtr
EKVA21zb1WWqPoeRCuVUtw9O03zGGOjfD9Nlc0PIsyywNAti1gz+aQS9jtsB2doelTdQHJuFDjPQ
n0gVFRFdV5pGFm47uaLkQPcrutQwtRhwEX9D9195aq1G8fHf+bmFUrBGePJY5bJyAgkRQO8Er6ot
Zv0yDbCSgm6hsaxXK0gskjqzYsCReLPpI6XFhnBeWfkBEkyClSyMw8Uz28yOAqVnzLjSJAX6Ba+N
wSlh+R+/TNkTv/15CZ7hFGLqtlxz3uEhUCEVW3sKyOy7paE3fDUY6GgUXFAiXJCApV4DS5myiK02
6FNh6Ue2hcTUgva9nZVcsk87HA3gnp9tz89i6+zD5dntJYJc5NADxj3xvUdyye6vuSqa56PpPrI3
yjJ6INKcpdvj6oHfN7m9OmNocuNvzHZlRmpvRrcW/VvfJ+lDxari8y7fv4hXa0wZWKkcMhX/ke6y
GiK7fXRu+wutmw/388XNw2h2Hf59fBe+vb/HAkGPbOZoD79z1YqdDmo05acC7fGMupV7MUv4npyZ
mwwjJ1XXnk7eje/m43A2fv8wH193UuYmhvUtDVrLjB1y9phUEPX0KMp6mHl7A6/DjHEZw/0sMsUm
Sex5LLR3PKj0c2pbLAMIx7PZ/czYkuD26LaOUGZ9krigwUtEPKkI7++uUMtBjPOH2zG8smxb8tEn
XC4v1zUMRpDmuVevmQlv2NUiM6JonwH8FfVqBZw+7TW/MOhEsS4hLW+Kqopsd1WJNAZYgm4pIxMh
1vvD6eR2sriyajgaWT3asvvdDq4D735N+T0Lg+e59Tk9f5+yzwh4MIW4kJPqQItHi3+T4msaDD2g
xPArNFeUrT38dlXMumi+tdVkziaqkgq8+Wn5juY5WaF+dSsrapN348Xn+9nHcPRpEj7cjX4fTabo
Tr5rs5znFXC8kksJvlsM4I4MdlcNalVTW4x9Hk0W4efJ+8nRhRNYuK6UlStZJUl6ge2mhBJNPtjr
F3U+yef18lNBMUr3F6fYyLRshl3TnHTl2ThppTxMcf6CVLv5qqGkwVHFFddFjbPBhZmlW2Jg8+mY
PrsV78H4hCD7pOP1ZIHi4gIsVzlcL+KW7XEEo0IADtLDoMEreqnpQqIls8jBiGMdxBKUjW7Rxvp7
vFm7mTPlKuTQjgDy0EEUeMTyK1xohpbXwaCtoWA34xkXdfgejrjlU5HMkatU6e4C+KcdAzCYlcFA
13HpcLGr5wMsSehrcMx5aoaKcRiPClRYP+q2eqMqdHJ9Mbl7SdQWx6f76ZSHOtw6CyFNsXZJElqA
5rMQylSnddcgmAc3it/C4mrI/KOE26CV6DBWdVHgB36rCNiyGJAsys41g8Y9brnLOhc3+219cgXT
eGfw66vWqXPzmt5/vhJfAQl0XoJtsyKPeeeBf8wcY4jGkfVtu3cHpr7oV0fs0pydC7vGiJhIogRk
AaeVZrG1iUorSfO0hLWvhAQhlEMMSsF5sBtEOJ+q1i7MexNCmcW2YncDmPoCs37Zc1wI7Y9S9ITz
/4YpZAObL5not5aecU36365+9PjEvvkNZmts0SiWqkkSTzGYevSDoR6A0oWWrIR68gOgbfS8JKak
G+51cz8uIzGqkVAXsHbP538rPOA/wcf8h/8CUEsDBBQAAAAIABZKel3uG4ddeQkAAMQaAABSAAAA
Q09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRl
LmtvcGx1Z2luL2ludGVudF9nYXRlLmx1YZ0Z/W/aSPb3/hUjnVaBxrjQdq+7LYNEU5pyl0Iuob09
rVZosIfgrbG9noHgjbJ/+715M2N7jElPhxQyX+9z3ufQ65HLTSrk5Y7lIZkmkifykklOrtiK9P0B
6fVIul7HUcJfiA0L03uS5alMZZFxjyQpCfk+CjiZvpj7z+DsNMl28i2R0ZYLybYZiRKyjYI8FTxI
k1B45CpKdgfyeUEWgKL3nvA9kCSdDJjosfD3nZBbtRCkaR5GCbAiuoh5vpOIOki3WcwlD2GUSBZI
sudwMpCCpElc+GSWkjsgvss5CSORMRlskNPJ1+n84vJm/N5/FqcBiwnKScnD4zsc+stllIT8AEtq
ag6td0kgozRRuGTn4BVdknNADmIxufHFHzmsPj+cF89hhydhE2wdJZHknX0JpjQHU0rPkt12xfMz
wpKQ7Cnd4wCxspWAI0Mcb3Z3vA1xlIgo5J3MW3WfEfgY9BliWeF35h9GdOUf+nY2VLOBmRVqr7B7
hdorBs8UpZIGqiXh9517b+OtmZCaFBOCg9hGtPsuojCzjZ7djzTizaivYTT3Ar44Rbm2UaLQdl8M
+m9e1iUQHCxAMslWMe883FM4RDeehsRvT8SpFPThEQe0761ztuXwPwYOl7CTRLGHGNVnBZS/8ZCu
WSy4F2xYHPPkjuMhJRLFLyrzHX/0lMDdYx28zTlw1dGSCB6vfcvCu2pK+2ZSY8OsOFQRPboKOFuo
7Fht5kTssiyOuCD7SEQgu0eUOWbqTCLjQmHigbL7JE16KRh9zLIsSu6IZPkdlwK95MJSIpEgjAjY
j3lvJzjJeL6NhACRlDdI2AxiFm3Bu8kGfP+egb+wndwAsShgSnS/oQSWbzulJArJfZs5qGW8ejT0
8rwyeLzSs7q1lNs+P2QRaLnroDzaHgF2hD/a6cHOkP7Yx49Gsk5zsvTAFyAGRRmLctF5qOAgPOWy
sgdfcSQ2j10SpqXtGDZQklW7BMq9uo2FQWOhaJ4oBkbOGhGFaES11yiQanwYDCma0b3dtAsbe6I/
LB1bwQ6RBFJQxlb5H/NW9HsqqF8AU8QxgoAukRNmJkxxgfEDdwq1U/RrHlLZ/APSoczT+OnKA0sC
j4Qb88zt0aP7fHzWEvOyNEpkR6H3hBdoYtEazdman/APjrKFX3S7RJm1jS9WIwAIh4coAAxGRsU4
K+xyMTKKRgyBHyV7Fkchhot3TYya24w+HCgg9Ar4Lh7rTAag4lxIiwwnNHsHQxUz9AhlFHRwAntI
MRFBMO9pKCAE0dtOilIpIURgRae0sxK1HZwPkB4EY6r/nYdqYcsOQvLMRGl26JRLXtiteC2t6zha
moTcCTwpMEbXU0C4yzG6UCmAaTSN2m7CJbVaQj9HajhEua3MPXMIpLeSl0uQiOHu+vW0I3MW3W2k
kdPkJqD1Qi80z4eHU0wc0z+CLb4DW2O0goXQPTlAiI5U8aNMXgHFLOFvCTgGnIvuoBiKIZRJfpdH
soAIyINvAkSLYB8yAZQ+NS4wqaHprkv9GcWP6GCggqSzOBxg6KyCEvKr7WREf3JLk/DQHdGXr/vP
de5TOdkBdA++el7NC+2b9j4gxvk/N4kaYxvSNy+bBLRsOWciTaydlz5pnVxt0rPp7Ov4avpheTv5
15fJ7GJypu0VagCEMfnThZl/ndxcja+vp7PL5cV8thhfLBww7cKC82SJ116bFy6m8S/T2+VsvlhO
frm+ml5MF8vFJ1hpQ9ppXIE2TcCM9ZYiU17c4CVmN5fUhy8348V0PmsIqK9u+No9/HHy7+WH6e1i
OrtYLK/n09ni1pWQyyFQqendhb/9NL9ZKAzXV+OLyefJzJXF3uuw77/5qXEfNzeTyy9X45vl9Xjx
qcGsufLRz38/SRkgLyfLjzfjz5PlP758vq4w2COloZ99HN8uQNefgdL0/dVkebu4mf9zcqZ0CXax
AK7bdt04q9oM0Dqke2rw0ydgAXN56gT1ehaGMkvXo3WCG+rmzdLAN24cV70QNDqqgCtbIVB8+o0T
jKYwZWsJBSVAEci0hOnQvGWFapnEbgvFofTr+MZJUUPGpOTbTNrDAk6/I5iWgWgsUigcOcuFg6Sl
zC29WklbqdN4ObI6grzvYzGgK0YxVAumAigR2NBgOh4TPaFu0Ui67qaKsWpPFxvoQJWq7R2b1Pqg
OwcdJ9VQdxTqC1IXZCjP3Kr+59WMohpWrUYp/1LJDDH7T6hy1NArk54deCrRwZ/XyMlemarswLP5
uErDJcHTeaolUeqsWAM+mag6p1JqBQx3FEdBJJeKAx0RvXKtsGsF6E+yKOHhEvr7CDUQ+NCNhEu7
UaE89Bv82ARftG8U3mFAW1KzV7QtF48thcqa87ADSocCH+425B4kkh1vrSulcMpKgHDmCtpZ0Ji6
rusqQ7O9pGkNbXvqFJQPj461qshaayytrzhrGCy/g79E6LSpUlgiIBQ1XYeSh9JX/xPaGtuKggoo
t/+ZLT/czK+vJx/eqrcXAC6SgGx4zh2JDBqnPq+w5PyPHUSC0tggPd0DHDaxLwzKVUHU+5WDtfRD
o6mRu2oDTCWcG7nqekeVvHJvUcVkVM/rN+6G2cSr1w0EDkevBuX4h8FftP//aNUhUr05INKm3dRt
R31MEUyrl4tfy+FvdbGUwVu1uI8bdQgqHOylOn58Qh0j2j/erHizbZXwg7+c5FFK7Ae2jwR/hZOI
1dORx7zt6JBjJiau9j3sb/plFK3FsPrH1IMG2LJj/ntOxNJnHttY3DAwIX19zrYpdJBnSnuDdlVg
QxoY9fuBj69DxhZc5EcGwW2CewpfvXc9xlCb27pM3+orZbxm/Lr1hsuDhtRB346uzqAHttMGyRp/
bbw3sdo8Y/jXuG2iaRfqe9dSl9mMjexHobB/HMn9ZvVwPmi4XJDuEkmrBke/SAn1IKXfoyr/Uu9O
zo1pWPw+H2BEPHbpdCdpzecVeqxdTlJwxDc8Kqc7utEnbgUYGg3sE4b1m5Pq1yLpG2hHak51nuqu
TNvoHzA6mEmhJ4YT10dP8qM+kFpuzMH67wxEPYHirxtBGvd0T7naSWSE76G6TAKunksj/JXEP4X6
VkUpsoWKcZer59kUi3WsyFep3BB2AFIbtudkBbKRdCV4vueqggVRImF/1mjHj+2S0ZEppGvtZ+N9
7KQCEIt+fEY4sKNf/wZf54Pf0JxbXnAwBDnZsfmpHK2qt+ufJyNObWxyGbDTWrLrOs7M8Iea/wJQ
SwMEFAAAAAgAFkp6XXTutNXzAQAAcQIAAGMAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
cmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9naG9zdGd1YXJkLXBy
b2QtMjAyNi0wOC5wZW1lkrmWokAARXO+onNPHzYBCSYosBCU1WIpyViEghIREBG/fronnRu9c196
v79/0ODBcr/8SLMt/esEL7/um3EsS+tb4Go1HQhtDurCaSCABgCeDi478Ps39elnQ8CnzftzPe4W
taziBE1vEfgMDfsHuc+CNZlqfMn0bjoMVx1sq6rjl2wt5anT5UKkTZwkZjjn4ipYZYjEhryugEge
44qbgILytanYY69cuPf92cES1U3Pwq3ryPsl7VvcfObbPSLAh/04LeIsCl7/sAt2SZhpEHKlM1se
s3dplXbhoFV1O8kVjaODscHpsiFT+iClH6FWx/nnjQN5GtHl9DKm3LMZDvSLkcoceqLrBZABRzyZ
qUwJcRAecnxQCmtY/VJ4+8PDDpvaFkexKmWZR+aLcxFTp3yN0Ts5hriRzk639KruzK3LPZSRDhyE
TcLStIKCKF+HDppHO4BqBefMA4KEScFEN6sJd8mW2pRNslMu3fyxy65rGVA1pV5Z0rEugs7ya/WE
nrMS72/6kJXL3qjPmx23MFlVGGJyiMT8GHvyJ8HzuR7TU5die0WxqN8Bu+U1IHmmVClYdaSkeBD7
pbKpgq1U5Bk5GKynyoW7DjkkG3eVlPFGe0efvUvludwEr/O6YNPuK8UEtaMBAP8w/xKC7v6/qv4C
UEsDBBQAAAAIABZKel0NQWlU8wEAAHECAABhAAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1
YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tleXMvZ2hvc3RndWFyZC1y
Yy0yMDI2LTA4LnBlbWWSuZaiQABFc76ic08foJQtmKCAAgtkKRYBM2SnpJFFbP366Z50bvTOfen9
/PxBRSZ2P/xYPWHtw0bZr/tkHIzVsYeu2tCppZ2pPDkVEmRA6Gkwk+Hv3zX2z0Zw1F3umD274QBz
sSzyr+5gMFEiLp5394NVM/TTiRtbGpXF1SNT21HCSXyFz/1y8ybIBQDUw3zUOvu82Lju35qhHpmg
jzlZ85HOTePDO0+Zlp+b92Uh5ksZb0v1wi1XaTsHuLGxqqlfjEFf73x/uMo6FunKBCOeAtVEOwp6
x/oa8tSw81lus6iP6uxu+0oFwtZsDKUU4bbtiI5Dpzo83+bBus0sYM5rsnWmG+O0Z7MJC4dxb/s3
oUFRykqBlSrPuEwMNiV5tuwKluWBUOziF1sAYaag4ZhQvvEAzXY0D48Lhy+nMOmkZmnKejWO4t7U
JLO0I2+R2Tx9RuQscdKtt4M0SWTQf2GWKWj53gLpsG+vgo9K4sAcKS2dnqfQajiqWJGwoc1JY/39
emi2y27d+zpbPopzka8NnpF8eXQq/UXcInf6TXitAQst8QpITVHtVZkshvcwGVfeqSn3oEfPv/eX
O4AxP41bFzOjPE1CaLdYIUQth3i4jAn53hveoMcddVvQ+6cjq7DUyvawcVQI0R/mX0LI1f+r6i9Q
SwMEFAAAAAgAFkp6Xe2rAT7TAAAAXQEAAFMAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3Vh
cmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9rZXlyaW5nLmx1YXWP
T0vEQAzF7/0Uj56dZVlEBPEkyx4WRdY/F/HQTtPZYDszZKaFIn53U93iQTankJf3e4kx2B1Dyruh
kgbjJeJQd2wxknDLtsocPD5oEvZuVRiDR+GxyoTEzuts1hLuX56e8bB93R5Qq5SDUAM15iNhz77p
CEEWtFAMiXVnOgFDM9glB5wQhVoSRdzgcLcMhXLF/gfbTWgV17OT3/ts6KN2NXecFaqrg3h8FtB6
K938n5v/M1GzzGa9uTLr6/IdtzgnriL15cV/gNiz9j/pZP4qvgFQSwMEFAAAAAgAFkp6Xc6fJ6gu
AQAAKQQAAFUAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3By
b2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9jb25maWcubHVhtZPdasMwDIXv8xSh113c/TIG
g72JcW2ReHWkIssdZezdp25d14w0UEZ9JfA5R5+FxSCFsX6vaj3BibMhcv1cz0yPYko2TfBrJtt2
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
VcOA+itxVHbNNaakvyjs0lAupU++/Jufss7ffK23O9Tw5AdDWaZr200Pwi28JHFKIsIsUuIv3Rxa
/8ueW37EkY0mAkSdmCTMdLg8Tef3RFZ+52K8WGyCLroi1L0qySrAQjAukMh6hQIlXdh9/hNQSwEC
FAMUAAAACAAWSnpd1ycRAEQFAACBCwAAUAAAAAAAAAAAAAAAgAEAAAAAQ09QWV9UT19LSU5ETEVf
Uk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0dob3N0R3VhcmRfSW50ZW50R2F0ZV9JTlNU
QUxMLnRvb2xQSwECFAMUAAAACAAWSnpdcikUMSUCAADWAwAATwAAAAAAAAAAAAAAgAGyBQAAQ09Q
WV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0dob3N0R3VhcmRfSW50
ZW50R2F0ZV9SRU1PVkUudG9vbFBLAQIUAxQAAAAIABZKel1/rBfjsgIAAAkFAABRAAAAAAAAAAAA
AACAAUQIAABDT1BZX1RPX0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvR2hv
c3RHdWFyZF9JbnRlbnRHYXRlX1JPTExCQUNLLnRvb2xQSwECFAMUAAAACAAWSnpdEdrZ1ncAAACU
AAAASgAAAAAAAAAAAAAAgAFlCwAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hp
ZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9CT09UX1BST0JFLnRvb2xQSwECFAMUAAAACAAWSnpdpbef
b20BAACjAgAAUAAAAAAAAAAAAAAAgAFEDAAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50
ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9ESVNBQkxFX0FVVE9CT09ULnRvb2xQSwECFAMU
AAAACAAWSnpdKJtt/zsDAABnBgAATwAAAAAAAAAAAAAAgAEfDgAAQ09QWV9UT19LSU5ETEVfUk9P
VC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNoaWVsZF9FTkFCTEVfQVVUT0JPT1Qu
dG9vbFBLAQIUAxQAAAAIABZKel3Pb6dZ6gIAAF8FAABOAAAAAAAAAAAAAACAAccRAABDT1BZX1RP
X0tJTkRMRV9ST09ULy5kY3Byb19pbnRlbnRzaGllbGQvdG9vbHMvSW50ZW50U2hpZWxkX1JFUExB
Q0VfTEVHQUNZLnRvb2xQSwECFAMUAAAACAAWSnpdWwgzrRgCAADeAwAATgAAAAAAAAAAAAAAgAEd
FQAAQ09QWV9UT19LSU5ETEVfUk9PVC8uZGNwcm9faW50ZW50c2hpZWxkL3Rvb2xzL0ludGVudFNo
aWVsZF9SRVNUT1JFX0xFR0FDWS50b29sUEsBAhQDFAAAAAgAFkp6XTenUu2FAAAAsAAAADkAAAAA
AAAAAAAAAIABoRcAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL0JP
T1RfU0hBMjU2U1VNU1BLAQIUAxQAAAAIABZKel07l917hAIAAFIEAAA0AAAAAAAAAAAAAACAAX0Y
AABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9TSEEyNTZTVU1TUEsB
AhQDFAAAAAgAFkp6XSv+hKGFBwAApREAADgAAAAAAAAAAAAAAIABUxsAAENPUFlfVE9fS0lORExF
X1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2Jvb3QtbGF1bmNoLnNoUEsBAhQDFAAAAAgAFkp6
XRd7Ih74AAAArwEAAEYAAAAAAAAAAAAAAIABLiMAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RH
dWFyZEludGVudFRyaWFsL2RjcHJvLWludGVudHNoaWVsZC1ib290LmNvbmZQSwECFAMUAAAACAAW
SnpdocAvSn8AAACpAAAATAAAAAAAAAAAAAAAgAGKJAAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9z
dEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL19tZXRhLmx1YVBLAQIU
AxQAAAAIABZKel176NwPihAAAMk0AABUAAAAAAAAAAAAAACAAXMlAABDT1BZX1RPX0tJTkRMRV9S
T09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vZ2xvYmFs
X3NoaWVsZC5sdWFQSwECFAMUAAAACAAWSnpd7huHXXkJAADEGgAAUgAAAAAAAAAAAAAAgAFvNgAA
Q09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRl
LmtvcGx1Z2luL2ludGVudF9nYXRlLmx1YVBLAQIUAxQAAAAIABZKel107rTV8wEAAHECAABjAAAA
AAAAAAAAAACAAVhAAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlhbC9k
Y3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9naG9zdGd1YXJkLXByb2QtMjAyNi0wOC5wZW1Q
SwECFAMUAAAACAAWSnpdDUFpVPMBAABxAgAAYQAAAAAAAAAAAAAAgAHMQgAAQ09QWV9UT19LSU5E
TEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2tl
eXMvZ2hvc3RndWFyZC1yYy0yMDI2LTA4LnBlbVBLAQIUAxQAAAAIABZKel3tqwE+0wAAAF0BAABT
AAAAAAAAAAAAAACAAT5FAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0R3VhcmRJbnRlbnRUcmlh
bC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4va2V5cy9rZXlyaW5nLmx1YVBLAQIUAxQAAAAIABZK
el3OnyeoLgEAACkEAABVAAAAAAAAAAAAAACAAYJGAABDT1BZX1RPX0tJTkRMRV9ST09UL0dob3N0
R3VhcmRJbnRlbnRUcmlhbC9kY3Byb2ludGVudGdhdGUua29wbHVnaW4vbGljZW5zZV9jb25maWcu
bHVhUEsBAhQDFAAAAAgAFkp6XfE6fFK/BgAAGBMAAFUAAAAAAAAAAAAAAIABI0gAAENPUFlfVE9f
S0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJvaW50ZW50Z2F0ZS5rb3BsdWdp
bi9saWNlbnNlX2NyeXB0by5sdWFQSwECFAMUAAAACAAWSnpdCv7HytcBAAADBAAAUwAAAAAAAAAA
AAAAgAFVTwAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9p
bnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfZ2F0ZS5sdWFQSwECFAMUAAAACAAWSnpdvvx/LSoO
AABuLwAAVgAAAAAAAAAAAAAAgAGdUQAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50
ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vuc2VfbWFuYWdlci5sdWFQSwEC
FAMUAAAACAAWSnpd3CQtO9gKAADGKQAAVgAAAAAAAAAAAAAAgAE7YAAAQ09QWV9UT19LSU5ETEVf
Uk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRnYXRlLmtvcGx1Z2luL2xpY2Vu
c2Vfc3RvcmFnZS5sdWFQSwECFAMUAAAACAAWSnpd1F96+a8ZAABIVgAASwAAAAAAAAAAAAAAgAGH
awAAQ09QWV9UT19LSU5ETEVfUk9PVC9HaG9zdEd1YXJkSW50ZW50VHJpYWwvZGNwcm9pbnRlbnRn
YXRlLmtvcGx1Z2luL21haW4ubHVhUEsBAhQDFAAAAAgAFkp6XTkoWEIfDQAA9C0AAFUAAAAAAAAA
AAAAAIABn4UAAENPUFlfVE9fS0lORExFX1JPT1QvR2hvc3RHdWFyZEludGVudFRyaWFsL2RjcHJv
aW50ZW50Z2F0ZS5rb3BsdWdpbi9vbmxpbmVfbGljZW5zZS5sdWFQSwECFAMUAAAACAAWSnpdtU91
PPIQAAA+KQAADQAAAAAAAAAAAAAAgAExkwAAUkVBRE1FX1ZJLnR4dFBLBQYAAAAAGgAaAGsMAABO
pAAAAAA=
