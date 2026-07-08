local win = require 'win-utils'

local M = {}

-- [API] 检测是否为笔记本 (基于电池状态)
-- 这是一个启发式方法：有电池通常意味着是移动设备
function M.is_laptop()
    return win.sys.info.is_laptop()
end

-- [API] 检测是否为 UEFI 启动
function M.is_uefi()
    return win.sys.info.get_firmware_type() == "UEFI"
end

-- [API] 获取系统架构 ("x64", "x86", "arm64")
function M.get_arch()
    return win.sys.info.get_arch()
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
