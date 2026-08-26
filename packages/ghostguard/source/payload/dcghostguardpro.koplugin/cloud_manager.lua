local CloudManager = {}
CloudManager.__index = CloudManager

-- Public GhostGuard builds intentionally do not ship an upload credential.
-- The old uploader required /mnt/us/documents/dochoithuvi_drive_token.conf,
-- which made the UI expose a feature that could not work on a clean install.
-- Keep this small compatibility object so older core code can call the same
-- methods, but never require or read a private .conf file in public builds.
function CloudManager:new(config, storage, plugin_dir)
    return setmetatable({
        config = config,
        storage = storage,
        plugin_dir = plugin_dir,
        last_start_wall = 0,
        last_error = nil,
    }, self)
end

function CloudManager:isBusy()
    return false
end

function CloudManager:start()
    self.last_error = "CLOUD_DISABLED_PUBLIC_BUILD"
    return false,
        "Gửi Cloud đã được tắt trong bản public. Báo cáo vẫn được lưu cục bộ trên Kindle; không cần file .conf."
end

function CloudManager:statusText()
    return table.concat({
        "DCPRO_GHOSTGUARD_CLOUD_DISABLED_V1",
        "STATUS=DISABLED",
        "DETAIL=Public build stores reports locally and does not require a Cloud credential file.",
    }, "\n")
end

return CloudManager
