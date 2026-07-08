local icon_refresh = require 'win-kit.icon_refresh'
local env_manager = require 'win-kit.env_manager'
local oem = require 'win-kit.oem'

local M = {}

function M.plan(opts)
    opts = opts or {}
    local steps = {}
    if opts.prepend_path then
        table.insert(steps, { action = 'prepend_path', path = opts.prepend_path, scope = opts.path_scope or 'System' })
    end
    if opts.append_path then
        table.insert(steps, { action = 'append_path', path = opts.append_path, scope = opts.path_scope or 'System' })
    end
    if opts.oem then
        table.insert(steps, { action = 'set_oem_information' })
    end
    if opts.refresh_icons ~= false then
        table.insert(steps, { action = 'refresh_icon_cache' })
    end

    return {
        ok = true,
        task = 'init_pe',
        dry_run = true,
        changed = false,
        steps = steps,
        warnings = {},
    }
end

function M.run(opts)
    opts = opts or {}
    if opts.dry_run then
        return M.plan(opts)
    end

    local details = {}

    if opts.prepend_path then
        local ok, err = env_manager.prepend_path(opts.prepend_path, opts.path_scope or 'System', opts)
        if not ok then return nil, { task = 'init_pe', code = 'prepend_path_failed', message = tostring(err) } end
        details.prepend_path = err
    end

    if opts.append_path then
        local ok, err = env_manager.append_path(opts.append_path, opts.path_scope or 'System', opts)
        if not ok then return nil, { task = 'init_pe', code = 'append_path_failed', message = tostring(err) } end
        details.append_path = err
    end

    if opts.oem then
        local ok, err = oem.set(opts.oem, opts)
        if not ok then return nil, { task = 'init_pe', code = 'oem_set_failed', message = tostring(err) } end
        details.oem = err
    end

    if opts.refresh_icons ~= false then
        local ok, err = icon_refresh.refresh_icons(opts)
        if not ok then
            return nil, { task = 'init_pe', code = 'icon_refresh_failed', message = tostring(err) }
        end
        details.icon_refresh = err
    end

    return {
        ok = true,
        task = 'init_pe',
        changed = details.prepend_path ~= nil or details.append_path ~= nil or details.oem ~= nil or details.icon_refresh ~= nil,
        details = details,
    }
end

return M
