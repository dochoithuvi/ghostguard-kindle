from pathlib import Path

ROOT = Path('.')
P = ROOT / 'packages/ghostguard/source/payload/dcghostguardpro.koplugin'

# defaults.lua: mark the hotfix revision and add safe checkpoint/watchdog knobs.
p = P / 'defaults.lua'
s = p.read_text()
s = s.replace('    version = "0.6.15",\n', '    version = "0.6.15",\n    runtime_revision = "calibration-flow-v2",\n', 1)
s = s.replace('    calibration_min_learning_seconds = 180,\n', '    calibration_min_learning_seconds = 180,\n    calibration_checkpoint_contacts = 5,\n    calibration_input_watchdog_seconds = 30,\n', 1)
s = s.replace('    -- IMPORTANT: SimpleUI/KOReader input bridge is required only for real\n    -- PROTECT mode. Observe/Calibration must never fail merely because the\n    -- device lacks the optional touch wrapper API.\n', '    -- Raw-event observation is required in Observe/Calibration/Protect.\n    -- Only the touch suppression wrapper is Protect-only. Learning therefore\n    -- listens to input without ever replacing or blocking KOReader gestures.\n', 1)
p.write_text(s)

# profile_manager.lua: checkpoint progress during learning and preserve weak
# clusters between sessions. Only approved GHOST_CLUSTER profiles retain
# trusted clusters; BASELINE approval strips coordinates completely.
p = P / 'profile_manager.lua'
s = p.read_text()
needle = '''function ProfileManager:addContact(sample)\n    if not self.calibration then return false, "calibration not active" end\n    -- Count every completed touch, not only faults. This is the healthy-device\n    -- baseline signal used to finish learning even when ghost events are rare.\n    self.calibration.total_contacts = self.calibration.total_contacts + 1\n    if not sample or not sample.learnable then return false, "not learnable" end\n    if sample.x == nil and sample.y == nil then return false, "no coordinates" end\n\n    self.calibration.suspect_contacts = self.calibration.suspect_contacts + 1\n'''
replacement = '''function ProfileManager:checkpoint()\n    if not self.calibration then return false, "calibration not active" end\n    local status = self:calibrationStatus()\n    local clusters = {}\n    for _, cluster in ipairs(self.calibration.clusters or {}) do\n        local copied = copy_cluster(cluster)\n        copied.confidence = self:confidence(copied)\n        clusters[#clusters + 1] = copied\n    end\n    local profile = {\n        status = "PENDING",\n        profile_kind = status.profile_kind,\n        created_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),\n        learning_seconds = status.learning_seconds,\n        total_contacts = status.total_contacts,\n        suspect_contacts = status.suspect_contacts,\n        clusters = clusters,\n        ready = status.ready,\n    }\n    local ok, err = self.storage:writeAtomic(self.pending_path, self:serialize(profile, "PENDING"))\n    if not ok then return false, err end\n    self.pending = profile\n    return true, profile\nend\n\nfunction ProfileManager:addContact(sample)\n    if not self.calibration then return false, "calibration not active" end\n    -- Count every completed touch, not only faults. This is the healthy-device\n    -- baseline signal used to finish learning even when ghost events are rare.\n    self.calibration.total_contacts = self.calibration.total_contacts + 1\n    local checkpoint_every = math.max(1, tonumber(self.config.calibration_checkpoint_contacts) or 5)\n    local should_checkpoint = (self.calibration.total_contacts % checkpoint_every) == 0\n    if not sample or not sample.learnable then\n        if should_checkpoint then self:checkpoint() end\n        return false, "not learnable"\n    end\n    if sample.x == nil and sample.y == nil then\n        if should_checkpoint then self:checkpoint() end\n        return false, "no coordinates"\n    end\n\n    self.calibration.suspect_contacts = self.calibration.suspect_contacts + 1\n'''
if needle not in s:
    raise SystemExit('profile addContact anchor missing')
s = s.replace(needle, replacement, 1)
s = s.replace('''    cluster.base_score_sum = cluster.base_score_sum + (tonumber(sample.base_score) or 0)\n    return true, cluster\nend\n''', '''    cluster.base_score_sum = cluster.base_score_sum + (tonumber(sample.base_score) or 0)\n    if should_checkpoint then self:checkpoint() end\n    return true, cluster\nend\n''', 1)

old_finalize = '''function ProfileManager:finalize()\n    if not self.calibration then return false, "calibration not active" end\n    local selected = {}\n    for _, cluster in ipairs(self.calibration.clusters) do\n        if cluster.count >= self.config.calibration_keep_cluster_samples then\n            cluster.confidence = self:confidence(cluster)\n            selected[#selected + 1] = cluster\n        end\n    end\n    table.sort(selected, function(a, b) return (a.count or 0) > (b.count or 0) end)\n    while #selected > self.config.calibration_max_clusters do table.remove(selected) end\n\n    local strongest = selected[1] and selected[1].count or 0\n    local total = tonumber(self.calibration.total_contacts) or 0\n    local suspects = tonumber(self.calibration.suspect_contacts) or 0\n    local learned_seconds = learning_seconds(self.calibration)\n    local time_ready = learned_seconds >= (tonumber(self.config.calibration_min_learning_seconds) or 0)\n    local ghost_evidence_ready = suspects >= self.config.calibration_min_suspect_samples\n        and strongest >= self.config.calibration_min_cluster_samples\n    local ghost_ready = ghost_evidence_ready and time_ready\n    local baseline_ready = total >= (tonumber(self.config.calibration_min_total_contacts) or math.huge)\n        and time_ready\n    local ready = ghost_ready or baseline_ready\n    local profile_kind = ghost_ready and "GHOST_CLUSTER"\n        or (baseline_ready and "BASELINE" or "LEARNING")\n    local profile = {\n        status = "PENDING",\n        profile_kind = profile_kind,\n        created_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),\n        learning_seconds = learned_seconds,\n        total_contacts = total,\n        suspect_contacts = suspects,\n        clusters = selected,\n        ready = ready,\n    }\n    local ok, err = self.storage:writeAtomic(self.pending_path, self:serialize(profile, "PENDING"))\n    self.calibration = nil\n    if not ok then return false, err end\n    self.pending = profile\n    return true, profile\nend\n'''
new_finalize = '''function ProfileManager:finalize()\n    if not self.calibration then return false, "calibration not active" end\n    -- Finalizing a learning session must preserve ALL candidate clusters so a\n    -- suspend/resume cycle cannot erase a 1-3 sample cluster before it grows.\n    -- Trust filtering happens only when a READY profile is approved.\n    local ok, profile_or_err = self:checkpoint()\n    local profile = ok and profile_or_err or nil\n    self.calibration = nil\n    if not ok then return false, profile_or_err end\n    self.pending = profile\n    return true, profile\nend\n'''
if old_finalize not in s:
    raise SystemExit('profile finalize anchor missing')
s = s.replace(old_finalize, new_finalize, 1)

old_approve = '''function ProfileManager:approvePending()\n    if not self:hasPendingReady() then return false, "Profile chưa đủ dữ liệu để bảo vệ an toàn" end\n    local approved = self.pending\n    approved.status = "APPROVED"\n    local ok, err = self.storage:writeAtomic(self.approved_path, self:serialize(approved, "APPROVED"))\n    if not ok then return false, err end\n    self.approved = approved\n    self.pending = nil\n    self.storage:removeExact(self.pending_path)\n    return true, self.approved_path\nend\n'''
new_approve = '''function ProfileManager:approvePending()\n    if not self:hasPendingReady() then return false, "Profile chưa đủ dữ liệu để bảo vệ an toàn" end\n    local approved = {\n        status = "APPROVED",\n        profile_kind = self.pending.profile_kind,\n        created_utc = self.pending.created_utc,\n        learning_seconds = self.pending.learning_seconds,\n        total_contacts = self.pending.total_contacts,\n        suspect_contacts = self.pending.suspect_contacts,\n        ready = true,\n        clusters = {},\n    }\n    if approved.profile_kind == "GHOST_CLUSTER" then\n        for _, cluster in ipairs(self.pending.clusters or {}) do\n            if (tonumber(cluster.count) or 0) >= self.config.calibration_keep_cluster_samples then\n                local copied = copy_cluster(cluster)\n                copied.confidence = self:confidence(copied)\n                approved.clusters[#approved.clusters + 1] = copied\n            end\n        end\n        table.sort(approved.clusters, function(a, b) return (a.count or 0) > (b.count or 0) end)\n        while #approved.clusters > self.config.calibration_max_clusters do table.remove(approved.clusters) end\n        if #approved.clusters == 0 then return false, "Không còn cluster đủ tin cậy để duyệt" end\n    end\n    local ok, err = self.storage:writeAtomic(self.approved_path, self:serialize(approved, "APPROVED"))\n    if not ok then return false, err end\n    self.approved = approved\n    self.pending = nil\n    self.storage:removeExact(self.pending_path)\n    return true, self.approved_path\nend\n'''
if old_approve not in s:
    raise SystemExit('profile approve anchor missing')
s = s.replace(old_approve, new_approve, 1)
p.write_text(s)

# ghostguard.lua: raw-event hook is mandatory for observation/calibration, while
# the actual touch wrapper remains Protect-only.
p = P / 'ghostguard.lua'
s = p.read_text()
old = '''    if protect or self.config.protect_wrapper_all_modes == true then\n        local bridge_ok, bridge_err = self:ensureInputBridge()\n        if not bridge_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(bridge_err)\n        end\n        self.protect_enabled = protect\n        local wrapper_ok, wrapper_err = self:ensureProtectWrapper()\n        if not wrapper_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(wrapper_err)\n        end\n        self.wrapper_mode = protect and "PROTECT" or "PASS_THROUGH"\n    end\n'''
new = '''    -- Every mode that claims to observe input must own a raw-event hook.\n    -- Calibration previously skipped this bridge, so its wall clock advanced\n    -- while TouchObserver received zero events. The hook is observation-only;\n    -- handleTouchEv is replaced only below when Protect explicitly needs it.\n    local bridge_ok, bridge_err = self:ensureInputBridge()\n    if not bridge_ok then\n        self.protect_enabled = false\n        return false, (calibrate and "CALIBRATION_INPUT: " or "RAW_EVENT_BRIDGE: ") .. tostring(bridge_err)\n    end\n    if protect or self.config.protect_wrapper_all_modes == true then\n        self.protect_enabled = protect\n        local wrapper_ok, wrapper_err = self:ensureProtectWrapper()\n        if not wrapper_ok then\n            self.protect_enabled = false\n            return false, "PROTECT_WRAPPER: " .. tostring(wrapper_err)\n        end\n        self.wrapper_mode = protect and "PROTECT" or "PASS_THROUGH"\n    else\n        self.protect_wrapper_installed = false\n        self.wrapper_mode = "NONE"\n    end\n'''
if old not in s:
    raise SystemExit('ghostguard start bridge anchor missing')
s = s.replace(old, new, 1)

marker = 'function GhostGuard:flush() if self.session then self.session:flush() end end\n'
insert = '''function GhostGuard:inputLearningStatus()\n    local stats = self.observer and self.observer:getStats() or {}\n    return {\n        hook_installed = self.hook_installed == true,\n        raw_events = tonumber(stats.raw_events) or 0,\n        frames = tonumber(stats.frames) or 0,\n        contact_ends = tonumber(stats.ends) or 0,\n    }\nend\n\n'''
if marker not in s:
    raise SystemExit('ghostguard flush anchor missing')
s = s.replace(marker, insert + marker, 1)
s = s.replace('''        "DCPRO GhostGuard " .. self.config.version,\n''', '''        "DCPRO GhostGuard " .. self.config.version .. " / " .. tostring(self.config.runtime_revision or "legacy"),\n''', 1)
p.write_text(s)

# main.lua: resume Calibration after suspend and never present a zero-event
# session as healthy learning.
p = P / 'main.lua'
s = p.read_text()
old_start_tail = '''    if mode == self.config.calibration_mode then\n        show(_("Đang học cách khách sử dụng máy.\\nHãy đọc và thao tác bình thường; GhostGuard chưa chặn cảm ứng.\\nPhiên: ") .. tostring(result), 8)\n    elseif mode == self.config.protect_mode then\n'''
new_start_tail = '''    if mode == self.config.calibration_mode then\n        show(_("Đang học cách khách sử dụng máy.\\nHãy đọc và thao tác bình thường; GhostGuard chưa chặn cảm ứng.\\nPhiên: ") .. tostring(result), 8)\n        UIManager:scheduleIn(self.config.calibration_input_watchdog_seconds or 30, function()\n            if not self.guard or not self.guard:isCalibrating() then return end\n            local st = self.guard:inputLearningStatus()\n            if not st.hook_installed then\n                self.guard:stop("calibration-input-missing")\n                show(_("GhostGuard đã dừng học vì không gắn được bộ nghe cảm ứng. Không có tiến độ giả được lưu."), 12)\n            elseif st.raw_events == 0 then\n                show(_("GhostGuard đang học nhưng chưa nhận sự kiện cảm ứng nào. Hãy chạm/lật vài trang; nếu bộ đếm vẫn không tăng, mở Trạng thái GhostGuard để kiểm tra."), 10)\n            end\n        end)\n    elseif mode == self.config.protect_mode then\n'''
if old_start_tail not in s:
    raise SystemExit('main startMode anchor missing')
s = s.replace(old_start_tail, new_start_tail, 1)

s = s.replace('''    if self.guard:profileLiveReady() then return "GhostGuard: Hoàn tất thiết lập" end\n    return "GhostGuard: Bắt đầu học profile"\nend\n''', '''    if self.guard:profileLiveReady() then return "GhostGuard: Hoàn tất thiết lập" end\n    if self.guard.profiles and self.guard.profiles.pending then return "GhostGuard: Tiếp tục học profile" end\n    return "GhostGuard: Bắt đầu học profile"\nend\n''', 1)

old_suspend = '''function DCPROGhostGuard:onSuspend()\n    if not self.guard then return end\n    self._resume_protect_after_suspend = self.guard:isProtecting() or (self.guard:isAutoProtectEnabled() and self.guard:profileApproved())\n    self.guard:stop("suspend-fail-open")\nend\n\nfunction DCPROGhostGuard:onResume()\n    if not self.guard then return end\n    local should_resume = self._resume_protect_after_suspend == true\n    self._resume_protect_after_suspend = false\n    if not should_resume then return end\n    UIManager:scheduleIn(4, function()\n        if not self.guard or self.guard:isRunning() or self.guard:isSafeMode() then return end\n        local licensed = self.guard:licenseValid(true)\n        if not licensed or not self.guard:profileApproved() or not self.guard:protectSupported() then return end\n        local ok, result = self.guard:start(self.config.protect_mode, "resume-auto-protect")\n        if not ok then logger.warn("DCPRO GhostGuard resume Protect skipped:", result) end\n    end)\nend\n'''
new_suspend = '''function DCPROGhostGuard:onSuspend()\n    if not self.guard then return end\n    self._resume_calibration_after_suspend = self.guard:isCalibrating()\n    self._resume_protect_after_suspend = self.guard:isProtecting() or (self.guard:isAutoProtectEnabled() and self.guard:profileApproved())\n    self.guard:stop("suspend-fail-open")\nend\n\nfunction DCPROGhostGuard:onResume()\n    if not self.guard then return end\n    local resume_calibration = self._resume_calibration_after_suspend == true\n    local resume_protect = self._resume_protect_after_suspend == true\n    self._resume_calibration_after_suspend = false\n    self._resume_protect_after_suspend = false\n    if not resume_calibration and not resume_protect then return end\n    UIManager:scheduleIn(self.config.resume_restart_delay_seconds or 4, function()\n        if not self.guard or self.guard:isRunning() or self.guard:isSafeMode() then return end\n        local licensed = self.guard:licenseValid(true)\n        if not licensed then return end\n        if resume_calibration and not self.guard:profileApproved() then\n            if self.guard:profileLiveReady() then\n                show(_("GhostGuard đã học đủ dữ liệu trong phiên trước. Mở Tools và chọn Hoàn tất thiết lập bảo vệ."), 10)\n                return\n            end\n            local ok, result = self.guard:start(self.config.calibration_mode, "resume-customer-learning")\n            if not ok then logger.warn("DCPRO GhostGuard resume Calibration skipped:", result) end\n            return\n        end\n        if resume_protect and self.guard:profileApproved() and self.guard:protectSupported() then\n            local ok, result = self.guard:start(self.config.protect_mode, "resume-auto-protect")\n            if not ok then logger.warn("DCPRO GhostGuard resume Protect skipped:", result) end\n        end\n    end)\nend\n'''
if old_suspend not in s:
    raise SystemExit('main suspend/resume anchor missing')
s = s.replace(old_suspend, new_suspend, 1)
p.write_text(s)

# OneClick: same semver hotfix, but verify the new runtime revision so a stale
# 0.6.15 installation can never be mistaken for the repaired runtime.
p = ROOT / 'DCPRO_GhostGuard_OneClick_Installer_v12.1.sh'
s = p.read_text()
s = s.replace('GG_EXPECT=0.6.15\n', 'GG_EXPECT=0.6.15\nGG_RUNTIME_REVISION=calibration-flow-v2\n', 1)
old = 'has_gg_expected(){ T="$(gg_plugin_target 2>/dev/null || true)"; [ -n "$T" ] && grep -Fq "version = \\\"$GG_EXPECT\\\"" "$T/defaults.lua" 2>/dev/null; }\n'
new = 'has_gg_expected(){ T="$(gg_plugin_target 2>/dev/null || true)"; [ -n "$T" ] && grep -Fq "version = \\\"$GG_EXPECT\\\"" "$T/defaults.lua" 2>/dev/null && grep -Fq "runtime_revision = \\\"$GG_RUNTIME_REVISION\\\"" "$T/defaults.lua" 2>/dev/null; }\n'
if old not in s:
    raise SystemExit('OneClick expected-runtime anchor missing')
s = s.replace(old, new, 1)
s = s.replace('log "Expected: GhostGuard $GG_EXPECT + KOReader safety guards + latest SimpleUI Tools bridge"', 'log "Expected: GhostGuard $GG_EXPECT/$GG_RUNTIME_REVISION + KOReader safety guards + latest SimpleUI Tools bridge"', 1)
p.write_text(s)

# Build script: preserve semver, enforce hotfix marker and run a regression test
# that proves Calibration owns a raw-event hook but does NOT replace handleTouchEv.
p = ROOT / 'scripts/build_artifact_v0612.sh'
s = p.read_text()
s = s.replace('[ -n "$VERSION" ] || VERSION=0.6.15\n', '[ -n "$VERSION" ] || VERSION=0.6.15\n', 1)
s = s.replace('''grep -q 'version = "0.6.15"' "$TMP/payload/dcghostguardpro.koplugin/defaults.lua"\n''', '''grep -q 'version = "0.6.15"' "$TMP/payload/dcghostguardpro.koplugin/defaults.lua"\ngrep -q 'runtime_revision = "calibration-flow-v2"' "$TMP/payload/dcghostguardpro.koplugin/defaults.lua"\ngrep -q 'CALIBRATION_INPUT:' "$TMP/payload/dcghostguardpro.koplugin/ghostguard.lua"\ngrep -q '_resume_calibration_after_suspend' "$TMP/payload/dcghostguardpro.koplugin/main.lua"\ngrep -q 'function ProfileManager:checkpoint()' "$TMP/payload/dcghostguardpro.koplugin/profile_manager.lua"\n''', 1)

regression = r'''# Regression: Calibration must receive real raw events without installing the Protect wrapper.
cat > "$TMP/test_calibration_runtime.lua" <<'LUA'
package.preload["device"] = function()
    local input = {
        handleTouchEv = function() return { "koreader-result" } end,
        registerEventAdjustHook = function(self, fn) self._test_hook = fn end,
    }
    return {
        model = "KindleBasic4",
        getModel = function() return "KindleBasic4" end,
        screen = { getWidth = function() return 1072 end, getHeight = function() return 1448 end },
        input = input,
    }
end
local root = os.getenv("GG_TEST_ROOT")
local config = dofile(root .. "/defaults.lua")
local TouchObserver = dofile(root .. "/touch_observer.lua")
local ProfileManager = dofile(root .. "/profile_manager.lua")
local GhostGuard = dofile(root .. "/ghostguard.lua")
local Device = require("device")

local Storage = {}; Storage.__index = Storage
function Storage:new() return setmetatable({ files = {} }, self) end
function Storage:ensureLayout() return true end
function Storage:archiveStaleMarker() return false end
function Storage:readFile(p) return self.files[p] end
function Storage:writeAtomic(p,v) self.files[p]=v; return true end
function Storage:removeExact(p) self.files[p]=nil; return true end
function Storage:touch(p,v) self.files[p]=v or ""; return true end
function Storage:fileExists(p) return self.files[p] ~= nil end
function Storage:isSafeMode() return false end
function Storage:openSession()
    local s = {}
    for _, n in ipairs({"writeCalibration","writeCandidate","writeEvent","writeContact","writeAction","flush"}) do s[n]=function() end end
    s.close=function() end
    return s
end
function Storage:prepareCloudOutbox() return false end
function Storage:setSafeMode() return true end

local License = {}; License.__index = License
function License:new() return setmetatable({}, self) end
function License:check() return true, "OK" end
function License:statusText() return "OK" end
function License:syncOnline() return true end
function License:activationHelp() return "" end
local Cloud = {}; Cloud.__index = Cloud
function Cloud:new() return setmetatable({}, self) end
function Cloud:statusText() return "OK" end
function Cloud:start() return true end
function Cloud:isBusy() return false end

local g = GhostGuard:new(config, Storage, TouchObserver, ProfileManager, License, Cloud, root)
local original_handle = Device.input.handleTouchEv
assert(g:start(config.calibration_mode, "ci-calibration"))
assert(g.hook_installed == true, "calibration did not install raw-event hook")
assert(type(Device.input._test_hook) == "function", "raw hook callback missing")
assert(Device.input.handleTouchEv == original_handle, "calibration must not replace handleTouchEv")
assert(g.protect_wrapper_installed == false, "calibration installed protect wrapper")

local hook = Device.input._test_hook
local t = os.time()
local function ev(tp, code, value, offset) hook(Device.input, { type=tp, code=code, value=value, time=t + offset }) end
for i=1,40 do
    local base = i * 0.01
    ev(3,47,0,base)
    ev(3,57,i,base+0.001)
    ev(3,53,300+(i%5),base+0.002)
    ev(3,54,500,base+0.003)
    ev(0,0,0,base+0.004)
    ev(3,57,-1,base+0.005)
    ev(0,0,0,base+0.006)
end
local st = g.profiles:calibrationStatus()
assert(st.total_contacts == 40, "completed touches were not counted: " .. tostring(st.total_contacts))
g.profiles.calibration.started_wall = os.time() - 180
st = g.profiles:calibrationStatus()
assert(st.baseline_ready == true, "baseline did not become ready")
local inputst = g:inputLearningStatus()
assert(inputst.raw_events > 0 and inputst.contact_ends == 40, "observer stats did not move")
assert(g:stop("ci-stop"))
assert(g.profiles.pending and g.profiles.pending.total_contacts == 40, "finalized progress missing")
print("CALIBRATION_RUNTIME_FLOW_PASS")
LUA
GG_TEST_ROOT="$TMP/payload/dcghostguardpro.koplugin" luajit "$TMP/test_calibration_runtime.lua" | grep -q CALIBRATION_RUNTIME_FLOW_PASS
'''
anchor = 'tar -C "$TMP" -czf "$PKG" manifest.json payload install.sh launch.sh scriptlets assets\n'
if anchor not in s:
    raise SystemExit('build tar anchor missing')
s = s.replace(anchor, regression + anchor, 1)
p.write_text(s)

print('CALIBRATION_FIX_APPLIED')
