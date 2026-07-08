local win = require 'win-utils'
local M = {}

function M.exec_capture(cmd, timeout, opts)
    opts = opts or {}
    if opts.dry_run then
        return '', 0, {
            ok = true,
            task = 'repair',
            dry_run = true,
            changed = false,
            steps = {
                { action = 'exec_capture', command = cmd, timeout = timeout },
            },
            warnings = {},
        }
    end

    local out_raw, exit_code = win.process.popen.run(cmd, {
        show = 0,
        include_stderr = true,
        timeout = timeout,
    })

    if not out_raw then return '', -1 end
    return out_raw:gsub('^%s*(.-)%s*$', '%1'), exit_code
end

function M.exec_find(cmd, pattern, opts)
    local out = M.exec_capture(cmd, nil, opts)
    return out:find(pattern) ~= nil
end

function M.with_super_hive(mount_point, hive_file, func, opts)
    opts = opts or {}
    if opts.dry_run then
        return true, {
            ok = true,
            task = 'repair',
            dry_run = true,
            changed = false,
            steps = {
                { action = 'load_hive', key_path = mount_point, file_path = hive_file },
                { action = 'reset_hive_acl', key_path = mount_point },
                { action = 'run_hive_callback', key_path = mount_point },
                { action = 'unload_hive', key_path = mount_point },
            },
            warnings = {},
        }
    end

    local ok, err = win.reg.load_hive(mount_point, hive_file)
    if not ok then
        return false, 'LoadHive failed: ' .. tostring(err)
    end

    local status, result = pcall(function()
        local acl_ok, acl_err = win.reg.acl.reset(mount_point)
        if not acl_ok then
            error('ACL Reset failed: ' .. tostring(acl_err))
        end

        local root_name = mount_point:match('^[^\\]+')
        local sub_name = mount_point:match('\\(.*)')

        local k = win.reg.open_key(root_name, sub_name)
        if not k then error('Open mounted key failed') end

        func(k)
        k:close()
    end)

    local unload_ok = false
    for _ = 1, 5 do
        win.sys.io.tee(nil)
        collectgarbage()

        if win.reg.unload_hive(mount_point) then
            unload_ok = true
            break
        end
        win.process.sleep(200)
    end

    if not status then return false, result end
    if not unload_ok then return false, 'UnloadHive failed (Key locked)' end

    return true
end

return M
