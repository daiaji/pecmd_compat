local win = require 'win-utils'

local M = {}

local function default_log(fmt, ...)
    print(string.format("[Pagefile] " .. fmt, ...))
end

local function get_logger(opts)
    if opts and opts.logger then return opts.logger end
    return default_log
end

function M.plan(min_ram_mb, page_size_mb, opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'setup_pagefile',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'query_memory', min_ram_mb = min_ram_mb },
            { action = 'select_fixed_drive', size_mb = page_size_mb },
            { action = 'create_pagefile', size_mb = page_size_mb },
        },
        warnings = {},
    }
end

-- [API] 智能设置虚拟内存
-- 对标 PECMD PAGE 命令的智能逻辑
-- @param min_ram_mb: 如果物理内存大于此值(MB)，则跳过设置
-- @param page_size_mb: 设置的大小 (初始大小=最大大小)
function M.smart_set(min_ram_mb, page_size_mb, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan(min_ram_mb, page_size_mb, opts) end

    local log = get_logger(opts)

    -- 1. 检查物理内存
    local mem = win.sys.info.get_memory_info()
    if not mem then 
        return false, "Failed to query memory info" 
    end
    
    if mem.total_mb > min_ram_mb then
        log("Physical RAM (%d MB) > Threshold (%d MB). Skipped.", mem.total_mb, min_ram_mb)
        return true, { ok = true, task = 'setup_pagefile', changed = false, skipped = true, total_mb = mem.total_mb }
    end
    
    -- 2. 寻找最佳磁盘 (排除 A/B 盘，找剩余空间最大的固定磁盘)
    log("Searching for suitable drive...")
    
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
    log("Creating %d MB pagefile on %s", page_size_mb, path)
    
    local ok, err = win.sys.pagefile.create(path, page_size_mb, page_size_mb)
    if not ok then
        return false, "Create failed: " .. tostring(err)
    end
    
    return true, { ok = true, task = 'setup_pagefile', changed = true, path = path, size_mb = page_size_mb }
end

return M
