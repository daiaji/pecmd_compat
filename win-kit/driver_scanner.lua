local ffi = require 'ffi'
local win = require 'win-utils'
local util = win.core
local fs = win.fs

local M = {}

-- 辅助：获取文件扩展名 (包含点)
local function get_ext(path)
    return path:match("^.+(%.[^\\/]+)$")
end

-- [API] 递归扫描指定目录并安装所有 INF 驱动
-- 模拟 PECMD 的 DEVI 命令
-- @param root_path: 驱动根目录路径 (如 "C:\Drivers")
-- @param opts: 配置选项表
--    opts.recursive: boolean, 是否递归子目录 (默认 true)
--    opts.force: boolean, 是否强制安装 (默认 false)
--    opts.cb: function(current_file_path, current_index, total_count), 进度回调
-- @return: success_count, fail_count, error_list
function M.install_recursive(root_path, opts)
    opts = opts or {}
    local recursive = opts.recursive ~= false
    local force = opts.force or false
    local cb = opts.cb
    
    local errors = {}
    local success_count = 0
    local fail_count = 0
    
    -- 0. 验证目录
    if not fs.is_dir(root_path) then
        return 0, 0, { "Root path directory not found: " .. tostring(root_path) }
    end

    -- 1. 第一阶段：扫描所有 INF 文件
    -- 这一步可能会比较慢，具体取决于文件数量，但在 WinPE 内存盘中通常很快
    local inf_files = {}
    
    local function scan(dir)
        local iter = fs.scandir(dir)
        for name, attr in iter do
            -- 忽略 . 和 ..
            if name ~= "." and name ~= ".." then
                local full_path = dir .. "\\" .. name
                
                -- 判断属性
                local is_dir = (bit.band(attr, 0x10) ~= 0)
                
                if is_dir then
                    if recursive then scan(full_path) end
                else
                    local ext = get_ext(name)
                    if ext and ext:lower() == ".inf" then
                        table.insert(inf_files, full_path)
                    end
                end
            end
        end
    end
    
    scan(util.normalize_path(root_path))
    
    local total = #inf_files
    if total == 0 then
        return 0, 0, {} -- 无驱动文件
    end
    
    -- 2. 第二阶段：批量安装
    for i, inf_path in ipairs(inf_files) do
        if cb then
            -- 安全回调
            xpcall(function() cb(inf_path, i, total) end, debug.traceback)
        end
        
        -- 策略 A: 尝试完整安装 (DiInstallDriverW)
        -- 这会尝试匹配硬件并安装驱动，最为彻底
        local ok, reboot_req = win.sys.driver.install(inf_path, force)
        
        if ok then
            success_count = success_count + 1
        else
            -- 策略 B: 预注入驱动存储区 (SetupCopyOEMInfW)
            -- 如果 DiInstallDriver 失败（例如当前没有对应的硬件插入），
            -- 我们仍然希望将驱动加入 Store，以便后续硬件插入时能自动识别。
            local ok_store, err_store = win.sys.driver.add_to_store(inf_path)
            
            if ok_store then
                -- 视为一种"软成功"
                success_count = success_count + 1
            else
                fail_count = fail_count + 1
                local msg = string.format("%s: Install failed, Store failed (%s)", fs.path.basename(inf_path), tostring(err_store))
                table.insert(errors, msg)
            end
        end
    end
    
    return success_count, fail_count, errors
end

return M