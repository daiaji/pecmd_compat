local win = require 'win-utils'
local Logic = {}

-- ============================================================================
-- 1. 高级进程执行 (对标 PECMD EXEC*)
-- ============================================================================

-- [API] 执行命令并返回清洗后的输出
-- @param cmd: 命令行
-- @param timeout: 超时时间 (可选)
-- @return: string (输出内容，已去除首尾空白), number (退出码)
function Logic.exec_capture(cmd, timeout)
    -- 调用底层 popen
    local out_raw, exit_code = win.process.popen.run(cmd, {
        show = 0,           -- 隐藏窗口
        include_stderr = true, -- 合并错误输出
        timeout = timeout
    })

    if not out_raw then return "", -1 end

    -- 业务处理：去除首尾空白符 (Trim)
    local out_clean = out_raw:gsub("^%s*(.-)%s*$", "%1")
    
    return out_clean, exit_code
end

-- [API] 像 grep 一样在命令输出中查找特定字符串
-- @return: boolean (是否找到)
function Logic.exec_find(cmd, pattern)
    local out = Logic.exec_capture(cmd)
    if out:find(pattern) then return true end
    return false
end

-- ============================================================================
-- 2. 离线注册表托管 (对标 PECMD HIVE -super)
-- ============================================================================

-- [API] 安全挂载并修复 Hive 权限，执行回调后自动卸载
-- 这是一个“上下文管理器”式的函数，确保 Hive 不会被锁死
-- @param mount_point: 挂载路径 (如 "HKLM\\OFFLINE_SYS")
-- @param hive_file: Hive 文件路径
-- @param func: 回调函数 function(key_object) ... end
-- @return: true/false, error_message
function Logic.with_super_hive(mount_point, hive_file, func)
    -- 1. 加载 Hive
    local ok, err = win.reg.load_hive(mount_point, hive_file)
    if not ok then 
        return false, "LoadHive failed: " .. tostring(err) 
    end

    -- 使用 pcall 确保无论业务逻辑是否出错，都会执行卸载
    local status, result = pcall(function()
        -- 2. [核心业务] 强力重置权限 (HIVE -super)
        -- 这一步对于修改 Win10/11 的离线 SYSTEM/SOFTWARE Hive 至关重要
        local acl_ok, acl_err = win.reg.acl.reset(mount_point)
        if not acl_ok then
            error("ACL Reset failed: " .. tostring(acl_err))
        end

        -- 3. 打开 Key 对象供回调使用
        local root_name = mount_point:match("^[^\\]+")
        local sub_name = mount_point:match("\\(.*)")
        
        local k = win.reg.open_key(root_name, sub_name)
        if not k then error("Open mounted key failed") end
        
        -- 执行用户逻辑
        func(k)
        
        k:close()
    end)

    -- 4. 强制卸载 (带重试机制，防止 Explorer 占用导致卸载失败)
    local unload_ok = false
    for i = 1, 5 do
        win.sys.io.tee(nil) -- 触发一次 GC 
        collectgarbage()
        
        if win.reg.unload_hive(mount_point) then
            unload_ok = true
            break
        end
        win.process.sleep(200) -- 等待 200ms
    end

    if not status then return false, result end -- 业务逻辑报错
    if not unload_ok then return false, "UnloadHive failed (Key locked)" end

    return true
end

return Logic
