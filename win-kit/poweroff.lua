local win = require 'win-utils'

local M = {}

-- [API] 系统安装/修复完成后的安全结束流程
-- 确保数据刷入磁盘，避免掉电数据丢失
function M.finalize_install(target_drive_letter)
    print("=== Finalizing Installation ===")

    -- 1. [关键] 卸载所有挂载的注册表 Hive
    -- 如果你在安装过程中 reg load 过目标系统的注册表，必须先卸载！
    -- win.reg.unload_hive("HKLM\\TempSystem") 
    
    -- 2. [关键] 强制刷新目标卷
    local path = target_drive_letter -- 例如 "C:"
    local hVol = win.disk.volume.open(path, true) --以此读写方式打开卷
    if hVol then
        print("Flushing buffers for " .. path)
        local kernel32 = require 'ffi.req' 'Windows.sdk.kernel32'
        
        -- 2.1 发送 Flush 指令
        kernel32.FlushFileBuffers(hVol:get())
        
        -- 2.2 [核弹级保险] 强制卸载文件系统 (Dismount)
        -- 这会强制断开所有打开的文件句柄，确保文件系统元数据（MFT/FAT）完全一致。
        -- 此时虽然盘符还在，但文件系统状态已变为“干净”，可以直接断电。
        local defs = win.disk.defs
        local util = win.core
        
        local ok, err = util.ioctl(hVol:get(), defs.IOCTL.DISMOUNT)
        if ok then
            print("Volume dismounted successfully (Clean State).")
        else
            print("Warning: Dismount failed (Open handles exist?): " .. tostring(err))
            -- 如果 Dismount 失败，说明还有程序（如 CMD 或 Explorer）占用着 C 盘
        end
        
        hVol:close()
    end

    -- 3. 全局 Sync (查漏补缺)
    win.disk.sync()
    
    print("Disk data persisted.")
end

return M