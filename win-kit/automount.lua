local win = require 'win-utils'
local types = win.disk.types -- 使用 win-utils 导出的常量

local M = {}

-- 定义不需要自动分配盘符的特殊分区类型 GUID (GPT)
local IGNORE_GUIDS = {
    [types.GPT.MSR] = true,       -- Microsoft Reserved
    [types.GPT.RECOVERY] = true,  -- Recovery Partition
    -- [types.GPT.ESP] = true,    -- 通常不挂载 ESP，但维护环境下有时需要
}

-- MBR 分区类型黑名单
local IGNORE_MBR_TYPES = {
    [0x00] = true, -- Empty
    [0x05] = true, -- Extended
    [0x0F] = true, -- Extended LBA
}

-- [API] 智能挂载所有可见分区
-- 对标 PECMD DISK 命令的自动整理逻辑
-- 策略：遍历所有物理磁盘 -> 遍历所有分区 -> 过滤特殊分区 -> 分配未使用盘符
function M.auto_mount_all()
    print("[AutoMount] Scanning physical disks...")
    
    local drives = win.disk.physical.list()
    local assigned_count = 0
    
    -- 缓存当前的卷列表，用于快速检查是否已有盘符
    local vol_list = win.disk.volume.list() or {}
    
    for _, drive in ipairs(drives) do
        -- 以只读方式打开磁盘获取分区表
        local hDrive = win.disk.physical.open(drive.index, "r")
        
        if hDrive then
            local layout_info = win.disk.layout.get(hDrive)
            hDrive:close()
            
            if layout_info then
                print(string.format("  > Checking Disk %d (%s)...", drive.index, layout_info.style))
                
                for _, part in ipairs(layout_info.parts) do
                    -- 过滤掉无效分区 (Offset 0 或 Size 0)
                    if part.size > 0 and part.off > 0 then
                        local should_mount = true
                        
                        -- 1. 检查分区类型
                        if layout_info.style == "GPT" then
                            if IGNORE_GUIDS[part.type] then should_mount = false end
                        elseif layout_info.style == "MBR" then
                            if IGNORE_MBR_TYPES[part.type] then should_mount = false end
                        end
                        
                        if should_mount then
                            -- 2. 查找对应的卷 GUID 路径
                            local guid_path = win.disk.volume.find_guid_by_partition(drive.index, part.off)
                            
                            if guid_path then
                                -- 3. 检查是否已有盘符
                                local has_letter = false
                                for _, v in ipairs(vol_list) do
                                    if v.guid_path == guid_path then
                                        for _, mp in ipairs(v.mount_points) do
                                            if mp:match("^%a:\\") then 
                                                has_letter = true 
                                                break 
                                            end
                                        end
                                    end
                                end
                                
                                -- 4. 如果没有盘符，则分配
                                if not has_letter then
                                    local ok, letter = win.disk.volume.assign(drive.index, part.off)
                                    if ok then
                                        print(string.format("    + Mounted Part %d (Offset %d) to %s", 
                                            part.num, part.off, letter))
                                        assigned_count = assigned_count + 1
                                    else
                                        print(string.format("    ! Failed to mount Part %d: %s", part.num, letter))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    print(string.format("[AutoMount] Finished. Assigned %d new letters.", assigned_count))
    return assigned_count
end

return M