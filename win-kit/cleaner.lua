local win = require 'win-utils'
local unlocker = require 'win-kit.unlocker'
local bit = require 'bit'

local M = {}

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
    print("[Cleaner] Cleaning: " .. target)
    
    local count = 0
    local fails = 0
    
    if not win.fs.is_dir(target) then return true end
    
    -- 递归删除内容
    for name, attr in win.fs.scandir(target) do
        if name ~= "." and name ~= ".." then
            local full = target .. "\\" .. name
            local is_dir = (bit.band(attr, 0x10) ~= 0)
            
            local ok = false
            if is_dir then
                -- 递归调用自身清理子目录
                -- 这里返回值是 (success, count) tuple, 只取 success
                local sub_ok = M.clean_dir(full, {self_delete=true})
                ok = sub_ok
            else
                -- 尝试强制删除文件 (利用 unlocker)
                ok = unlocker.force_delete(full)
            end
            
            if ok then count = count + 1 else fails = fails + 1 end
        end
    end
    
    -- 如果需要删除目录本身
    if opts.self_delete then
        if not win.fs.delete(target) then fails = fails + 1 end
    end
    
    return fails == 0, count
end

-- [API] 标准临时文件清理流程
function M.cleanup_standard()
    local dirs = {
        win.sys.env.get("TEMP"),
        win.sys.env.get("SystemRoot") .. "\\Temp"
    }
    
    for _, d in ipairs(dirs) do
        if d and win.fs.exists(d) then
            M.clean_dir(d, {self_delete=false}) -- 保留 TEMP 根目录
        end
    end
end

return M