local M = {}

-- 定义 win-kit 的模块映射 (平铺结构)
local modules = {
    -- 驱动相关
    driver_scanner      = 'win-kit.driver_scanner',
    driver_installer    = 'win-kit.driver_installer',
    smart_devi          = 'win-kit.smart_devi',
    smart_offline_devi  = 'win-kit.smart_offline_devi',
    
    -- 磁盘/系统相关
    automount           = 'win-kit.automount',
    smart_pagefile      = 'win-kit.smart_pagefile',
    unlocker            = 'win-kit.unlocker',
    auto_display        = 'win-kit.auto_display',
    icon_refresh        = 'win-kit.icon_refresh',
    oem                 = 'win-kit.oem',
    
    -- [NEW] 硬件与环境管理
    hardware            = 'win-kit.hardware',
    env_manager         = 'win-kit.env_manager',
    cleaner             = 'win-kit.cleaner',
    
    -- 逻辑/其他
    pecmd_logic         = 'win-kit.pecmd_logic',
    poweroff            = 'win-kit.poweroff'
}

setmetatable(M, {
    __index = function(t, key)
        local path = modules[key]
        if path then
            local mod = require(path)
            rawset(t, key, mod)
            return mod
        end
        return nil
    end
})

return M