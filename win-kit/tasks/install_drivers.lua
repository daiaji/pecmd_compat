local smart_devi = require 'win-kit.smart_devi'
local smart_offline_devi = require 'win-kit.smart_offline_devi'

local M = {}

function M.run(opts)
    opts = opts or {}

    if opts.offline_image then
        return smart_offline_devi.inject(opts)
    end

    return smart_devi.install(opts)
end

function M.plan(opts)
    opts = opts or {}

    if opts.offline_image then
        return smart_offline_devi.plan(opts)
    end

    return smart_devi.plan(opts)
end

return M
