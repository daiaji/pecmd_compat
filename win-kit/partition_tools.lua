local ffi = require 'ffi'
local bit = require 'bit'
local win = require 'win-utils'
local types = win.disk.types

local M = {}

-- 64位常量定义 (GPT 属性)
-- LuaJIT 的 bit 库只能处理 32 位，必须使用 cdata + 算术运算处理高位
local GPT_ATTR_READONLY = 0x1000000000000000ULL
local GPT_ATTR_HIDDEN   = 0x4000000000000000ULL
local GPT_ATTR_NODRIVE  = 0x8000000000000000ULL

-- 辅助：简单的 64 位位设置 (仅用于特定 Flag，不通用)
-- 原理：如果位未置位，则加；如果位已置位，则减 (用于清除)
local function set_flag_64(val64, flag64, enable)
    -- 使用 FFI 算术运算检测位状态
    -- (val & flag) == flag
    local has_flag = (val64 % (flag64 * 2ULL)) >= flag64
    
    if enable then
        if not has_flag then return val64 + flag64 end
    else
        if has_flag then return val64 - flag64 end
    end
    return val64
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
function M.set_id(drive_idx, part_idx, new_id)
    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive failed" end
    
    -- 直接调用 win-utils 底层，它会自动处理 MBR/GPT 的类型差异
    local ok, err = win.disk.layout.set_partition_type(drive, part_idx, new_id)
    
    drive:close()
    return ok, err
end

-- [API] 设置 MBR 分区激活状态
-- 对标 PECMD: PART <磁盘>#<分区> -a / a
function M.set_active(drive_idx, part_idx, active)
    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive failed" end
    
    local ok, err = win.disk.layout.set_active(drive, part_idx, active)
    
    drive:close()
    return ok, err
end

-- [API] 智能显隐分区
-- 对标 PECMD: PART <磁盘>#<分区> 0x17 (隐藏) / 0x07 (显示) 的智能封装
-- 自动识别 MBR/GPT 并应用最佳实践策略
-- @param drive_idx: 磁盘号
-- @param part_idx: 分区号
-- @param hidden: boolean (true=隐藏, false=显示)
function M.set_hidden(drive_idx, part_idx, hidden)
    -- 1. 获取当前状态以判断分区表类型
    local info, part, err = get_part_info(drive_idx, part_idx)
    if not info then return false, err end
    
    -- 打开驱动器准备写入
    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive rw failed" end
    
    local success = false
    local msg = nil
    
    -- 2. 执行显隐策略
    if info.style == "GPT" then
        -- === GPT 策略 ===
        -- 修改 Attribute Bits: Hidden(62) + NoDriveLetter(63)
        local current = ffi.cast("uint64_t", part.attr)
        local new_attr = current
        
        new_attr = set_flag_64(new_attr, GPT_ATTR_HIDDEN, hidden)
        new_attr = set_flag_64(new_attr, GPT_ATTR_NODRIVE, hidden)
        
        if new_attr ~= current then
            success, msg = win.disk.layout.set_partition_attributes(drive, part.num, new_attr)
        else
            success = true; msg = "No change needed"
        end
        
    else
        -- === MBR 策略 ===
        -- 修改 PartitionType ID: +/- 0x10
        local current_id = part.type
        local new_id = current_id
        
        if hidden then
            -- 常见 ID 映射: 0x07(NTFS)->0x17, 0x0B(FAT32)->0x1B
            -- 如果第4位(0x10)未置位，则加上
            if bit.band(current_id, 0x10) == 0 then
                new_id = bit.bor(current_id, 0x10)
            end
        else
            -- 反之，如果第4位已置位，则清除
            if bit.band(current_id, 0x10) ~= 0 then
                new_id = bit.band(current_id, bit.bnot(0x10))
            end
        end
        
        if new_id ~= current_id then
            success, msg = win.disk.layout.set_partition_type(drive, part.num, new_id)
        else
            success = true; msg = "No change needed"
        end
    end
    
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
    
    return success, msg
end

-- [API] 简易只读设置 (GPT Only)
-- MBR 不支持标准只读位，通常忽略
function M.set_readonly(drive_idx, part_idx, readonly)
    local info, part, err = get_part_info(drive_idx, part_idx)
    if not info then return false, err end
    
    if info.style ~= "GPT" then 
        return false, "Read-only attribute is GPT only" 
    end
    
    local drive = win.disk.physical.open(drive_idx, "rw", true)
    if not drive then return false, "Open drive failed" end
    
    local current = ffi.cast("uint64_t", part.attr)
    local new_attr = set_flag_64(current, GPT_ATTR_READONLY, readonly)
    
    local ok, res_err = win.disk.layout.set_partition_attributes(drive, part.num, new_attr)
    
    drive:close()
    return ok, res_err
end

return M