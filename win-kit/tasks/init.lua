local M = {}

local modules = {
    install_drivers = 'win-kit.tasks.install_drivers',
    assign_drive_letters = 'win-kit.tasks.assign_drive_letters',
    setup_pagefile = 'win-kit.tasks.setup_pagefile',
    setup_display = 'win-kit.tasks.setup_display',
    shutdown_cleanup = 'win-kit.tasks.shutdown_cleanup',
    init_pe = 'win-kit.tasks.init_pe',
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
