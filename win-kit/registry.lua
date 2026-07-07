local win = require 'win-utils'
local raw_reg = win.reg -- 引用底层 FFI 模块

local M = {}

-- ============================================================================
-- 基础配置与辅助函数
-- ============================================================================

-- 根键全名与缩写映射表
local ROOT_MAP = {
    -- HKLM
    HKLM = "HKLM",
    HKEY_LOCAL_MACHINE = "HKLM",
    MACHINE = "HKLM",
    
    -- HKCU
    HKCU = "HKCU",
    HKEY_CURRENT_USER = "HKCU",
    CURRENT_USER = "HKCU",
    
    -- HKU
    HKU = "HKU",
    HKEY_USERS = "HKU",
    USERS = "HKU",
    
    -- HKCR
    HKCR = "HKCR",
    HKEY_CLASSES_ROOT = "HKCR",
    CLASSES_ROOT = "HKCR",
    
    -- HKCC
    HKCC = "HKCC",
    HKEY_CURRENT_CONFIG = "HKCC",
    CURRENT_CONFIG = "HKCC"
}

-- 解析路径字符串
-- @param full_path: "HKLM\Software\MyKey"
-- @return: root_str("HKLM"), sub_key_str("Software\MyKey")
local function parse_path(full_path)
    if not full_path then return nil, "Path is nil" end
    
    -- 统一分隔符
    local clean_path = full_path:gsub("/", "\\")
    
    -- 分离根键和子键
    local root_part, sub_part = clean_path:match("^([^\\]+)\\(.*)")
    
    -- 处理仅有根键的情况 (e.g. "HKLM" or "HKLM\")
    if not root_part then
        root_part = clean_path:gsub("\\$", "")
        sub_part = ""
    end
    
    local canonical_root = ROOT_MAP[root_part:upper()]
    if not canonical_root then 
        return nil, "Invalid Registry Root: " .. tostring(root_part)
    end
    
    -- 移除子键末尾斜杠
    sub_part = sub_part:gsub("\\+$", "")
    
    return canonical_root, sub_part
end

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 读取注册表值
-- @param key_path: 完整键路径 (e.g. "HKCU\Control Panel\Desktop")
-- @param value_name: 值名称 (传 "" 或 nil 读取默认值)
-- @param default_val: (可选) 如果读取失败或不存在时返回的默认值
-- @return: 读取到的值 (string/number/table) 或 default_val
function M.read(key_path, value_name, default_val)
    local root, sub = parse_path(key_path)
    if not root then return default_val end
    
    -- 底层 open_key 目前是 Create 语义，这意味着读取不存在的键会创建空键
    -- 在配置工具场景下通常可以接受，若需严格只读需扩展底层 API
    local k = raw_reg.open_key(root, sub)
    if not k then return default_val end
    
    local res = k:read(value_name or "")
    k:close()
    
    if res == nil then return default_val end
    return res
end

--- 写入注册表值
-- @param key_path: 完整键路径
-- @param value_name: 值名称 (传 "" 或 nil 写默认值)
-- @param data: 要写入的数据
-- @param type_hint: (可选) 强制指定类型字符串: 
--        "string"(sz), "expand"(expand_sz), "multi"(multi_sz), 
--        "dword", "qword", "binary"
-- @return: boolean success, string error_msg
function M.write(key_path, value_name, data, type_hint)
    local root, sub = parse_path(key_path)
    if not root then return false, sub end -- sub contains error msg
    
    local k, err = raw_reg.open_key(root, sub)
    if not k then return false, "OpenKey failed: " .. tostring(err) end
    
    local val_name = value_name or ""
    local target_type = type_hint
    
    -- 自动类型推断
    if not target_type then
        local t = type(data)
        if t == "number" then
            -- 超过 32 位整数范围则使用 QWORD，否则 DWORD
            -- LuaJIT number 是 double (53bit 精度)，足以覆盖大部分整数场景
            target_type = (data > 4294967295 or data < -2147483648) and "qword" or "dword"
        elseif t == "boolean" then
            -- 布尔值自动转为 DWORD (1/0)
            data = data and 1 or 0
            target_type = "dword"
        elseif t == "table" then
            -- 表默认为 Multi_SZ 数组
            target_type = "multi_sz"
        else
            -- 默认字符串
            target_type = "string"
            data = tostring(data)
        end
    end
    
    -- 类型简写修正
    if target_type == "expand" then target_type = "expand_sz" end
    if target_type == "multi" then target_type = "multi_sz" end
    if target_type == "bin" then target_type = "binary" end
    
    local ok, w_err = k:write(val_name, data, target_type)
    k:close()
    
    return ok, w_err
end

--- 删除键或值
-- @param key_path: 完整键路径
-- @param value_name: (可选) 
--        如果提供了值名称，则删除该值。
--        如果为 nil，则**递归删除整个键**及其子键。
-- @return: boolean success, string error_msg
function M.delete(key_path, value_name)
    local root, sub = parse_path(key_path)
    if not root then return false, sub end
    
    if value_name then
        -- 模式 A: 删除值
        local k = raw_reg.open_key(root, sub)
        if not k then return true end -- 键不存在，视为删除成功
        
        local ok, err = k:delete_value(value_name)
        k:close()
        -- 如果值不存在(错误码2)，视为成功
        if not ok and err and err:find("2") then return true end
        return ok, err
    else
        -- 模式 B: 删除键 (递归)
        return raw_reg.delete_key(root, sub, true)
    end
end

--- 批量导入配置 (Config-as-Code)
-- 这是一个递归函数，将 Lua Table 结构映射到注册表树
-- @param base_path: 导入的根路径
-- @param data_table: 配置表
--    {
--       ValueName1 = "Data",      -- 写入值
--       ValueName2 = 123,         -- 写入 DWORD
--       SubKeyName = {            -- 创建子键并递归
--           InnerVal = "..."
--       }
--    }
-- @return: boolean success
function M.import(base_path, data_table)
    if type(data_table) ~= "table" then return false, "Table expected" end
    
    -- 确保基础路径存在
    local root, sub = parse_path(base_path)
    if not root then return false, "Invalid base path" end
    local k = raw_reg.open_key(root, sub)
    if not k then return false, "Failed to create base key" end
    k:close()
    
    for key, val in pairs(data_table) do
        -- 判断是子键还是值
        -- 如果 val 是 table，且不是数组形式 (Multi_SZ)，则视为子键结构
        local is_array = (type(val) == "table") and (val[1] ~= nil or #val == 0)
        
        if type(val) == "table" and not is_array then
            -- 递归处理子键
            local sub_path = base_path .. "\\" .. key
            local ok, err = M.import(sub_path, val)
            if not ok then return false, err end
        else
            -- 写入值 (自动推断类型)
            local ok, err = M.write(base_path, key, val)
            if not ok then 
                return false, string.format("Failed to write %s\\%s: %s", base_path, key, tostring(err)) 
            end
        end
    end
    
    return true
end

-- ============================================================================
-- 高级操作
-- ============================================================================

--- 强制重置权限 (Take Ownership + Full Access)
-- 对标 PECMD HIVE -super，用于处理受保护的注册表项
function M.reset_acl(key_path)
    local acl = require 'win-utils.reg.acl'
    if not acl then return false, "ACL module missing" end
    return acl.reset(key_path)
end

--- 加载 Hive 文件
-- @param key_path: 挂载点 (e.g. "HKLM\TempHive")
-- @param file_path: Hive 文件路径
function M.load_hive(key_path, file_path)
    return raw_reg.load_hive(key_path, file_path)
end

--- 卸载 Hive
function M.unload_hive(key_path)
    return raw_reg.unload_hive(key_path)
end

return M