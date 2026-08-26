#!/bin/sh
# DCPRO GhostGuard OneClick v13
# Fresh-device production bootstrap:
#   KOReader -> SimpleUI -> GhostGuard 0.9.1 -> system service -> integration verify
#
# GhostGuard package: 0.9.1
# GhostGuard runtime: 0.9.0 / continuous-learning-shadow-v1
# Native filtering remains SHADOW_ONLY (no input grab/injection).

ROOT="${DCPRO_ONECLICK_ROOT:-/mnt/us}"
DATA="$ROOT/.dcpro_ghostguard"
TMP="${DCPRO_ONECLICK_TMP:-$DATA/oneclick-v13}"
LOG="${DCPRO_ONECLICK_LOG:-$ROOT/documents/GhostGuard_OneClick_v13.log}"

KO_VERSION="2026.07.1"
KMC_REPO="https://repo.kindlemodding.org/manifest.v2.json"

SUI_ZIP_URL="https://codeload.github.com/doctorhetfield-cmd/simpleui.koplugin/zip/refs/heads/main"
SUI_ZIP="$TMP/simpleui-main.zip"
SUI_UNPACK="$TMP/simpleui-unpack"

GG_PKG_NAME="ghostguard_0.9.1_kindle5-kindlepw2-kindlehf.kpkg"
GG_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/artifacts/$GG_PKG_NAME"
GG_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/artifacts/$GG_PKG_NAME"
GG_BRIDGE_PRIMARY="https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/packages/ghostguard/source/payload/dcghostguardpro.koplugin/simpleui_bridge.lua"
GG_BRIDGE_MIRROR="https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/packages/ghostguard/source/payload/dcghostguardpro.koplugin/simpleui_bridge.lua"

GG_PKG="$TMP/$GG_PKG_NAME"
GG_UNPACK="$TMP/ghostguard-unpack"
SHIM="$TMP/shim"

mkdir -p "$TMP" "$ROOT/documents" 2>/dev/null || exit 1
: > "$LOG" 2>/dev/null || true

log(){ printf '%s\n' "$*" >> "$LOG" 2>/dev/null || true; }

FBINK="$(command -v fbink 2>/dev/null || true)"
[ -n "$FBINK" ] || for x in /var/local/kmc/bin/fbink /var/local/kmc/kindlehf/bin/fbink /var/local/kmc/kindlepw2/bin/fbink; do
    [ -x "$x" ] && FBINK="$x" && break
done
say(){ [ -n "$FBINK" ] && "$FBINK" -S 2 -x 1 -y "$1" -r "$2" >/dev/null 2>&1 || true; }
fail(){ log "ERROR: $*"; say 14 "LOI: xem GhostGuard_OneClick_v13.log"; exit 1; }

download(){
    url="$1"; out="$2"; rm -f "$out" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        log "Download via curl: $url"
        curl -L -f -sS "$url" -o "$out" >>"$LOG" 2>&1 && [ -s "$out" ] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        log "Download via wget: $url"
        wget -q -O "$out" "$url" >>"$LOG" 2>&1 && [ -s "$out" ] && return 0
    fi
    return 1
}

find_kpm(){
    for k in /var/local/kmc/bin/kpm /var/local/kmc/kindlehf/bin/kpm /var/local/kmc/kindlepw2/bin/kpm; do
        [ -x "$k" ] && { printf '%s\n' "$k"; return 0; }
    done
    return 1
}

valid_ko_root(){
    d="$1"
    [ -n "$d" ] && [ -d "$d/plugins" ] || return 1
    [ -d "$d/frontend" ] || [ -f "$d/koreader.sh" ] || [ -x "$d/bin/koreader.sh" ] || [ -f "$d/reader.lua" ]
}

detect_koreader_root(){
    if [ -n "${DCPRO_KO_ROOT_OVERRIDE:-}" ] && valid_ko_root "$DCPRO_KO_ROOT_OVERRIDE"; then printf '%s\n' "$DCPRO_KO_ROOT_OVERRIDE"; return 0; fi
    for d in "$ROOT/koreader" "$ROOT/extensions/koreader"; do if valid_ko_root "$d"; then printf '%s\n' "$d"; return 0; fi; done
    p="$(find "$ROOT" -maxdepth 8 -type f -path '*/plugins/dcghostguardpro.koplugin/main.lua' 2>/dev/null | head -n 1)"
    [ -n "$p" ] || p="$(find "$ROOT" -type f -path '*/plugins/dcghostguardpro.koplugin/main.lua' 2>/dev/null | head -n 1)"
    if [ -n "$p" ]; then d="${p%/plugins/dcghostguardpro.koplugin/main.lua}"; [ -d "$d/plugins" ] && { printf '%s\n' "$d"; return 0; }; fi
    p="$(find "$ROOT" -maxdepth 8 -type f \( -name koreader.sh -o -name reader.lua \) 2>/dev/null | head -n 1)"
    [ -n "$p" ] || p="$(find "$ROOT" -type f \( -name koreader.sh -o -name reader.lua \) 2>/dev/null | head -n 1)"
    if [ -n "$p" ]; then
        d="${p%/*}"; n=0
        while [ "$n" -lt 5 ]; do
            if [ -d "$d/plugins" ]; then printf '%s\n' "$d"; return 0; fi
            parent="${d%/*}"; [ "$parent" = "$d" ] && break; d="$parent"; n=$((n + 1))
        done
    fi
    return 1
}

koreader_target(){ case "$1" in */kindlehf/bin/kpm) echo kindlehf;; */kindlepw2/bin/kpm) echo kindlepw2;; *) echo kindle;; esac; }
ko_sha256(){ case "$1" in kindle) echo "1fa9cc2784ffa42eaa309445d4e81661f825614c9c32349554fed6e4c8757a1d";; kindlehf) echo "3343a916d12f36c01b59df1f65bd83ff5616e6c2a4dfbe919e7fa1400b8b1bbb";; kindlepw2) echo "ea1f575c54492a2c679d128b7f3210fd7d6a87e5f5a1ff1f7a7fe2080ff68f86";; *) return 1;; esac; }
verify_sha256(){
    f="$1"; expected="$2"
    if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"; [ "$got" = "$expected" ]; return $?; fi
    if command -v openssl >/dev/null 2>&1; then got="$(openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}')"; [ "$got" = "$expected" ]; return $?; fi
    log "WARN: SHA256 tool unavailable; checksum verification skipped."; return 0
}
unzip_to(){
    zip="$1"; dest="$2"; rm -rf "$dest" 2>/dev/null || true; mkdir -p "$dest" || return 1
    if command -v unzip >/dev/null 2>&1; then unzip -q "$zip" -d "$dest" >>"$LOG" 2>&1; return $?; fi
    if command -v busybox >/dev/null 2>&1; then busybox unzip -q "$zip" -d "$dest" >>"$LOG" 2>&1; return $?; fi
    return 1
}

install_koreader_kpm(){
    kpm="$1"; [ -x "$kpm" ] || return 1
    repos="$("$kpm" -y list-repo 2>&1 || true)"; printf '%s\n' "$repos" >>"$LOG"
    if ! printf '%s\n' "$repos" | grep -Fq "kindlemodding"; then "$kpm" -y add-repo "$KMC_REPO" >>"$LOG" 2>&1 || true; fi
    "$kpm" -y update >>"$LOG" 2>&1 || log "WARN: KPM update failed before KOReader install."
    "$kpm" -y install koreader >>"$LOG" 2>&1 || return 1
    KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"; [ -n "$KO_ROOT" ]
}

install_koreader_official(){
    kpm="$1"; target="$(koreader_target "$kpm")"; expected="$(ko_sha256 "$target")" || return 1
    asset="koreader-${target}-v${KO_VERSION}.zip"; url="https://github.com/koreader/koreader/releases/download/v${KO_VERSION}/${asset}"; zip="$TMP/$asset"; dest="$TMP/koreader-unpack"
    log "Official KOReader fallback: $url"; download "$url" "$zip" || return 1; verify_sha256 "$zip" "$expected" || return 1; unzip_to "$zip" "$dest" || return 1
    src=""
    for d in "$dest/koreader" "$dest"/*/koreader; do if [ -f "$d/koreader.sh" ] || [ -d "$d/frontend" ]; then src="$d"; break; fi; done
    if [ -n "$src" ]; then rm -rf "$ROOT/koreader" 2>/dev/null || true; cp -R "$src" "$ROOT/koreader" >>"$LOG" 2>&1 || return 1
    else
        for d in "$dest/extensions/koreader" "$dest"/*/extensions/koreader; do if [ -x "$d/bin/koreader.sh" ] || [ -d "$d/frontend" ]; then src="$d"; break; fi; done
        [ -n "$src" ] || return 1; mkdir -p "$ROOT/extensions" || return 1; rm -rf "$ROOT/extensions/koreader" 2>/dev/null || true; cp -R "$src" "$ROOT/extensions/koreader" >>"$LOG" 2>&1 || return 1
    fi
    KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"; [ -n "$KO_ROOT" ]
}

ensure_koreader(){
    KO_ROOT="$(detect_koreader_root 2>/dev/null || true)"; if [ -n "$KO_ROOT" ]; then log "KOReader already installed: $KO_ROOT"; return 0; fi
    KPM="$(find_kpm 2>/dev/null || true)"; if [ -n "$KPM" ] && install_koreader_kpm "$KPM"; then log "KOReader installed via KPM: $KO_ROOT"; return 0; fi
    log "KOReader KPM path unavailable/failed; using official release ZIP."; install_koreader_official "$KPM"
}

simpleui_installed(){ target="$KO_ROOT/plugins/simpleui.koplugin"; [ -f "$target/main.lua" ] && [ -f "$target/features/sui_quickactions.lua" ] && [ -f "$target/infra/sui_config.lua" ] && [ -f "$target/engines/sui_window.lua" ]; }
install_simpleui(){
    if simpleui_installed; then log "SimpleUI already installed and API-compatible."; return 0; fi
    download "$SUI_ZIP_URL" "$SUI_ZIP" || return 1; unzip_to "$SUI_ZIP" "$SUI_UNPACK" || return 1
    src=""
    for d in "$SUI_UNPACK/simpleui.koplugin-main" "$SUI_UNPACK"/*; do
        if [ -f "$d/main.lua" ] && [ -f "$d/_meta.lua" ] && [ -f "$d/features/sui_quickactions.lua" ] && [ -f "$d/infra/sui_config.lua" ] && [ -f "$d/engines/sui_window.lua" ]; then src="$d"; break; fi
    done
    [ -n "$src" ] || return 1
    target="$KO_ROOT/plugins/simpleui.koplugin"; backup="$KO_ROOT/plugins/.simpleui.koplugin.v13-old"; staging="$KO_ROOT/plugins/.simpleui.koplugin.v13-new.$$"
    rm -rf "$staging" "$backup" 2>/dev/null || true; cp -R "$src" "$staging" >>"$LOG" 2>&1 || return 1
    [ -d "$target" ] && mv "$target" "$backup" >>"$LOG" 2>&1 || true
    if ! mv "$staging" "$target" >>"$LOG" 2>&1; then [ -d "$backup" ] && mv "$backup" "$target" 2>/dev/null || true; return 1; fi
    if ! simpleui_installed; then rm -rf "$target" 2>/dev/null || true; [ -d "$backup" ] && mv "$backup" "$target" 2>/dev/null || true; return 1; fi
    rm -rf "$backup" 2>/dev/null || true; log "SimpleUI install: PASS ($target)"; return 0
}

verify_gg_archive(){
    [ -s "$GG_PKG" ] || return 1
    if tar -tzf "$GG_PKG" > "$TMP/gg-archive.list" 2>>"$LOG"; then :; elif command -v gzip >/dev/null 2>&1; then gzip -dc "$GG_PKG" 2>>"$LOG" | tar -tf - > "$TMP/gg-archive.list" 2>>"$LOG" || return 1; else return 1; fi
    grep -q '^manifest.json$' "$TMP/gg-archive.list" && grep -q '^install.sh$' "$TMP/gg-archive.list" && grep -q '^payload/dcghostguardpro.koplugin/main.lua$' "$TMP/gg-archive.list" && grep -q '^payload/dcghostguardpro.koplugin/simpleui_bridge.lua$' "$TMP/gg-archive.list" && grep -q '^payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua$' "$TMP/gg-archive.list" && grep -q '^system/ghostguard-native-shadow.lua$' "$TMP/gg-archive.list"
}
extract_gg(){ rm -rf "$GG_UNPACK" 2>/dev/null || true; mkdir -p "$GG_UNPACK" || return 1; tar -xzf "$GG_PKG" -C "$GG_UNPACK" >>"$LOG" 2>&1 && return 0; command -v gzip >/dev/null 2>&1 || return 1; gzip -dc "$GG_PKG" 2>>"$LOG" | tar -xf - -C "$GG_UNPACK" >>"$LOG" 2>&1; }
verify_gg_extracted(){
    [ -f "$GG_UNPACK/manifest.json" ] && [ -f "$GG_UNPACK/install.sh" ] && [ -f "$GG_UNPACK/payload/dcghostguardpro.koplugin/main.lua" ] && [ -f "$GG_UNPACK/payload/dcghostguardpro.koplugin/simpleui_bridge.lua" ] && [ -f "$GG_UNPACK/payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua" ] && [ -f "$GG_UNPACK/system/ghostguard-native-shadow.lua" ] || return 1
    compact="$(tr -d ' \t\r\n' < "$GG_UNPACK/manifest.json" 2>/dev/null || true)"; printf '%s' "$compact" | grep -Fq '"id":"ghostguard"' && printf '%s' "$compact" | grep -Fq '"version":[0,9,1]'
}
patch_gg_installer(){
    src="$GG_UNPACK/install.sh"; dst="$TMP/gg-install-patched.sh"
    awk 'BEGIN { replacing = 0; done = 0 } /^KO_ROOT=""$/ && !done { print "KO_ROOT=\"${DCPRO_KO_ROOT_OVERRIDE:-}\""; print "if [ -z \"$KO_ROOT\" ]; then"; print "  for candidate in \"$ROOT/koreader\" \"$ROOT/extensions/koreader\"; do"; print "    if [ -d \"$candidate/plugins\" ]; then KO_ROOT=\"$candidate\"; break; fi"; print "  done"; print "fi"; replacing = 1; done = 1; next } replacing { if ($0 ~ /^\[ -n "\$KO_ROOT" \] \|\|/) { print; replacing = 0 } next } { print }' "$src" > "$dst" || return 1
    grep -Fq 'DCPRO_KO_ROOT_OVERRIDE' "$dst" || return 1; /bin/sh -n "$dst" >>"$LOG" 2>&1 || return 1; cp "$dst" "$GG_UNPACK/install.sh" >>"$LOG" 2>&1 || return 1; chmod 755 "$GG_UNPACK/install.sh" 2>/dev/null || true
}
make_cmp_shim(){
    command -v cmp >/dev/null 2>&1 && return 0; mkdir -p "$SHIM" || return 1
    cat > "$SHIM/cmp" <<'EOS'
#!/bin/sh
a="$1"; b="$2"
[ -r "$a" ] && [ -r "$b" ] || exit 1
if command -v cksum >/dev/null 2>&1; then [ "$(cksum < "$a" 2>/dev/null)" = "$(cksum < "$b" 2>/dev/null)" ]; exit $?; fi
if command -v md5sum >/dev/null 2>&1; then aa="$(md5sum "$a" 2>/dev/null | awk '{print $1}')"; bb="$(md5sum "$b" 2>/dev/null | awk '{print $1}')"; [ -n "$aa" ] && [ "$aa" = "$bb" ]; exit $?; fi
[ "$(wc -c < "$a" 2>/dev/null)" = "$(wc -c < "$b" 2>/dev/null)" ]
EOS
    chmod 755 "$SHIM/cmp" 2>/dev/null
}

sync_simpleui_bridge(){
    target="$KO_ROOT/plugins/dcghostguardpro.koplugin/simpleui_bridge.lua"; tmp="$TMP/simpleui_bridge.lua"
    if ! download "$GG_BRIDGE_PRIMARY" "$tmp"; then download "$GG_BRIDGE_MIRROR" "$tmp" || return 1; fi
    grep -Fq 'features/sui_quickactions' "$tmp" && grep -Fq 'infra/sui_config' "$tmp" && grep -Fq 'engines/sui_window' "$tmp" || return 1
    cp "$tmp" "$target" >>"$LOG" 2>&1 || return 1; grep -Fq 'features/sui_quickactions' "$target" && grep -Fq 'infra/sui_config' "$target" && grep -Fq 'engines/sui_window' "$target" || return 1
    log "GhostGuard <-> SimpleUI bridge sync: PASS"
}
verify_ghostguard(){
    target="$KO_ROOT/plugins/dcghostguardpro.koplugin"; [ -f "$target/main.lua" ] || return 1
    grep -Fq 'version = "0.9.0"' "$target/defaults.lua" 2>/dev/null && grep -Fq 'runtime_revision = "continuous-learning-shadow-v1"' "$target/defaults.lua" 2>/dev/null || return 1
    [ -f "$target/adaptive_bootstrap.lua" ] && [ -f "$target/simpleui_bridge.lua" ] && [ -f "$DATA/service/ghostguard-native-shadow.lua" ] && [ -f "$DATA/KPM_INSTALL_OK" ] || return 1
    grep -Fq 'PACKAGE_VERSION=0.9.1' "$DATA/KPM_INSTALL_OK" 2>/dev/null && grep -Fq "KO_READER_ROOT=$KO_ROOT" "$DATA/KPM_INSTALL_OK" 2>/dev/null && grep -Fq 'NATIVE_FILTER=SHADOW_ONLY' "$DATA/KPM_INSTALL_OK" 2>/dev/null
}
write_v13_marker(){
    cat > "$DATA/ONECLICK_V13_OK" <<EOF
DCPRO_GHOSTGUARD_ONECLICK_V13
KO_READER_ROOT=$KO_ROOT
SIMPLEUI_PLUGIN=$KO_ROOT/plugins/simpleui.koplugin
GHOSTGUARD_PLUGIN=$KO_ROOT/plugins/dcghostguardpro.koplugin
GHOSTGUARD_PACKAGE=0.9.1
GHOSTGUARD_RUNTIME=0.9.0
RUNTIME_REVISION=continuous-learning-shadow-v1
SIMPLEUI_BRIDGE=READY
NATIVE_FILTER=SHADOW_ONLY
INPUT_GRAB=OFF
EVENT_INJECTION=OFF
INSTALLED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
EOF
}

log "=================================================="; log "DCPRO GhostGuard OneClick v13"; log "Date: $(date)"; log "ROOT=$ROOT"; log "=================================================="
say 1 "GhostGuard OneClick v13"; say 2 "KOReader + SimpleUI + GhostGuard"
say 3 "[1/8] Kiem tra KOReader..."; ensure_koreader || fail "KOReader installation failed."; log "ACTIVE_KO_ROOT=$KO_ROOT"; say 5 "KOReader... OK"
say 6 "[2/8] Cai SimpleUI..."; install_simpleui || fail "SimpleUI installation/API verification failed."; say 7 "SimpleUI... OK"
say 8 "[3/8] Tai GhostGuard 0.9.1..."; if ! download "$GG_PRIMARY" "$GG_PKG"; then log "GhostGuard primary failed; trying jsDelivr."; download "$GG_MIRROR" "$GG_PKG" || fail "Cannot download GhostGuard 0.9.1."; fi
say 9 "[4/8] Kiem tra GhostGuard..."; verify_gg_archive || fail "GhostGuard artifact invalid/incomplete."
say 10 "[5/8] Giai nen + chuan bi..."; extract_gg || fail "Cannot extract GhostGuard artifact."; verify_gg_extracted || fail "GhostGuard extracted package verification failed."; patch_gg_installer || fail "Cannot patch temp GhostGuard installer for active KOReader root."; make_cmp_shim || fail "Cannot prepare copy verification compatibility."
say 11 "[6/8] Cai GhostGuard..."; OLD_PATH="$PATH"; [ -d "$SHIM" ] && PATH="$SHIM:$PATH" && export PATH; export DCPRO_KO_ROOT_OVERRIDE="$KO_ROOT"; (cd "$GG_UNPACK" || exit 1; /bin/sh ./install.sh oneclick-v13) >>"$LOG" 2>&1; RC=$?; unset DCPRO_KO_ROOT_OVERRIDE; PATH="$OLD_PATH"; export PATH; [ "$RC" -eq 0 ] || fail "GhostGuard install.sh failed with rc=$RC."
say 12 "[7/8] Ket noi SimpleUI..."; sync_simpleui_bridge || fail "GhostGuard SimpleUI bridge sync failed."
say 13 "[8/8] Xac minh..."; simpleui_installed || fail "SimpleUI disappeared after GhostGuard install."; verify_ghostguard || fail "GhostGuard verification failed."; write_v13_marker || fail "Cannot write v13 completion marker."
KPM="$(find_kpm 2>/dev/null || true)"; if [ -n "$KPM" ]; then "$KPM" -y update >>"$LOG" 2>&1 || log "WARN: final KPM update failed; installation is already complete."; fi
rm -rf "$GG_UNPACK" "$SHIM" "$SUI_UNPACK" 2>/dev/null || true
log "SUCCESS"; log "KO_ROOT=$KO_ROOT"; log "SimpleUI=READY"; log "GhostGuard package=0.9.1"; log "GhostGuard runtime=0.9.0 / continuous-learning-shadow-v1"; log "SimpleUI bridge=READY"; log "Native filter=SHADOW_ONLY"; log "Restart KOReader once."
say 15 "THANH CONG! Restart KOReader"
exit 0
