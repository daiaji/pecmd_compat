local win = require 'win-utils'

local M = {}

-- [API] 智能设置虚拟内存
-- 对标 PECMD PAGE 命令的智能逻辑
-- @param min_ram_mb: 如果物理内存大于此值(MB)，则跳过设置
-- @param page_size_mb: 设置的大小 (初始大小=最大大小)
function M.smart_set(min_ram_mb, page_size_mb)
    -- 1. 检查物理内存
    local mem = win.sys.info.get_memory_info()
    if not mem then 
        return false, "Failed to query memory info" 
    end
    
    if mem.total_mb > min_ram_mb then
        print(string.format("[Pagefile] Physical RAM (%d MB) > Threshold (%d MB). Skipped.", mem.total_mb, min_ram_mb))
        return true -- 视为成功
    end
    
    -- 2. 寻找最佳磁盘 (排除 A/B 盘，找剩余空间最大的固定磁盘)
    print("[Pagefile] Searching for suitable drive...")
    
    local best_drive = nil
    local max_free = 0
    
    local vols = win.disk.volume.list()
    if not vols then return false, "Failed to list volumes" end
    
    for _, v in ipairs(vols) do
        -- 必须有盘符且是固定磁盘 (Fixed)
        if #v.mount_points > 0 and v.type == "Fixed" then
            local root = v.mount_points[1] -- e.g., "C:\"
            local letter = root:sub(1,1):upper()
            
            -- 排除软驱/保留盘符 A: B:
            if letter ~= "A" and letter ~= "B" then
                local space = win.fs.get_space_info(root)
                local req_bytes = page_size_mb * 1024 * 1024
                
                if space and space.free_bytes > req_bytes then
                    -- 简单的贪婪策略：选剩余空间最大的
                    if space.free_bytes > max_free then
                        max_free = space.free_bytes
                        best_drive = root
                    end
                end
            end
        end
    end
    
    if not best_drive then 
        return false, "No suitable fixed drive found with enough space" 
    end
    
    -- 3. 创建页面文件
    local path = best_drive .. "pagefile.sys"
    print(string.format("[Pagefile] Creating %d MB pagefile on %s", page_size_mb, path))
    
    local ok, err = win.sys.pagefile.create(path, page_size_mb, page_size_mb)
    if not ok then
        return false, "Create failed: " .. tostring(err)
    end
    
    return true
end

return M