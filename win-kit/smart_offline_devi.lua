local win = require 'win-utils'
local bit = require 'bit'

local M = {}

local function default_log(fmt, ...)
    print(string.format("[SmartOfflineDEVI] " .. fmt, ...))
end

local function get_logger(opts)
    if opts and opts.logger then
        return opts.logger
    end
    return default_log
end

function M.plan(opts)
    opts = opts or {}
    local driver_source = opts.driver_source or opts.root or opts.driver_root or (opts.roots and opts.roots[1]) or [[U:\Drivers]]
    local offline_image = opts.offline_image or [[D:\]]

    return {
        ok = true,
        task = 'install_drivers',
        offline = true,
        dry_run = true,
        changed = false,
        steps = {
            { action = 'scan_local_hardware_ids' },
            { action = 'scan_matching_inf_files', root = driver_source },
            { action = 'inject_offline_drivers', image = offline_image },
        },
        warnings = {},
    }
end

function M.inject(opts)
    opts = opts or {}
    if opts.dry_run then
        return M.plan(opts)
    end

    local log = get_logger(opts)
    local driver_source = opts.driver_source or opts.root or opts.driver_root or (opts.roots and opts.roots[1]) or [[U:\Drivers]]
    local offline_image = opts.offline_image or [[D:\]]

    log("Injecting drivers from %s into offline image %s", driver_source, offline_image)

    -- 即便是离线注入，我们通常也是为了让目标系统能在当前机器上启动，
    -- 所以依据当前 WinPE 识别到的物理硬件 ID 进行匹配。
    log("Scanning local hardware IDs...")

    local local_devs = win.sys.dev_info.enum_devices({ present = true })
    if not local_devs then
        return nil, { task = 'install_drivers', code = 'device_enum_failed', message = 'Failed to enumerate devices' }
    end

-- 构建目标 ID 查找表 (Set)
    local target_ids = {}
    local id_count = 0

    for _, dev in ipairs(local_devs) do
        if dev.hwids then
            for _, id in ipairs(dev.hwids) do
                target_ids[id:upper()] = true
                id_count = id_count + 1
            end
        end
        if dev.compat_ids then
            for _, id in ipairs(dev.compat_ids) do
                target_ids[id:upper()] = true
                id_count = id_count + 1
            end
        end
    end

    log("Found %d devices, collected %d unique hardware IDs.", #local_devs, id_count)

    log("Scanning drivers in '%s'...", driver_source)

    if not win.fs.is_dir(driver_source) then
        return nil, { task = 'install_drivers', code = 'driver_source_missing', message = 'Driver source directory not found', path = driver_source }
    end

    local matched_infs = {}

    local function scan_match_recursive(dir)
        for name, attr in win.fs.scandir(dir) do
            if name ~= "." and name ~= ".." then
                local full_path = dir .. "\\" .. name
                local is_dir = bit.band(attr, 0x10) ~= 0

                if is_dir then
                    scan_match_recursive(full_path)
                elseif name:match("%.[iI][nN][fF]$") then
                    local supported_ids = win.sys.inf.get_hwids(full_path)

                    if supported_ids then
                        for id, _ in pairs(supported_ids) do
                            if target_ids[id:upper()] then
                                log("MATCH: %s matches hardware %s", name, id)
                                table.insert(matched_infs, full_path)
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    scan_match_recursive(driver_source)
    log("Total matched INF files: %d", #matched_infs)

    if #matched_infs == 0 then
        return { ok = true, task = 'install_drivers', offline = true, changed = false, injected_count = 0 }
    end

    log("Injecting into offline image: %s", offline_image)

    local injected_count = 0
    local errors = {}

    for i, inf in ipairs(matched_infs) do
        log("[%d/%d] Injecting %s", i, #matched_infs, win.fs.path.basename(inf))

        local ok, res = win.sys.dism.add_driver_offline(offline_image, inf, { force_unsigned = opts.force_unsigned ~= false })

        if ok then
            injected_count = injected_count + 1
        else
            table.insert(errors, { inf = inf, result = res })
            if type(res) == "string" then
                log("Failed: %s", res)
            elseif type(res) == "table" and res.errors then
                for _, e in ipairs(res.errors) do
                    log("DISM log: %s", e)
                end
            end
        end
    end

    win.sys.dism.shutdown()

    return {
        ok = #errors == 0,
        task = 'install_drivers',
        offline = true,
        changed = injected_count > 0,
        matched_count = #matched_infs,
        injected_count = injected_count,
        errors = errors,
    }
end

return M
