local repair = require 'win-kit.repair'

local M = {}

local function bcdedit(args, opts)
    return repair.exec_capture('bcdedit.exe ' .. args, nil, opts)
end

function M.plan(opts)
    opts = opts or {}
    local steps = {}

    local target = opts.target or '{current}'
    local store = opts.store

    if opts.fix_boot_partition then
        table.insert(steps, { action = 'mark_partition_active', target = target })
    end
    if opts.rebuild_bcd then
        table.insert(steps, { action = 'rebuild_bcd', store = store, target = target })
    end
    if opts.fix_bootsector then
        table.insert(steps, { action = 'write_bootsect', drive = opts.fix_bootsector })
    end
    if opts.timeout ~= nil then
        table.insert(steps, { action = 'set_timeout', store = store, value = opts.timeout })
    end
    if opts.default_entry then
        table.insert(steps, { action = 'set_default', store = store, entry = opts.default_entry })
    end
    if opts.offline_hive_repair then
        table.insert(steps, { action = 'load_and_repair_hive', mount_point = opts.offline_hive_repair.mount_point, file = opts.offline_hive_repair.file })
    end

    return {
        ok = true,
        task = 'boot_repair',
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
    local store_arg = opts.store and ('/store "' .. opts.store .. '" ') or ''
    local target = opts.target or '{current}'

    if opts.fix_boot_partition then
        local out, code = bcdedit(store_arg .. '/set ' .. target .. ' device partition=' .. (opts.fix_boot_partition or 'C:'), opts)
        if code ~= 0 then
            return nil, { task = 'boot_repair', code = 'bcdedit_device_failed', message = 'bcdedit set device failed: ' .. tostring(out) }
        end
        details.device_set = true
    end

    if opts.rebuild_bcd then
        local out, code = bcdedit(store_arg .. '/set ' .. target .. ' osdevice partition=' .. (opts.rebuild_bcd or 'C:'), opts)
        if code ~= 0 then
            return nil, { task = 'boot_repair', code = 'bcdedit_osdevice_failed', message = 'bcdedit set osdevice failed: ' .. tostring(out) }
        end
        details.osdevice_set = true
    end

    if opts.fix_bootsector then
        local out, code = repair.exec_capture('bootsect.exe /nt60 ' .. opts.fix_bootsector .. ' /force', nil, opts)
        if code ~= 0 then
            table.insert(details.warnings or {}, 'bootsect failed: ' .. tostring(out))
        else
            details.bootsect_written = opts.fix_bootsector
        end
    end

    if opts.timeout ~= nil then
        local out, code = bcdedit(store_arg .. '/timeout ' .. tostring(opts.timeout), opts)
        if code ~= 0 then
            return nil, { task = 'boot_repair', code = 'bcdedit_timeout_failed', message = 'bcdedit /timeout failed: ' .. tostring(out) }
        end
        details.timeout_set = opts.timeout
    end

    if opts.default_entry then
        local out, code = bcdedit(store_arg .. '/default ' .. opts.default_entry, opts)
        if code ~= 0 then
            return nil, { task = 'boot_repair', code = 'bcdedit_default_failed', message = 'bcdedit /default failed: ' .. tostring(out) }
        end
        details.default_set = opts.default_entry
    end

    if opts.offline_hive_repair then
        local ok, err = repair.with_super_hive(
            opts.offline_hive_repair.mount_point,
            opts.offline_hive_repair.file,
            function(key)
                if opts.offline_hive_repair.callback then
                    opts.offline_hive_repair.callback(key)
                end
            end,
            opts
        )
        if not ok then
            return nil, { task = 'boot_repair', code = 'hive_repair_failed', message = tostring(err) }
        end
        details.hive_repaired = opts.offline_hive_repair.file
    end

    return {
        ok = true,
        task = 'boot_repair',
        changed = details.device_set ~= nil or details.osdevice_set ~= nil or details.bootsect_written ~= nil or details.timeout_set ~= nil or details.default_set ~= nil or details.hive_repaired ~= nil,
        details = details,
    }
end

return M
