local win = require 'win-utils'
local ffi = require 'ffi'

local M = {}

-- 定义 SYSTEM_POWER_STATUS
ffi.cdef[[
    typedef struct _SYSTEM_POWER_STATUS {
        uint8_t ACLineStatus;
        uint8_t BatteryFlag;
        uint8_t BatteryLifePercent;
        uint8_t SystemStatusFlag;
        uint32_t BatteryLifeTime;
        uint32_t BatteryFullLifeTime;
    } SYSTEM_POWER_STATUS;
    int GetSystemPowerStatus(SYSTEM_POWER_STATUS* lpSystemPowerStatus);
]]

-- [API] 检测是否为笔记本 (基于电池状态)
-- 这是一个启发式方法：有电池通常意味着是移动设备
function M.is_laptop()
    local kernel32 = ffi.load("kernel32")
    local status = ffi.new("SYSTEM_POWER_STATUS")
    
    if kernel32.GetSystemPowerStatus(status) ~= 0 then
        -- BatteryFlag: 128 (0x80) means No system battery
        -- BatteryFlag: 255 (0xFF) means Unknown status
        -- 如果不是 128 且不是 255，则认为有电池
        if status.BatteryFlag ~= 128 and status.BatteryFlag ~= 255 then
            return true
        end
    end
    return false
end

-- [API] 检测是否为 UEFI 启动
function M.is_uefi()
    return win.sys.info.get_firmware_type() == "UEFI"
end

-- [API] 获取系统架构 ("x64", "x86", "arm64")
function M.get_arch()
    return ffi.arch
end

-- [API] 获取简单的硬件摘要
function M.get_profile()
    return {
        firmware = win.sys.info.get_firmware_type(),
        arch = M.get_arch(),
        is_laptop = M.is_laptop(),
        winpe = win.sys.info.is_winpe()
    }
end

return M