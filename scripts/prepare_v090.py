#!/usr/bin/env python3
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text()


def write(rel, text):
    (ROOT / rel).write_text(text)


def replace_once(text, old, new, label):
    if old not in text:
        if new in text:
            return text
        raise SystemExit(f"missing anchor: {label}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Runtime configuration
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/payload/dcghostguardpro.koplugin/defaults.lua"
s = read(rel)
s = replace_once(s, 'version = "0.8.0"', 'version = "0.9.0"', "defaults version")
s = replace_once(s, 'runtime_revision = "system-service-v1"',
                 'runtime_revision = "continuous-learning-shadow-v1"', "runtime revision")
if "cloud_upload_enabled = false" not in s:
    s = replace_once(s, "    cloud_compress_threshold = 2000000,",
                     "    cloud_compress_threshold = 2000000,\n    cloud_upload_enabled = false,",
                     "cloud public switch")
if "adaptive_promotion_min_cluster" not in s:
    anchor = "    adaptive_learning_during_protect = true,\n"
    block = """    adaptive_learning_during_protect = true,
    -- v0.9 continuous learning is event-driven. Normal touches do only a few
    -- arithmetic checks; flash is checkpointed only after strong anomalies.
    adaptive_min_base_score = 7,
    adaptive_cluster_radius_px = 96,
    adaptive_checkpoint_samples = 8,
    adaptive_checkpoint_seconds = 120,
    adaptive_promotion_min_cluster = 6,
    adaptive_promotion_min_confidence = 0.72,
    adaptive_promotion_min_age_seconds = 30,
    adaptive_max_clusters = 32,
    adaptive_max_candidate_clusters = 32,
    -- Native shadow coordinates are raw evdev coordinates. Keep them as
    -- diagnostics until controller-axis normalization is proven on-device.
    adaptive_import_native_shadow = false,
    native_shadow_enabled = true,
"""
    s = replace_once(s, anchor, block, "adaptive policy")
write(rel, s)


# ---------------------------------------------------------------------------
# Metadata and runtime bootstrap
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/payload/dcghostguardpro.koplugin/_meta.lua"
s = read(rel)
s = re.sub(r'GhostGuard v0\.8\.0:[^"]*',
           'GhostGuard v0.9.0: continuous low-power profile learning plus a read-only system-wide native shadow observer; actual blocking remains fail-open in KOReader while native filtering is validated.',
           s, count=1)
write(rel, s)

rel = "packages/ghostguard/source/payload/dcghostguardpro.koplugin/main.lua"
s = read(rel)
if "continuous learning v0.9 loaded" not in s:
    anchor = "    self.config, self.guard = config, guard_or_err\n"
    block = """    self.config, self.guard = config, guard_or_err

    -- v0.9: continuous adaptive learning. A fault in this optional layer must
    -- never prevent the proven core protection path from loading.
    local AdaptiveBootstrap, adaptive_err = load_local("adaptive_bootstrap.lua")
    if AdaptiveBootstrap then
        local call_ok, install_ok, adaptive_or_err = pcall(AdaptiveBootstrap, self.guard, config)
        if call_ok and install_ok == true then
            self.adaptive = adaptive_or_err
            logger.info("DCPRO GhostGuard continuous learning v0.9 loaded")
        else
            logger.warn("DCPRO GhostGuard adaptive learning unavailable:",
                call_ok and adaptive_or_err or install_ok)
        end
    else
        logger.warn("DCPRO GhostGuard adaptive bootstrap missing:", adaptive_err)
    end
"""
    s = replace_once(s, anchor, block, "main adaptive loader")
s = s.replace("Dừng và tạo báo cáo báo cáo Cloud", "Tạo báo cáo GhostGuard")
s = s.replace("Trạng thái Cloud", "Trạng thái báo cáo GhostGuard")
write(rel, s)


# ---------------------------------------------------------------------------
# Harden continuous-learning promotion: stage -> atomic write -> publish.
# No candidate is discarded and no in-memory approved profile is changed if
# persistence fails. Also lazily activates after internal resume retries.
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/payload/dcghostguardpro.koplugin/adaptive_bootstrap.lua"
s = read(rel)
start = s.find("function Adaptive:promoteReady()")
end = s.find("\nfunction Adaptive:pruneCandidates()", start)
if start < 0 or end < 0:
    raise SystemExit("adaptive promoteReady anchors missing")
promote = r'''function Adaptive:promoteReady()
    local profiles = self.guard.profiles
    local approved = profiles and profiles.approved
    if not approved or approved.ready ~= true then return 0 end

    local min_count = tonumber(self.config.adaptive_promotion_min_cluster) or 6
    local min_conf = tonumber(self.config.adaptive_promotion_min_confidence) or 0.72
    local min_age = tonumber(self.config.adaptive_promotion_min_age_seconds) or 30
    local max_clusters = tonumber(self.config.adaptive_max_clusters) or 32

    -- Work on a staged copy. The live approved profile is swapped only after
    -- the complete profile has been written atomically.
    local staged = { clusters = {} }
    for key, value in pairs(approved) do
        if key ~= "clusters" and type(value) ~= "table" then staged[key] = value end
    end
    for _, cluster in ipairs(approved.clusters or {}) do
        staged.clusters[#staged.clusters + 1] = copy_cluster(cluster)
    end

    local promoted, keep = 0, {}
    for _, cluster in ipairs(self.clusters) do
        cluster.confidence = self:confidence(cluster)
        local age = math.max(0,
            (tonumber(cluster.last_seen_wall) or 0) - (tonumber(cluster.first_seen_wall) or 0))
        local repeat_ok = (tonumber(cluster.session_hits) or 0) >= 2
            or age >= min_age
            or (tonumber(cluster.count) or 0) >= math.max(min_count + 4, 10)
        local cx, cy = center(cluster.x_min, cluster.x_max), center(cluster.y_min, cluster.y_max)
        local already = nil
        if type(profiles.match) == "function" then
            local ok, match = pcall(profiles.match, profiles, cx, cy)
            if ok then already = match end
        end

        if not already and #staged.clusters < max_clusters
            and (tonumber(cluster.count) or 0) >= min_count
            and (tonumber(cluster.confidence) or 0) >= min_conf and repeat_ok then
            local copied = copy_cluster(cluster)
            copied.confidence = self:confidence(copied)
            staged.clusters[#staged.clusters + 1] = copied
            staged.profile_kind = "GHOST_CLUSTER"
            staged.ready = true
            staged.suspect_contacts = (tonumber(staged.suspect_contacts) or 0)
                + (tonumber(copied.count) or 0)
            promoted = promoted + 1
        else
            keep[#keep + 1] = cluster
        end
    end

    if promoted == 0 then return 0 end
    table.sort(staged.clusters, function(a, b)
        local ca, cb = tonumber(a.confidence) or 0, tonumber(b.confidence) or 0
        if ca == cb then return (tonumber(a.count) or 0) > (tonumber(b.count) or 0) end
        return ca > cb
    end)

    local payload = profiles:serialize(staged, "APPROVED")
    local ok, err = self.storage:writeAtomic(profiles.approved_path, payload)
    if not ok then
        self.last_error = "adaptive promotion save failed: " .. tostring(err)
        return 0
    end

    profiles.approved = staged
    self.clusters = keep
    self.promotions = self.promotions + promoted
    self.last_error = nil
    if self.guard.session then
        pcall(self.guard.session.writeAction, self.guard.session,
            { timestamp_us = os.time() * 1000000, frame = -1, slot = -1, score = 0 },
            "ADAPTIVE_PROFILE_PROMOTE", "regions=" .. tostring(promoted))
        pcall(self.guard.session.flush, self.guard.session)
    end
    self:save(true)
    return promoted
end
'''
s = s[:start] + promote + s[end:]

# Native shadow remains diagnostic in v0.9.0 until raw evdev axes are mapped
# to the exact KOReader coordinate space on target devices.
s = s.replace("    self:importNativeCandidates()\n    self:patchObserver()",
              "    if self.config.adaptive_import_native_shadow == true then\n"
              "        self:importNativeCandidates()\n"
              "    end\n"
              "    self:patchObserver()", 1)

# Keep the native pause marker until core stop has completed, then release it.
old_stop = '''    guard.stop = function(g, reason)
        if self.active then pcall(self.endSession, self) end
        return original_stop(g, reason)
    end
'''
new_stop = '''    guard.stop = function(g, reason)
        local ok, result = original_stop(g, reason)
        if self.active then pcall(self.endSession, self) end
        return ok, result
    end
'''
if old_stop in s:
    s = s.replace(old_stop, new_stop, 1)

# Some system-service resume retries call the underlying start wrapper directly.
# Lazily attach continuous learning on the first raw event so those paths cannot
# accidentally run Protect without the adaptive observer.
if "local original_raw = guard.onRawEvent" not in s:
    s = s.replace("    local original_status = guard.statusText\n    local original_reset = guard.resetProfile\n",
                  "    local original_status = guard.statusText\n"
                  "    local original_reset = guard.resetProfile\n"
                  "    local original_raw = guard.onRawEvent\n", 1)
    marker = '''    guard.statusText = function(g, ...)
        local base = original_status(g, ...)
        return tostring(base or "GhostGuard") .. "\\n" .. self:statusText()
    end
'''
    raw_wrapper = marker + '''
    guard.onRawEvent = function(g, event)
        if not self.active and type(g.isProtecting) == "function" and g:isProtecting()
            and g.profiles and g.profiles:hasApproved() then
            local adaptive_ok, adaptive_err = pcall(self.beginSession, self)
            if not adaptive_ok then
                self.last_error = "adaptive lazy begin error: " .. tostring(adaptive_err)
            end
        end
        return original_raw(g, event)
    end
'''
    if marker not in s:
        raise SystemExit("adaptive status wrapper anchor missing")
    s = s.replace(marker, raw_wrapper, 1)
write(rel, s)


# ---------------------------------------------------------------------------
# Public local-report cleanup in the core.
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/payload/dcghostguardpro.koplugin/ghostguard_core.lua"
s = read(rel)
old = '''        local active_profile = self.profiles:hasApproved() and self.profiles.approved_path
            or (self.profiles.pending and self.profiles.pending_path or nil)
        local out_ok, out_result = self.storage:prepareCloudOutbox(session, {
            device_id = self.device_id,
            model = self.model,
            profile_path = active_profile,
        })
        if out_ok then self.last_outbox = out_result end
'''
new = '''        if self.config.cloud_upload_enabled ~= false then
            local active_profile = self.profiles:hasApproved() and self.profiles.approved_path
                or (self.profiles.pending and self.profiles.pending_path or nil)
            local out_ok, out_result = self.storage:prepareCloudOutbox(session, {
                device_id = self.device_id,
                model = self.model,
                profile_path = active_profile,
            })
            if out_ok then self.last_outbox = out_result end
        end
'''
s = replace_once(s, old, new, "core cloud outbox")
s = s.replace('return true, "stopped; report queued in cloud_outbox"',
              'return true, "stopped; report saved locally"', 1)
old_status = '''        "Báo cáo: " .. self.config.report_dir,
        "Cloud outbox: " .. self.config.cloud_outbox_dir,
        "Cloud Apps Script: ĐÃ CẤU HÌNH",
        "Cloud worker: " .. (self.cloud:isBusy() and "ĐANG CHẠY" or "RẢNH"),
        "Drive đích: " .. tostring(self.config.drive_root_folder_id),
'''
new_status = '''        "Báo cáo local: " .. self.config.report_dir,
        "Cloud upload: TẮT trong bản public",
'''
if old_status in s:
    s = s.replace(old_status, new_status, 1)
write(rel, s)


# ---------------------------------------------------------------------------
# v0.9 system bridge wording + NATIVE_SHADOW policy/status.
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/payload/dcghostguardpro.koplugin/ghostguard.lua"
s = read(rel)
s = s.replace("runtime wrapper v0.8", "runtime wrapper v0.9", 1)
s = s.replace("The protection engine remains in ghostguard_core.lua. v0.8 adds", "The protection engine remains in ghostguard_core.lua. v0.9 keeps", 1)
s = s.replace('"runtime v0.8 loaded"', '"runtime v0.9 loaded"')
s = s.replace("System service v0.8:", "System service v0.9:")
write(rel, s)

rel = "packages/ghostguard/source/payload/dcghostguardpro.koplugin/system_service.lua"
s = read(rel)
if "native_shadow = bool01" not in s:
    s = replace_once(s,
        '        pause_during_sleep = bool01(parse(text, "PAUSE_DURING_SLEEP"), true),',
        '        pause_during_sleep = bool01(parse(text, "PAUSE_DURING_SLEEP"), true),\n'
        '        native_shadow = bool01(parse(text, "NATIVE_SHADOW"), true),',
        "system policy native shadow")
s = s.replace('"# DCPRO GhostGuard v0.8 persistent service policy",',
              '"# DCPRO GhostGuard v0.9 persistent service policy",', 1)
if '"NATIVE_SHADOW=" .. p.native_shadow' not in s:
    s = replace_once(s,
        '        "PAUSE_DURING_SLEEP=" .. p.pause_during_sleep,\n        "DESIRED_MODE=" .. p.desired_mode,',
        '        "PAUSE_DURING_SLEEP=" .. p.pause_during_sleep,\n'
        '        "NATIVE_SHADOW=" .. p.native_shadow,\n        "DESIRED_MODE=" .. p.desired_mode,',
        "system setDesired native shadow")
old = '''    local fail_open = parse(status, "FAIL_OPEN") or "YES"
    local safe, detail = self:controllerSafe()
    local controller_state = safe and "OK" or ("CHANGED — " .. tostring(detail))
    return string.format(
        "System service v0.8: PID %s, power=%s\\nController: %s (%s) — %s\\nFail-open=%s; native grab/injection=OFF",
        pid, power, controller, event, controller_state, fail_open)
'''
new = '''    local fail_open = parse(status, "FAIL_OPEN") or "YES"
    local shadow = parse(status, "NATIVE_SHADOW") or "0"
    local shadow_pid = parse(status, "NATIVE_SHADOW_PID") or "0"
    local native_filter = parse(status, "NATIVE_FILTER") or "OFF"
    local safe, detail = self:controllerSafe()
    local controller_state = safe and "OK" or ("CHANGED — " .. tostring(detail))
    return string.format(
        "System service v0.9: PID %s, power=%s\\nController: %s (%s) — %s\\nFail-open=%s; Native shadow=%s (PID %s); Native filter=%s; grab/injection=OFF",
        pid, power, controller, event, controller_state, fail_open, shadow, shadow_pid, native_filter)
'''
s = replace_once(s, old, new, "system status v0.9")
write(rel, s)


# ---------------------------------------------------------------------------
# System supervisor: launch a read-only event-driven shadow observer while
# awake. It never grabs or injects input. Failed shadow processes are retried
# with a bounded backoff to protect battery.
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/system/ghostguard-service.sh"
s = read(rel)
s = s.replace("# DCPRO GhostGuard v0.8 system supervisor.",
              "# DCPRO GhostGuard v0.9 system supervisor.", 1)
s = s.replace('VERSION="0.8.0"', 'VERSION="0.9.0"', 1)
if 'SHADOW_SCRIPT=' not in s:
    s = replace_once(s, 'CONTROLLER_CHANGED="$SERVICE_DIR/CONTROLLER_CHANGED"\n',
        'CONTROLLER_CHANGED="$SERVICE_DIR/CONTROLLER_CHANGED"\n'
        'SHADOW_SCRIPT="$SERVICE_DIR/ghostguard-native-shadow.lua"\n'
        'SHADOW_PIDFILE="$SERVICE_DIR/native-shadow.pid"\n'
        'SHADOW_STATUS="$SERVICE_DIR/native-shadow.status"\n'
        'SHADOW_SPOOL="$SERVICE_DIR/native-shadow-candidates.log"\n'
        'SHADOW_PAUSE="$SERVICE_DIR/native-shadow.pause"\n'
        'SHADOW_RETRY_AT=0\nSHADOW_FAILURES=0\n', "service shadow vars")
s = s.replace("# DCPRO GhostGuard v0.8 persistent service policy",
              "# DCPRO GhostGuard v0.9 persistent service policy")
if "NATIVE_SHADOW=1" not in s:
    s = s.replace("PAUSE_DURING_SLEEP=1\nDESIRED_MODE=AUTO",
                  "PAUSE_DURING_SLEEP=1\nNATIVE_SHADOW=1\nDESIRED_MODE=AUTO", 1)
if "    NATIVE_SHADOW=1" not in s:
    s = s.replace("    PAUSE_DURING_SLEEP=1\n    DESIRED_MODE=AUTO",
                  "    PAUSE_DURING_SLEEP=1\n    NATIVE_SHADOW=1\n    DESIRED_MODE=AUTO", 1)
if "NATIVE_SHADOW)" not in s:
    s = replace_once(s,
        '            PAUSE_DURING_SLEEP) [ "$value" = "0" ] && PAUSE_DURING_SLEEP=0 || PAUSE_DURING_SLEEP=1 ;;\n            DESIRED_MODE)',
        '            PAUSE_DURING_SLEEP) [ "$value" = "0" ] && PAUSE_DURING_SLEEP=0 || PAUSE_DURING_SLEEP=1 ;;\n'
        '            NATIVE_SHADOW) [ "$value" = "0" ] && NATIVE_SHADOW=0 || NATIVE_SHADOW=1 ;;\n'
        '            DESIRED_MODE)', "service config parser")

if "pid_is_shadow()" not in s:
    helper_anchor = "}\n\n# Single instance without relying on flock (not present on every Kindle build)."
    helper = r'''}

pid_is_shadow() {
    pid="$1"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq 'ghostguard-native-shadow.lua'
}

find_luajit() {
    for bin in "$ROOT/koreader/luajit" "$ROOT/koreader/bin/luajit" \
        "$ROOT/extensions/koreader/luajit" "$ROOT/extensions/koreader/bin/luajit"; do
        if [ -x "$bin" ]; then printf '%s\n' "$bin"; return 0; fi
    done
    command -v luajit 2>/dev/null || true
}

stop_shadow() {
    if [ -r "$SHADOW_PIDFILE" ]; then
        spid="$(cat "$SHADOW_PIDFILE" 2>/dev/null || true)"
        if pid_is_shadow "$spid"; then kill "$spid" 2>/dev/null || true; fi
    fi
    rm -f "$SHADOW_PIDFILE" 2>/dev/null || true
}

shadow_backoff() {
    now="$(date +%s 2>/dev/null || echo 0)"
    SHADOW_FAILURES=$((SHADOW_FAILURES + 1))
    delay=30
    [ "$SHADOW_FAILURES" -ge 3 ] 2>/dev/null && delay=300
    if [ "$now" -gt 0 ] 2>/dev/null; then SHADOW_RETRY_AT=$((now + delay)); fi
    log "native shadow exited unexpectedly; retry in ${delay}s (failure $SHADOW_FAILURES)"
}

start_shadow() {
    [ "${ENABLED:-1}" = "1" ] || { stop_shadow; return 0; }
    [ "${NATIVE_SHADOW:-1}" = "1" ] || { stop_shadow; return 0; }
    [ -r "$SHADOW_SCRIPT" ] || return 1
    event="${CONTROLLER_EVENT:-NONE}"
    [ "$event" != "NONE" ] && [ -r "/dev/input/$event" ] || return 1

    if [ -r "$SHADOW_PIDFILE" ]; then
        spid="$(cat "$SHADOW_PIDFILE" 2>/dev/null || true)"
        if pid_is_shadow "$spid"; then return 0; fi
        rm -f "$SHADOW_PIDFILE" 2>/dev/null || true
        shadow_backoff
        return 1
    fi

    now="$(date +%s 2>/dev/null || echo 0)"
    if [ "$now" -gt 0 ] 2>/dev/null && [ "$SHADOW_RETRY_AT" -gt "$now" ] 2>/dev/null; then
        return 1
    fi

    lua="$(find_luajit)"
    [ -n "$lua" ] || return 1
    did="$(tr -cd 'A-Za-z0-9' < /proc/usid 2>/dev/null | tr '[:lower:]' '[:upper:]' || true)"
    [ -n "$did" ] || did="UNKNOWNDEVICE"
    profile="$DATA/profiles/$did.approved.profile"
    "$lua" "$SHADOW_SCRIPT" "/dev/input/$event" "$SHADOW_SPOOL" \
        "$SHADOW_STATUS" "$SHADOW_PAUSE" "$profile" >/dev/null 2>&1 &
    spid=$!
    printf '%s\n' "$spid" > "$SHADOW_PIDFILE" 2>/dev/null || true
    return 0
}

# Single instance without relying on flock (not present on every Kindle build).'''
    s = replace_once(s, helper_anchor, helper, "service shadow helpers")

s = s.replace('cleanup() { rm -f "$PIDFILE" 2>/dev/null || true; }',
              'cleanup() { stop_shadow; rm -f "$SHADOW_PAUSE" "$PIDFILE" 2>/dev/null || true; }', 1)

if 'echo "NATIVE_SHADOW=$NATIVE_SHADOW"' not in s:
    s = replace_once(s,
        '        echo "PAUSE_DURING_SLEEP=$PAUSE_DURING_SLEEP"\n        echo "DESIRED_MODE=${DESIRED_MODE:-AUTO}"',
        '        echo "PAUSE_DURING_SLEEP=$PAUSE_DURING_SLEEP"\n'
        '        echo "NATIVE_SHADOW=$NATIVE_SHADOW"\n'
        '        shadow_pid="$(cat "$SHADOW_PIDFILE" 2>/dev/null || echo 0)"\n'
        '        if ! pid_is_shadow "$shadow_pid"; then shadow_pid=0; fi\n'
        '        echo "NATIVE_SHADOW_PID=$shadow_pid"\n'
        '        echo "NATIVE_FILTER=SHADOW_ONLY"\n'
        '        echo "DESIRED_MODE=${DESIRED_MODE:-AUTO}"', "service status shadow")

if 'start_shadow || true\n    write_status "active" "WAKE"' not in s:
    s = replace_once(s, '    write_status "active" "WAKE"\n}',
        '    SHADOW_RETRY_AT=0\n    rm -f "$SHADOW_PAUSE" 2>/dev/null || true\n'
        '    start_shadow || true\n    write_status "active" "WAKE"\n}', "service wake shadow")

startup = 'state="$(power_state)"\nprev_state="$state"\nlast_heartbeat='
if startup in s:
    s = s.replace(startup,
        'state="$(power_state)"\nprev_state="$state"\nrm -f "$SHADOW_PAUSE" 2>/dev/null || true\n'
        'if is_active_state "$state"; then start_shadow || true; else stop_shadow; fi\nlast_heartbeat=', 1)

s = s.replace('        else\n            write_status "$state" "POWER_TRANSITION"\n        fi',
              '        else\n            stop_shadow\n            write_status "$state" "POWER_TRANSITION"\n        fi', 1)

loop_anchor = '        prev_state="$state"\n    fi\n\n    now="$(date +%s 2>/dev/null || echo 0)"'
if loop_anchor in s:
    s = s.replace(loop_anchor,
        '        prev_state="$state"\n    fi\n\n'
        '    if is_active_state "$state"; then start_shadow || true; else stop_shadow; fi\n\n'
        '    now="$(date +%s 2>/dev/null || echo 0)"', 1)
write(rel, s)


# ---------------------------------------------------------------------------
# Installer
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/install.sh"
s = read(rel)
if 'NATIVE_SHADOW="$SERVICE_DIR/ghostguard-native-shadow.lua"' not in s:
    s = replace_once(s, 'NATIVE_CAPTURE="$SERVICE_DIR/ghostguard-native-capture.sh"',
                     'NATIVE_CAPTURE="$SERVICE_DIR/ghostguard-native-capture.sh"\n'
                     'NATIVE_SHADOW="$SERVICE_DIR/ghostguard-native-shadow.lua"',
                     "installer shadow var")
if '[ -f "system/ghostguard-native-shadow.lua" ]' not in s:
    s = replace_once(s,
        '[ -f "system/ghostguard-native-capture.sh" ] || fail "integrated native diagnostics missing"',
        '[ -f "system/ghostguard-native-capture.sh" ] || fail "integrated native diagnostics missing"\n'
        '[ -f "system/ghostguard-native-shadow.lua" ] || fail "native shadow observer missing"',
        "installer shadow require")
if 'cp -p "system/ghostguard-native-shadow.lua" "$NATIVE_SHADOW"' not in s:
    s = replace_once(s,
        'cp -p "system/ghostguard-native-capture.sh" "$NATIVE_CAPTURE" || fail "cannot install native diagnostic capture"',
        'cp -p "system/ghostguard-native-capture.sh" "$NATIVE_CAPTURE" || fail "cannot install native diagnostic capture"\n'
        'cp -p "system/ghostguard-native-shadow.lua" "$NATIVE_SHADOW" || fail "cannot install native shadow observer"',
        "installer copy shadow")
if 'chmod 644 "$NATIVE_SHADOW"' not in s:
    s = replace_once(s, 'chmod 755 "$SERVICE_SCRIPT" "$NATIVE_CAPTURE" 2>/dev/null || true',
        'chmod 755 "$SERVICE_SCRIPT" "$NATIVE_CAPTURE" 2>/dev/null || true\n'
        'chmod 644 "$NATIVE_SHADOW" 2>/dev/null || true', "installer shadow perms")
s = s.replace("# DCPRO GhostGuard v0.8 persistent service policy",
              "# DCPRO GhostGuard v0.9 persistent service policy")
if "NATIVE_SHADOW=1" not in s:
    s = s.replace("PAUSE_DURING_SLEEP=1\nDESIRED_MODE=AUTO",
                  "PAUSE_DURING_SLEEP=1\nNATIVE_SHADOW=1\nDESIRED_MODE=AUTO", 1)
s = s.replace("PACKAGE_VERSION=0.8.3", "PACKAGE_VERSION=0.9.0")
if "NATIVE_FILTER=SHADOW_ONLY" not in s:
    s = s.replace('NATIVE_INTEGRATED=1\\nINPUT_GRAB=OFF',
                  'NATIVE_INTEGRATED=1\\nNATIVE_SHADOW=1\\nNATIVE_FILTER=SHADOW_ONLY\\nINPUT_GRAB=OFF', 1)
s = s.replace("GhostGuard v0.8.3 installed.", "GhostGuard v0.9.0 installed.")
old_echo = 'echo "GhostGuard Native diagnostics integrated: $NATIVE_CAPTURE"'
new_echo = ('echo "GhostGuard Native diagnostics integrated: $NATIVE_CAPTURE"\n'
            'echo "GhostGuard Native shadow observer: $NATIVE_SHADOW (read-only, event-driven)"')
if old_echo in s and "GhostGuard Native shadow observer:" not in s:
    s = s.replace(old_echo, new_echo, 1)
s = s.replace("Safety: system service input grab/injection are OFF; Protect remains in the tested KOReader bridge.",
              "Safety: Native filter is SHADOW_ONLY; input grab/injection are OFF; actual blocking remains in the tested KOReader bridge.", 1)
s = s.replace("Restart KOReader once after upgrading to v0.8.3.",
              "Restart KOReader once after upgrading to v0.9.0.", 1)
write(rel, s)


# ---------------------------------------------------------------------------
# Build script
# ---------------------------------------------------------------------------
rel = "scripts/build_ghostguard_v080.sh"
s = read(rel)
if 'ghostguard-native-shadow.lua" "$TMP/system/ghostguard-native-shadow.lua' not in s:
    s = replace_once(s,
        'cp "$SRC/system/ghostguard-native-capture.sh" "$TMP/system/ghostguard-native-capture.sh"',
        'cp "$SRC/system/ghostguard-native-capture.sh" "$TMP/system/ghostguard-native-capture.sh"\n'
        'cp "$SRC/system/ghostguard-native-shadow.lua" "$TMP/system/ghostguard-native-shadow.lua"',
        "builder copy shadow")
s = s.replace("grep -q 'version = \"0.8.0\"' \"$PLUGIN/defaults.lua\"",
              "grep -q 'version = \"0.9.0\"' \"$PLUGIN/defaults.lua\"")
s = s.replace("grep -q 'runtime_revision = \"system-service-v1\"' \"$PLUGIN/defaults.lua\"",
              "grep -q 'runtime_revision = \"continuous-learning-shadow-v1\"' \"$PLUGIN/defaults.lua\"")
s = s.replace("grep -q 'GhostGuard v0.8.0' \"$PLUGIN/_meta.lua\"",
              "grep -q 'GhostGuard v0.9.0' \"$PLUGIN/_meta.lua\"")
if "NATIVE_FILTER=SHADOW_ONLY" not in s:
    s = replace_once(s,
        'grep -q \'INPUT_GRAB=OFF\' "$TMP/system/ghostguard-service.sh"',
        'grep -q \'INPUT_GRAB=OFF\' "$TMP/system/ghostguard-service.sh"\n'
        'grep -q \'NATIVE_FILTER=SHADOW_ONLY\' "$TMP/system/ghostguard-service.sh"\n'
        'grep -q \'READ_ONLY_SHADOW\' "$TMP/system/ghostguard-native-shadow.lua"\n'
        'grep -q \'continuous learning v0.9 loaded\' "$PLUGIN/main.lua"',
        "builder safety checks")
s = s.replace('    for f in "$PLUGIN"/*.lua "$PLUGIN"/keys/*.lua; do\n        luajit -b "$f" /dev/null\n    done',
              '    for f in "$PLUGIN"/*.lua "$PLUGIN"/keys/*.lua "$TMP/system/ghostguard-native-shadow.lua"; do\n'
              '        luajit -b "$f" /dev/null\n    done', 1)
write(rel, s)


# ---------------------------------------------------------------------------
# Package + repository manifests
# ---------------------------------------------------------------------------
rel = "packages/ghostguard/source/manifest.json"
data = json.loads(read(rel))
data["version"] = [0, 9, 0]
data["description"] = (
    "GhostGuard v0.9.0 - continuous low-power adaptive profile learning, "
    "read-only system-wide native shadow observation, reliable Library icon, and local-only reporting."
)
write(rel, json.dumps(data, ensure_ascii=False, indent=2) + "\n")

entry = ('        {"url":"packages/ghostguard/artifacts/ghostguard_0.9.0_kindle5-kindlepw2-kindlehf.kpkg",'
         '"version":[0,9,0],"dependencies":[],"supported_platforms":["kindle5","kindlepw2","kindlehf"]},\n')
for rel in ["manifest.v2.json", "manifest.mirror.json", "manifest.json"]:
    s = read(rel)
    if "ghostguard_0.9.0_kindle5-kindlepw2-kindlehf.kpkg" not in s:
        s = replace_once(s, '      "artifacts": [\n', '      "artifacts": [\n' + entry,
                         f"{rel} artifact list")
    s = re.sub(r'GhostGuard v0\.8\.3[^\"]*',
        'GhostGuard v0.9.0 - continuous low-power adaptive learning and read-only native shadow observation; blocking remains fail-open in KOReader while native filtering is validated.',
        s, count=1)
    write(rel, s)

print("v0.9.0 source prepared")
