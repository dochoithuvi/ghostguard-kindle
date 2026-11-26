#!/bin/sh
# DCPRO IntentShield 1.0 Final r3 candidate - network OneClick.
# Install KOReader through KPM; install verified ZenOS release; install local embedded IntentShield.
set -eu
ROOT=/mnt/us
LOG="$ROOT/documents/IntentShield_OneClick.log"
mkdir -p "$ROOT/documents"
exec >>"$LOG" 2>&1
fail(){ echo "FAIL: $*"; exit 1; }
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
trap 'rm -rf "$T"' EXIT
trap 'exit 130' HUP INT TERM
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
if [ -z "$KR" ]; then
    KPM=
    for k in /var/local/kmc/bin/kpm /var/local/kmc/kindlehf/bin/kpm /var/local/kmc/kindlepw2/bin/kpm; do
        if [ -x "$k" ]; then KPM="$k"; break; fi
    done
    [ -n "$KPM" ] || fail "Install KPM first (;kpm)"
    repos=$("$KPM" -y list-repo 2>&1 || :)
    case "$repos" in *kindlemodding*) ;; *) "$KPM" -y add-repo https://repo.kindlemodding.org/manifest.v2.json || fail "KPM repository";; esac
    "$KPM" -y update || fail "KPM update"
    "$KPM" -y install koreader || fail "KOReader install"
    detect_ko
    [ -n "$KR" ] || fail "KOReader root not found"
fi
P="$KR/plugins"
[ ! -d "$P/zen_ui.koplugin" ] || fail "Migrate old Zen UI using official Zen UI update before continuing"
[ ! -d "$P/projecttitle.koplugin" ] || fail "Disable Project: Title before continuing"
[ ! -d "$P/simpleui.koplugin" ] || fail "Disable legacy SimpleUI before continuing"
if [ ! -d "$P/zenos.koplugin" ]; then
    URL=https://github.com/xZenLabs/zen-os/releases/download/v4.3.2/zenos.koplugin.zip
    if command -v curl >/dev/null; then curl -fLSs "$URL" -o "$T/zen.zip" || fail "ZenOS download"; else wget -O "$T/zen.zip" "$URL" || fail "ZenOS download"; fi
    printf '%s  %s\n' '3782a354400fb03f25aa7d745bf31633de0b15dfea99c9342be73687fc8d8a83' "$T/zen.zip" | sha256sum -c - || fail "ZenOS checksum"
    unzip -q "$T/zen.zip" -d "$T/zen"
    Z="$T/zen/zenos.koplugin"
    [ -f "$Z/main.lua" ] && [ -f "$Z/config/defaults.lua" ] && [ -f "$Z/fonts/readerly/Readerly_R-Regular.ttf" ] || fail "Unexpected ZenOS layout"
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
    mv "$Z/config/defaults.lua.dcpro" "$Z/config/defaults.lua"
    mv "$Z" "$P/zenos.koplugin" || fail "ZenOS install"
else
    echo "Existing ZenOS preserved; configure Navbar/font through Zen Settings if desired"
fi
# Payload is appended by build_oneclick.py. No network download of IntentShield itself.
sed '1,/^__DCPRO_PAYLOAD_BELOW__$/d' "$0" | base64 -d > "$T/payload.zip"
unzip -q "$T/payload.zip" -d "$T/payload"
B="$T/payload/COPY_TO_KINDLE_ROOT"
[ -f "$B/documents/GhostGuard_IntentGate_INSTALL.sh" ] || fail "Invalid embedded payload"
# Preserve backups and existing markers; copy only known distributable files.
mkdir -p "$ROOT/GhostGuardIntentTrial" "$ROOT/documents"
cp -R "$B/GhostGuardIntentTrial/." "$ROOT/GhostGuardIntentTrial/"
for f in "$B/documents/"*.sh; do cp "$f" "$ROOT/documents/"; done
/bin/sh "$ROOT/documents/GhostGuard_IntentGate_INSTALL.sh" || fail "IntentShield install"
echo "SUCCESS: Open KOReader, finish ZenOS setup, check license and Global Shield. Auto Boot remains opt-in."
sync
exit 0
__DCPRO_PAYLOAD_BELOW__
