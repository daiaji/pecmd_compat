local win = require 'win-utils'

local M = {}

-- [API] 刷新桌面图标缓存
-- 对标 PECMD ENVI @@DeskTopFresh
function M.refresh_icons()
    print("[IconRefresh] Stopping Explorer process...")
    
    -- 1. 终止所有 Explorer 进程
    local list = win.process.list()
    for _, p in ipairs(list) do
        if p.name:lower() == "explorer.exe" then
            win.process.kill(p.pid)
        end
    end
    
    -- 等待进程退出
    win.process.sleep(500)
    
    -- 2. 定位并删除缓存文件
    -- 路径通常是 %LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache*.db
    local local_app = win.sys.env.get("LOCALAPPDATA")
    if not local_app then return false, "LOCALAPPDATA not found" end
    
    local cache_dir = local_app .. "\\Microsoft\\Windows\\Explorer"
    
    print("[IconRefresh] Clearing cache in: " .. cache_dir)
    
    if win.fs.is_dir(cache_dir) then
        -- 使用 scandir 查找匹配的文件
        for name, attr in win.fs.scandir(cache_dir) do
            if name:match("^iconcache_.*%.db$") then
                local full_path = cache_dir .. "\\" .. name
                -- 尝试删除，因为 explorer 已杀，应该没有锁
                if win.fs.delete(full_path) then
                    print("  > Deleted " .. name)
                else
                    print("  > Failed to delete " .. name)
                end
            end
        end
    else
        print("[IconRefresh] Warning: Cache dir not found")
    end
    
    -- 3. 重启 Explorer
    -- 我们只在有桌面环境的情况下重启 explorer
    -- 在 WinPE CMD 模式下可能不需要
    print("[IconRefresh] Restarting Explorer...")
    
    -- 使用 ShellExecute 启动，不等待
    win.process.exec("explorer.exe", nil, 1)
    
    return true
end

return M