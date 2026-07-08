local win = require 'win-utils'

local M = {}

function M.plan(action, drive_idx, part_idx, value)
    return {
        ok = true,
        task = 'partition_tools',
        dry_run = true,
        changed = false,
        drive_index = drive_idx,
        partition = part_idx,
        steps = {
            { action = action, drive_index = drive_idx, partition = part_idx, value = value },
        },
        warnings = {},
    }
end

-- 辅助：获取指定分区的布局信息
local function get_part_info(drive_idx, part_idx_or_off)
    local drive, err = win.disk.physical.open(drive_idx, "r", true)
    if not drive then return nil, nil, "Open drive failed: " .. tostring(err) end
    
    local layout_info = win.disk.layout.get(drive)
    drive:close()
    
    if not layout_info then return nil, nil, "Get layout failed" end
    
    local target_part = nil
    for _, p in ipairs(layout_info.parts) do
        -- 支持按 分区号(1-based) 或 偏移量 查找
        if type(part_idx_or_off) == "number" then
            if part_idx_or_off < 1024 then -- 假设小于 1024 是分区号
                if p.num == part_idx_or_off then target_part = p; break end
            else -- 假设是大数是偏移量
                if p.off == part_idx_or_off then target_part = p; break end
            end
        end
    end
    
    if not target_part then return nil, nil, "Partition not found" end
    return layout_info, target_part
end

-- [API] 修改分区类型 ID
-- 对标 PECMD: PART <磁盘>#<分区> <ID>
-- @param drive_idx: 物理磁盘号 (0, 1...)
-- @param part_idx: 分区号 (1, 2...)
-- @param new_id: MBR(数字, 如 0x07) 或 GPT(GUID 字符串)
function M.set_id(drive_idx, part_idx, new_id, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan('set_partition_id', drive_idx, part_idx, new_id) end

    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive failed" end
    
    -- 直接调用 win-utils 底层，它会自动处理 MBR/GPT 的类型差异
    local ok, err = win.disk.layout.set_partition_type(drive, part_idx, new_id)
    
    drive:close()
    if not ok then return false, err end
    return true, { ok = true, task = 'partition_tools', changed = true, action = 'set_partition_id', drive_index = drive_idx, partition = part_idx, value = new_id }
end

-- [API] 设置 MBR 分区激活状态
-- 对标 PECMD: PART <磁盘>#<分区> -a / a
function M.set_active(drive_idx, part_idx, active, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan('set_active', drive_idx, part_idx, active) end

    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive failed" end
    
    local ok, err = win.disk.layout.set_active(drive, part_idx, active)
    
    drive:close()
    if not ok then return false, err end
    return true, { ok = true, task = 'partition_tools', changed = true, action = 'set_active', drive_index = drive_idx, partition = part_idx, value = active }
end

-- [API] 智能显隐分区
-- 对标 PECMD: PART <磁盘>#<分区> 0x17 (隐藏) / 0x07 (显示) 的智能封装
-- 自动识别 MBR/GPT 并应用最佳实践策略
-- @param drive_idx: 磁盘号
-- @param part_idx: 分区号
-- @param hidden: boolean (true=隐藏, false=显示)
function M.set_hidden(drive_idx, part_idx, hidden, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan('set_hidden', drive_idx, part_idx, hidden) end

    local info, part, err = get_part_info(drive_idx, part_idx)
    if not info then return false, err end
    
    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive rw failed" end
    
    local success, msg = win.disk.layout.set_hidden(drive, part.num, hidden)
    
    drive:close()
    
    -- 3. 后处理：如果是隐藏操作，强制卸载当前挂载点
    if success and hidden then
        -- 查找该分区对应的卷 GUID
        local guid_path = win.disk.volume.find_guid_by_partition(drive_idx, part.off)
        if guid_path then
            local vol_list = win.disk.volume.list()
            for _, v in ipairs(vol_list or {}) do
                if v.guid_path == guid_path then
                    -- 卸载所有盘符 (例如 "F:\", "G:\")
                    for _, mp in ipairs(v.mount_points) do
                        win.disk.mount.unmount(mp) -- 这会广播系统消息刷新 Explorer
                    end
                    -- 卸载卷本身 (强制断开句柄)
                    local hVol = win.disk.volume.open(guid_path)
                    if hVol then
                        win.core.ioctl(hVol:get(), win.disk.defs.IOCTL.DISMOUNT)
                        hVol:close()
                    end
                end
            end
        end
    end
    
    if not success then return false, msg end
    return true, { ok = true, task = 'partition_tools', changed = true, action = 'set_hidden', drive_index = drive_idx, partition = part_idx, value = hidden }
end

-- [API] 简易只读设置 (GPT Only)
-- MBR 不支持标准只读位，通常忽略
function M.set_readonly(drive_idx, part_idx, readonly, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan('set_readonly', drive_idx, part_idx, readonly) end

    local info, part, err = get_part_info(drive_idx, part_idx)
    if not info then return false, err end

    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive failed" end

    local ok, res_err = win.disk.layout.set_readonly(drive, part.num, readonly)
    
    drive:close()
    if not ok then return false, res_err end
    return true, { ok = true, task = 'partition_tools', changed = true, action = 'set_readonly', drive_index = drive_idx, partition = part_idx, value = readonly }
end

return M
