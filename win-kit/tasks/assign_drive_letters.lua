local automount = require 'win-kit.automount'

local M = {}

function M.plan(opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'assign_drive_letters',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'scan_physical_disks' },
            { action = 'filter_mountable_partitions' },
            { action = 'assign_missing_drive_letters' },
        },
        warnings = {},
    }
end

function M.run(opts)
    opts = opts or {}
    if opts.dry_run then
        return M.plan(opts)
    end

    local count, detail = automount.auto_mount_all(opts)
    if detail then return detail end
    return { ok = true, task = 'assign_drive_letters', changed = count > 0, assigned_count = count }
end

return M
