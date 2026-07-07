local win = require 'win-utils'

local M = {}

-- [API] 强制解锁文件 (查找并终止占用进程)
-- 对标 PECMD FILE -force
-- @param path: 目标文件或目录路径
-- @return: boolean success, number count_killed
function M.unlock_file(path)
    -- 1. 查找占用该文件的进程 ID 列表
    -- 利用 RestartManager 或 NtQuerySystemInformation (底层封装在 handles.lua 中)
    local pids = win.process.handles.find_lockers(path)
    
    if #pids == 0 then 
        return true, 0 
    end
    
    local killed = 0
    local my_pid = win.process.current().pid
    
    print(string.format("[Unlocker] Found %d lockers for '%s'", #pids, path))
    
    for _, pid in ipairs(pids) do
        -- 保护自己不被杀
        if pid ~= my_pid then
            -- 尝试终止进程
            local ok, err = win.process.kill(pid)
            if ok then 
                print(string.format("  > Killed PID %d holding file", pid))
                killed = killed + 1
            else
                print(string.format("  > Failed to kill PID %d: %s", pid, tostring(err)))
            end
        else
            print("  > Skipping self (PID " .. pid .. ")")
        end
    end
    
    -- 稍作等待让句柄释放
    win.process.sleep(200)
    
    -- 再次检查是否解锁
    local remaining = win.process.handles.find_lockers(path)
    
    if #remaining > 0 then
        print(string.format("[Unlocker] Warning: %d lockers remaining.", #remaining))
        return false, killed
    end
    
    return true, killed
end

-- [API] 强制删除 (解锁 + 删除)
-- @param path: 路径
-- @return: boolean success
function M.force_delete(path)
    -- 先尝试直接删除，如果失败再尝试解锁
    if win.fs.delete(path) then return true end
    
    local unlocked, count = M.unlock_file(path)
    if not unlocked then
        -- 即使解锁不完全也尝试删除一次，也许剩下的只是读取锁
    end
    
    return win.fs.delete(path)
end

return M