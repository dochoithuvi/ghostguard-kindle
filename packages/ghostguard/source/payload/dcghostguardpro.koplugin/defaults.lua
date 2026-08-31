-- Legacy OneClick compatibility anchors. Comments only; 0.9.2 is the active runtime:
-- version = "0.6.17"
-- runtime_revision = "calibration-flow-v2"
return {
    version = "0.9.2",
    runtime_revision = "mtguard5-adaptive-v3-stable",
    default_mode = "OBSERVE_ONLY",
    calibration_mode = "CALIBRATION",
    protect_mode = "PROTECT_PROFILE",

    data_dir = "/mnt/us/.dcpro_ghostguard",
    report_dir = "/mnt/us/.dcpro_ghostguard/reports",
    profile_dir = "/mnt/us/.dcpro_ghostguard/profiles",

    exit_reason_detail_file = "/mnt/us/.dcpro_ghostguard/EXIT_REASON_DETAIL.txt",
    koreader_traceback_file = "/mnt/us/.dcpro_ghostguard/KOReader_EXIT_TRACEBACK.txt",
    exit_history_file = "/mnt/us/.dcpro_ghostguard/EXIT_HISTORY.log",

    license_required = true,
    license_recheck_seconds = 30,
    license_clock_rollback_tolerance_seconds = 300,
    allow_legacy_license_migration = false,
    legacy_license_paths = {},

    online_license_enabled = true,
    online_license_registry_url = "https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/licenses/licenses.json",
    online_license_signature_url = "https://raw.githubusercontent.com/dochoithuvi/ghostguard-kindle/main/licenses/licenses.sig",
    online_license_registry_mirror_url = "https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/licenses/licenses.json",
    online_license_signature_mirror_url = "https://cdn.jsdelivr.net/gh/dochoithuvi/ghostguard-kindle@main/licenses/licenses.sig",
    online_license_cache_json = "/mnt/us/.dcpro_ghostguard/online_licenses.json",
    online_license_cache_sig = "/mnt/us/.dcpro_ghostguard/online_licenses.sig",
    online_license_sync_state = "/mnt/us/.dcpro_ghostguard/online_license_sync_state",
    online_license_grace_seconds = 604800,
    online_license_connect_timeout = 5,
    online_license_total_timeout = 12,

    run_marker = "/mnt/us/.dcpro_ghostguard/RUNNING",
    launch_once_marker = "/mnt/us/.dcpro_ghostguard/LAUNCH_ONCE",
    auto_protect_marker = "/mnt/us/.dcpro_ghostguard/AUTO_PROTECT",
    customer_setup_marker = "/mnt/us/.dcpro_ghostguard/CUSTOMER_SETUP",
    customer_profile_ready_marker = "/mnt/us/.dcpro_ghostguard/PROFILE_READY",
    probation_marker = "/mnt/us/.dcpro_ghostguard/PROBATION_REMAINING",
    safe_mode_paths = {
        "/mnt/us/.dcpro_ghostguard/SAFE_MODE",
        "/mnt/us/koreader/dcpro/SAFE_MODE",
    },

    -- v0.8 system supervisor. It owns boot/power/controller lifecycle only.
    -- It never grabs/injects evdev; KOReader remains the touch suppression host.
    system_service_dir = "/mnt/us/.dcpro_ghostguard/service",
    system_service_autostart_default = true,
    system_service_resume_after_wake_default = true,
    system_service_pause_during_sleep_default = true,
    system_service_controller_change_fail_open = true,
    system_service_resume_retry_delays = { 2, 4, 8, 12 },

    customer_autolearn_default = true,
    customer_ready_notice_after_seconds = 180,
    customer_probation_sessions = 2,

    auto_start_delay_seconds = 5,
    max_observe_session_seconds = 1800,
    max_calibration_session_seconds = 1800,
    max_protect_session_seconds = 21600,
    flush_every_frames = 128,

    -- Raw-event observation is required in Observe/Calibration/Protect.
    -- Only the touch suppression wrapper is Protect-only. Learning therefore
    -- listens to input without ever replacing or blocking KOReader gestures.
    protect_wrapper_all_modes = false,
    engine_keep_alive_on_widget_close = true,
    resume_restart_delay_seconds = 4,

    burst_window_us = 250000,
    burst_start_count = 5,
    teleport_window_us = 50000,
    teleport_distance = 350,
    zero_life_us = 1500,

    -- Protect is no longer restricted to a model allowlist. Keep the same
    -- lookup contract used by GhostGuard:protectSupported(), but return true
    -- for every KOReader-reported Kindle model (including future model IDs).
    protect_supported_models = setmetatable({}, {
        __index = function() return true end,
    }),

    weak_low_touch_major = 20,
    weak_short_lifetime_us = 100000,
    weak_incomplete_lifetime_us = 250000,
    weak_max_path_px = 55,
    weak_extreme_edge_px = 24,
    weak_near_edge_px = 80,
    calibration_min_base_score = 5,

    calibration_cluster_radius_px = 96,
    calibration_min_suspect_samples = 12,
    calibration_min_cluster_samples = 5,
    calibration_keep_cluster_samples = 4,
    calibration_max_clusters = 8,
    calibration_profile_padding_x = 36,
    calibration_profile_padding_y = 56,
    -- A healthy device may produce very few ghost candidates. Learning can
    -- therefore complete as a conservative BASELINE after both enough normal
    -- completed touches and enough cumulative learning time across sessions.
    calibration_min_total_contacts = 40,
    calibration_min_learning_seconds = 180,
    calibration_checkpoint_contacts = 5,
    calibration_input_watchdog_seconds = 30,

    protect_min_base_score = 4,
    protect_suspect_score = 5,
    protect_drop_score = 8,
    protect_burst_window_us = 1200000,
    protect_burst_count = 3,
    protect_quarantine_seconds = 0,
    protect_max_blocks_per_minute = 24,
    protect_probation_max_blocks_per_minute = 8,

    adaptive_profiles_enabled = true,
    adaptive_candidate_min_suspects = 8,
    adaptive_candidate_min_cluster = 3,
    adaptive_learning_during_protect = true,
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

    -- Local Adaptive v3: external diagnostics + strict fast promotion for
    -- repeated malformed ghost contacts. Existing normal promotion remains.
    adaptive_external_status_path = "/mnt/us/GhostGuard_Reports/ContinuousLearning_Status.txt",
    adaptive_external_changes_path = "/mnt/us/GhostGuard_Reports/ContinuousLearning_Changes.log",
    adaptive_external_profile_snapshot_path = "/mnt/us/GhostGuard_Reports/ActiveProfile_AutoLearned.txt",
    adaptive_external_report_seconds = 10,
    adaptive_fast_promotion_enabled = true,
    adaptive_fast_promotion_min_cluster = 3,
    adaptive_fast_promotion_min_confidence = 0.80,
    adaptive_fast_promotion_min_base_score = 9,
    native_shadow_enabled = true,
}
