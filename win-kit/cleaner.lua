local win = require 'win-utils'
local unlocker = require 'win-kit.unlocker'
local bit = require 'bit'

local M = {}

local function default_log(fmt, ...)
    print(string.format("[Cleaner] " .. fmt, ...))
end

local function get_logger(opts)
    if opts and opts.logger then return opts.logger end
    return default_log
end

function M.plan(target, opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'clean_dir',
        dry_run = true,
        changed = false,
        target = target,
        self_delete = opts.self_delete == true,
        steps = {
            { action = 'scan_dir', path = target },
            { action = 'force_delete_contents', path = target },
        },
        warnings = {},
    }
end

-- [API] 设置临时目录 (立即生效 + 持久化)
function M.set_temp(path)
    if not win.fs.mkdir(path, {p=true}) then return false, "Mkdir failed" end
    
    -- 1. 当前进程生效
    win.sys.env.set("TEMP", path)
    win.sys.env.set("TMP", path)
    
    -- 2. 系统全局生效
    win.sys.env.set_persistent("TEMP", path, "System")
    win.sys.env.set_persistent("TMP", path, "System")
    
    -- 3. 用户级生效 (覆盖)
    win.sys.env.set_persistent("TEMP", path, "User")
    win.sys.env.set_persistent("TMP", path, "User")
    
    return true
end

-- [API] 清理目录 (强制模式)
-- @param target: 目录路径
-- @param opts: { self_delete=bool } 是否删除目录本身
function M.clean_dir(target, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan(target, opts) end

    local log = get_logger(opts)
    log("Cleaning: %s", target)
    
    local count = 0
    local fails = 0
    
    if not win.fs.is_dir(target) then
        return true, { ok = true, task = 'clean_dir', changed = false, target = target, count = 0, fails = 0 }
    end
    
    -- 递归删除内容
    for name, attr in win.fs.scandir(target) do
        if name ~= "." and name ~= ".." then
            local full = target .. "\\" .. name
            local is_dir = (bit.band(attr, 0x10) ~= 0)
            
            local ok = false
            if is_dir then
                -- 递归调用自身清理子目录
                -- 这里返回值是 (success, count) tuple, 只取 success
                local sub_ok = M.clean_dir(full, { self_delete = true, logger = opts.logger })
                ok = sub_ok
            else
                -- 尝试强制删除文件 (利用 unlocker)
                ok = unlocker.force_delete(full, opts)
            end
            
            if ok then count = count + 1 else fails = fails + 1 end
        end
    end
    
    -- 如果需要删除目录本身
    if opts.self_delete then
        if not win.fs.delete(target) then fails = fails + 1 end
    end
    
    return fails == 0, { ok = fails == 0, task = 'clean_dir', changed = count > 0, target = target, count = count, fails = fails }
end

-- [API] 标准临时文件清理流程
function M.cleanup_standard(opts)
    opts = opts or {}
    if opts.dry_run then
        return true, {
            ok = true,
            task = 'shutdown_cleanup',
            dry_run = true,
            changed = false,
            steps = {
                { action = 'clean_env_temp_dir' },
                { action = 'clean_system_temp_dir' },
            },
            warnings = {},
        }
    end

    local dirs = {
        win.sys.env.get("TEMP"),
        win.sys.env.get("SystemRoot") .. "\\Temp"
    }
    local cleaned = 0
    local failures = 0
    
    for _, d in ipairs(dirs) do
        if d and win.fs.exists(d) then
            local ok, detail = M.clean_dir(d, { self_delete = false, logger = opts.logger }) -- 保留 TEMP 根目录
            if ok then
                cleaned = cleaned + (detail and detail.count or 0)
            else
                failures = failures + 1
            end
        end
    end

    return failures == 0, { ok = failures == 0, task = 'shutdown_cleanup', changed = cleaned > 0, cleaned_count = cleaned, failures = failures }
end

return M
