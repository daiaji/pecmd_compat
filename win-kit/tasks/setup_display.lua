local auto_display = require 'win-kit.auto_display'

local M = {}

function M.plan(opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'setup_display',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'enumerate_display_modes' },
            { action = 'select_best_display_mode' },
            { action = 'apply_display_mode' },
        },
        warnings = {},
    }
end

function M.run(opts)
    opts = opts or {}
    if opts.dry_run then
        return M.plan(opts)
    end

    local ok, err = auto_display.auto_set(opts)
    if not ok then
        return nil, { task = 'setup_display', code = 'display_setup_failed', message = tostring(err) }
    end

    return err or { ok = true, task = 'setup_display', changed = true }
end

return M
