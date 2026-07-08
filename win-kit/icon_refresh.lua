local win = require 'win-utils'

local M = {}

local function default_log(fmt, ...)
    print(string.format("[IconRefresh] " .. fmt, ...))
end

local function get_logger(opts)
    if opts and opts.logger then return opts.logger end
    return default_log
end

function M.plan(opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'refresh_icon_cache',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'stop_explorer' },
            { action = 'delete_icon_cache_files' },
            { action = 'restart_explorer' },
        },
        warnings = {},
    }
end

-- [API] 刷新桌面图标缓存
-- 对标 PECMD ENVI @@DeskTopFresh
function M.refresh_icons(opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan(opts) end

    local log = get_logger(opts)
    log("Stopping Explorer process...")
    local killed = 0
    local deleted = 0
    local failed = 0
    
    -- 1. 终止所有 Explorer 进程
    local list = win.process.list()
    for _, p in ipairs(list) do
        if p.name:lower() == "explorer.exe" then
            local ok = win.process.kill(p.pid)
            if ok then killed = killed + 1 end
        end
    end
    
    -- 等待进程退出
    win.process.sleep(500)
    
    -- 2. 定位并删除缓存文件
    -- 路径通常是 %LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache*.db
    local local_app = win.sys.env.get("LOCALAPPDATA")
    if not local_app then return false, "LOCALAPPDATA not found" end
    
    local cache_dir = local_app .. "\\Microsoft\\Windows\\Explorer"
    
    log("Clearing cache in: %s", cache_dir)
    
    if win.fs.is_dir(cache_dir) then
        -- 使用 scandir 查找匹配的文件
        for name, attr in win.fs.scandir(cache_dir) do
            if name:match("^iconcache_.*%.db$") then
                local full_path = cache_dir .. "\\" .. name
                -- 尝试删除，因为 explorer 已杀，应该没有锁
                if win.fs.delete(full_path) then
                    log("Deleted %s", name)
                    deleted = deleted + 1
                else
                    log("Failed to delete %s", name)
                    failed = failed + 1
                end
            end
        end
    else
        log("Warning: Cache dir not found")
    end
    
    -- 3. 重启 Explorer
    -- 我们只在有桌面环境的情况下重启 explorer
    -- 在 WinPE CMD 模式下可能不需要
    log("Restarting Explorer...")
    
    -- 使用 ShellExecute 启动，不等待
    win.process.exec("explorer.exe", nil, 1)
    
    return true, { ok = true, task = 'refresh_icon_cache', changed = killed > 0 or deleted > 0, killed_explorer_count = killed, deleted_cache_count = deleted, failed_delete_count = failed }
end

return M
