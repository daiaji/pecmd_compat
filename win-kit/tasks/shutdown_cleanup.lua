local cleaner = require 'win-kit.cleaner'
local poweroff = require 'win-kit.poweroff'

local M = {}

function M.plan(opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'shutdown_cleanup',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'clean_standard_temp_dirs' },
            { action = 'flush_and_dismount_target_volume', drive = opts.target_drive_letter },
            { action = 'sync_all_disks' },
        },
        warnings = {},
    }
end

function M.run(opts)
    opts = opts or {}
    if opts.dry_run then
        return M.plan(opts)
    end

    local clean_ok, clean_detail = cleaner.cleanup_standard(opts)
    if not clean_ok then
        return nil, { task = 'shutdown_cleanup', code = 'cleanup_failed', message = 'Standard cleanup failed', detail = clean_detail }
    end

    local finalize_detail = nil
    if opts.target_drive_letter then
        finalize_detail = poweroff.finalize_install(opts.target_drive_letter)
    end

    return {
        ok = true,
        task = 'shutdown_cleanup',
        changed = (clean_detail and clean_detail.changed) or finalize_detail ~= nil,
        cleanup = clean_detail,
        finalize = finalize_detail,
    }
end

return M
