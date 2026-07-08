local win = require 'win-utils'

local M = {}

-- [API] 系统安装/修复完成后的安全结束流程
-- 确保数据刷入磁盘，避免掉电数据丢失
function M.finalize_install(target_drive_letter)
    print("=== Finalizing Installation ===")
    local result = {
        ok = true,
        task = 'shutdown_cleanup',
        target_drive_letter = target_drive_letter,
        flushed = false,
        dismounted = false,
        synced = false,
        warnings = {},
    }

    -- 1. [关键] 卸载所有挂载的注册表 Hive
    -- 如果你在安装过程中 reg load 过目标系统的注册表，必须先卸载！
    -- win.reg.unload_hive("HKLM\\TempSystem") 
    
    -- 2. [关键] 强制刷新目标卷
    local path = target_drive_letter -- 例如 "C:"
    print("Flushing buffers for " .. path)
    local ok, flush_result = win.disk.volume.flush_and_dismount(path)
    if ok then
        print("Volume dismounted successfully (Clean State).")
        result.flushed = true
        result.dismounted = true
    else
        local detail = flush_result
        print("Warning: Flush/dismount incomplete: " .. tostring(detail and detail.dismount_error or detail))
        table.insert(result.warnings, detail)
        result.flushed = detail and detail.flushed or false
        result.dismounted = detail and detail.dismounted or false
    end

    -- 3. 全局 Sync (查漏补缺)
    win.disk.sync()
    result.synced = true
    
    print("Disk data persisted.")
    return result
end

return M
