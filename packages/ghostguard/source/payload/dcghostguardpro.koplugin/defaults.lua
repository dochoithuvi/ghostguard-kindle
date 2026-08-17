return {
    version = "0.6.13",
    default_mode = "OBSERVE_ONLY",
    calibration_mode = "CALIBRATION",
    protect_mode = "PROTECT_PROFILE",

    data_dir = "/mnt/us/.dcpro_ghostguard",
    report_dir = "/mnt/us/.dcpro_ghostguard/reports",
    profile_dir = "/mnt/us/.dcpro_ghostguard/profiles",
    cloud_outbox_dir = "/mnt/us/.dcpro_ghostguard/cloud_outbox",
    cloud_target_file = "/mnt/us/.dcpro_ghostguard/cloud_target.txt",
    cloud_status_file = "/mnt/us/.dcpro_ghostguard/CLOUD_UPLOAD_STATUS.txt",
    cloud_lock_dir = "/mnt/us/.dcpro_ghostguard/CLOUD_UPLOAD.lock",
    cloud_endpoint = "https://script.google.com/macros/s/AKfycbw2Ex8MShC1eHmv3_rN1HN3P-Wkhd3G2Y6R5BTsxc5jGTf-ysifCDAOas5gbknajHYgKQ/exec",
    cloud_token_file = "/mnt/us/documents/dochoithuvi_drive_token.conf",
    cloud_max_bytes = 8388608,
    cloud_compress_threshold = 2000000,

    exit_reason_detail_file = "/mnt/us/.dcpro_ghostguard/EXIT_REASON_DETAIL.txt",
    koreader_traceback_file = "/mnt/us/.dcpro_ghostguard/KOReader_EXIT_TRACEBACK.txt",
    exit_history_file = "/mnt/us/.dcpro_ghostguard/EXIT_HISTORY.log",

    license_required = true,
    license_recheck_seconds = 30,
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

    drive_root_folder_id = "1h26N0Gtb1PgV2SYCkzU_ue2iwFrtwnah",
    drive_root_folder_url = "https://drive.google.com/drive/folders/1h26N0Gtb1PgV2SYCkzU_ue2iwFrtwnah",

    customer_autolearn_default = true,
    customer_ready_notice_after_seconds = 180,
    customer_probation_sessions = 2,

    auto_start_delay_seconds = 5,
    max_observe_session_seconds = 1800,
    max_calibration_session_seconds = 1800,
    max_protect_session_seconds = 21600,
    flush_every_frames = 128,

    -- The optional touch wrapper is needed only for real PROTECT mode.
    -- Observe/Calibration must work even when SimpleUI/KOReader does not
    -- expose the touch wrapper API.
    protect_wrapper_all_modes = false,
    engine_keep_alive_on_widget_close = true,
    resume_restart_delay_seconds = 4,

    burst_window_us = 250000,
    burst_start_count = 5,
    teleport_window_us = 50000,
    teleport_distance = 350,
    zero_life_us = 1500,

    protect_supported_models = {
        KindleBasic4 = true,
    },

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
}
