local win = require 'win-utils'

local M = {}

local function default_log(fmt, ...)
    print(string.format("[Unlocker] " .. fmt, ...))
end

local function get_logger(opts)
    if opts and opts.logger then return opts.logger end
    return default_log
end

function M.plan(path, opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'unlock_file',
        dry_run = true,
        changed = false,
        path = path,
        steps = {
            { action = 'find_locking_processes', path = path },
            { action = 'terminate_locking_processes', path = path },
            { action = 'retry_delete', path = path },
        },
        warnings = {},
    }
end

-- [API] 强制解锁文件 (查找并终止占用进程)
-- 对标 PECMD FILE -force
-- @param path: 目标文件或目录路径
-- @return: boolean success, number count_killed
function M.unlock_file(path, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan(path, opts) end
    local log = get_logger(opts)
    -- 1. 查找占用该文件的进程 ID 列表
    -- 利用 RestartManager 或 NtQuerySystemInformation (底层封装在 handles.lua 中)
    local pids = win.process.handles.find_lockers(path)
    
    if #pids == 0 then 
        return true, { ok = true, task = 'unlock_file', changed = false, killed_count = 0 }
    end
    
    local killed = 0
    local my_pid = win.process.current().pid
    
    log("Found %d lockers for '%s'", #pids, path)
    
    for _, pid in ipairs(pids) do
        -- 保护自己不被杀
        if pid ~= my_pid then
            -- 尝试终止进程
            local ok, err = win.process.kill(pid)
            if ok then 
                log("Killed PID %d holding file", pid)
                killed = killed + 1
            else
                log("Failed to kill PID %d: %s", pid, tostring(err))
            end
        else
            log("Skipping self (PID %d)", pid)
        end
    end
    
    -- 稍作等待让句柄释放
    win.process.sleep(200)
    
    -- 再次检查是否解锁
    local remaining = win.process.handles.find_lockers(path)
    
    if #remaining > 0 then
        log("Warning: %d lockers remaining.", #remaining)
        return false, { ok = false, task = 'unlock_file', changed = killed > 0, killed_count = killed, remaining_count = #remaining }
    end
    
    return true, { ok = true, task = 'unlock_file', changed = killed > 0, killed_count = killed, remaining_count = 0 }
end

-- [API] 强制删除 (解锁 + 删除)
-- @param path: 路径
-- @return: boolean success
function M.force_delete(path, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan(path, opts) end

    -- 先尝试直接删除，如果失败再尝试解锁
    if win.fs.delete(path) then return true, { ok = true, task = 'force_delete', changed = true, path = path } end
    
    local unlocked, detail = M.unlock_file(path, opts)
    if not unlocked then
        -- 即使解锁不完全也尝试删除一次，也许剩下的只是读取锁
    end
    
    local deleted = win.fs.delete(path)
    return deleted, { ok = deleted, task = 'force_delete', changed = deleted or (detail and detail.changed) or false, path = path, unlock = detail }
end

return M
