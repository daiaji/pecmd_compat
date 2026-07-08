local win = require 'win-utils'

local M = {}

-- 简单的日志打印
local function default_log(fmt, ...)
    print(string.format("[SmartDEVI] " .. fmt, ...))
end

local function get_logger(opts)
    if opts and opts.logger then
        return opts.logger
    end
    return default_log
end

-- 快速读取文件内容到字符串
local function read_file_as_string(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- -----------------------------------------------------------------------------
-- 核心逻辑：智能安装
-- -----------------------------------------------------------------------------
-- @param drv_path: 驱动包根目录 (例如 "X:\Drivers")
-- @param mode: 
--    "smart" (默认): 仅安装 HardwareID 匹配缺失驱动设备的 INF
--    "force": 强制安装目录下所有 INF
--    "all": 扫描所有设备（不仅是有问题的），尝试更新驱动
local function smart_install(drv_path, mode, opts)
    opts = opts or {}
    local log = get_logger(opts)
    mode = mode or "smart"
    
    log("Starting Driver Install. Mode: %s", mode)
    
    -- 1. 获取目标 ID 集合
    local target_ids = {}
    if mode == "force" then
        log("Force mode: skipping system device scan.")
    else
        -- 如果是 "all"，则列出所有设备；否则只列出有问题(缺驱动)的设备
        local only_problem = (mode == "smart")
        local devs = win.sys.dev_info.enum_devices({ problem = only_problem, present = true })
        
        local count = 0
        if devs then
            for _, dev in ipairs(devs) do
                if dev.hwids then
                    for _, id in ipairs(dev.hwids) do 
                        target_ids[id:upper()] = true 
                    end
                end
                if dev.compat_ids then
                    for _, id in ipairs(dev.compat_ids) do 
                        target_ids[id:upper()] = true 
                    end
                end
                count = count + 1
            end
        end
        
        log("Scanned %d relevant devices.", count)
        
        if count == 0 and mode == "smart" then
            log("No missing drivers found. Exiting.")
            return { ok = true, task = 'install_drivers', changed = false, installed_count = 0, reboot_needed = false }
        end
    end

    -- 2. 扫描 INF 文件
    if not win.fs.exists(drv_path) then
        log("Error: Driver path not found: %s", drv_path)
        return nil, { task = 'install_drivers', code = 'driver_source_missing', message = 'Driver path not found', path = drv_path }
    end
    
    log("Scanning INF files in: %s", drv_path)
    local inf_files = {}
    
    -- 递归扫描函数
    local function scan_dir(dir)
        for name, attr in win.fs.scandir(dir) do
            if name ~= "." and name ~= ".." then
                local full = dir .. "\\" .. name
                if win.fs.is_dir(full) then
                    scan_dir(full)
                elseif name:match("%.[iI][nN][fF]$") then
                    table.insert(inf_files, full)
                end
            end
        end
    end
    
    scan_dir(win.core.normalize_path(drv_path))
    log("Found %d INF files.", #inf_files)

    -- 3. 匹配与安装
    local installed_count = 0
    local reboot_needed = false
    
    for _, inf in ipairs(inf_files) do
        local need_install = false
        
        if mode == "force" then
            need_install = true
        else
            -- 启发式匹配：读取 INF 内容，查找是否包含目标 ID
            -- 这是一个极其高效的优化：不解析 INF 结构，直接全文搜索
            local content = read_file_as_string(inf)
            if content then
                -- 处理编码：部分 INF 是 UTF-16 LE
                -- 简单的处理方式是移除所有 \0 字节，将其“降级”为 ASCII
                -- 因为 HardwareID 本身只包含 ASCII 字符，这样做是安全的
                local clean_content = content:gsub("%z", ""):upper()
                
                for id, _ in pairs(target_ids) do
                    -- 简单的子串搜索。注意 ID 中的特殊字符可能会影响正则，
                    -- 所以使用 find(..., 1, true) 进行纯文本搜索
                    if clean_content:find(id, 1, true) then
                        log("MATCH: [%s] matches device [%s]", win.fs.path.basename(inf), id)
                        need_install = true
                        break
                    end
                end
            end
        end
        
        if need_install then
            log("Installing: %s", inf)
            -- 调用 DiInstallDriverW 进行安装
            local ok, req_reboot = win.sys.driver.install(inf, false)
            if ok then
                installed_count = installed_count + 1
                if req_reboot then reboot_needed = true end
                log("  -> Success%s", req_reboot and " (Reboot Required)" or "")
            else
                -- 如果安装失败，尝试添加到驱动存储区作为后备
                local ok_store, err_store = win.sys.driver.add_to_store(inf)
                if ok_store then
                    log("  -> Install failed, but added to Driver Store.")
                else
                    log("  -> Failed: " .. (tostring(err_store) or "Unknown"))
                end
            end
        end
    end
    
    log("Done. Installed %d drivers.", installed_count)
    if reboot_needed then
        log("NOTE: A system reboot is required to complete driver installation.")
    end

    return {
        ok = true,
        task = 'install_drivers',
        changed = installed_count > 0,
        installed_count = installed_count,
        reboot_needed = reboot_needed,
    }
end

function M.plan(opts)
    opts = opts or {}
    local root = opts.root or opts.driver_root or (opts.roots and opts.roots[1]) or [[X:\Drivers]]
    return {
        ok = true,
        task = 'install_drivers',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'scan_devices', mode = opts.mode or 'smart' },
            { action = 'scan_inf_files', root = root },
            { action = 'install_matching_drivers', root = root },
        },
        warnings = {},
    }
end

function M.install(opts)
    opts = opts or {}

    if opts.dry_run then
        return M.plan(opts)
    end

    if not win.process.token.is_elevated() then
        return nil, { task = 'install_drivers', code = 'not_elevated', message = 'Administrator privileges are required for driver installation' }
    end

    local root = opts.root or opts.driver_root or (opts.roots and opts.roots[1]) or [[X:\Drivers]]
    return smart_install(root, opts.mode or 'smart', opts)
end

M.smart_install = smart_install

return M
