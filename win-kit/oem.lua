local win = require 'win-utils'

local M = {}
local KEY_OEM = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OEMInformation"

-- [API] 设置系统属性中的 OEM 信息
-- @param info: table
--    info.manufacturer (string)
--    info.model (string)
--    info.support_url (string)
--    info.support_phone (string)
--    info.logo_path (string) - 必须是 .bmp 格式
--    info.support_hours (string)
function M.set(info)
    if type(info) ~= "table" then return false, "Table expected" end
    
    local k, err = win.reg.open_key("HKLM", KEY_OEM)
    if not k then return false, "Registry access failed: " .. tostring(err) end
    
    -- 映射表：Lua 键名 -> 注册表键名
    local map = {
        manufacturer = "Manufacturer",
        model        = "Model",
        support_url  = "SupportURL",
        support_phone= "SupportPhone",
        logo_path    = "Logo",
        support_hours= "SupportHours"
    }
    
    for lua_key, reg_key in pairs(map) do
        local val = info[lua_key]
        if val then
            k:write(reg_key, val)
        elseif val == "" then
            -- 如果传入空字符串，视为删除该项
            k:delete_value(reg_key)
        end
    end
    
    k:close()
    return true
end

-- [API] 读取当前 OEM 信息
function M.get()
    local k = win.reg.open_key("HKLM", KEY_OEM)
    if not k then return nil end
    
    local info = {
        manufacturer = k:read("Manufacturer"),
        model        = k:read("Model"),
        support_url  = k:read("SupportURL"),
        support_phone= k:read("SupportPhone"),
        logo_path    = k:read("Logo"),
        support_hours= k:read("SupportHours")
    }
    k:close()
    return info
end

return M