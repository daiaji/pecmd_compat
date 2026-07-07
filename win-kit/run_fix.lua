-- 设置包路径以便找到模块 (如果是独立运行需要)
package.path = package.path .. ";..\\?.lua;..\\..\\?.lua"

local win = require 'win-utils'
local logic = require 'win-kit.pecmd_logic'

print("=== Win-Utils Business Logic Demo ===")

-- ----------------------------------------------------------------------------
-- 场景 A: 网络诊断 (利用 EXEC*)
-- ----------------------------------------------------------------------------
print("\n[Step 1] Network Diagnostics...")

-- 1. 获取 IP 配置
local ip_info, code = logic.exec_capture("ipconfig")
if code == 0 then
    print("  > IPConfig output length: " .. #ip_info .. " bytes")
    if ip_info:find("IPv4") then
        local ip = ip_info:match("IPv4.-: ([%d%.]+)")
        print("  > Detected IP: " .. (ip or "Unknown"))
    else
        print("  > No IPv4 address found.")
    end
else
    print("  > Error running ipconfig: " .. code)
end

-- 2. 检测连通性 (简单判断)
print("  > Pinging localhost...")
if logic.exec_find("ping -n 1 127.0.0.1", "TTL=") then
    print("  > Network Stack OK.")
else
    print("  > Network Stack Failure.")
end

-- ----------------------------------------------------------------------------
-- 场景 B: 离线系统修复 (利用 HIVE -super)
-- ----------------------------------------------------------------------------
print("\n[Step 2] Offline System Repair...")

-- 1. 寻找目标系统 (简单模拟，遍历 C-F 盘)
local target_hive = nil
for _, drive in ipairs({"C:", "D:", "E:", "F:"}) do
    local path = drive .. "\\Windows\\System32\\config\\SOFTWARE"
    if win.fs.exists(path) then
        target_hive = path
        print("  > Found offline Windows on: " .. drive)
        break
    end
end

if not target_hive then
    print("  > No offline Windows found. Skipping registry test.")
    -- 为了演示代码能跑通，如果没找到真实系统，我们尝试创建一个临时 Hive
    print("  > [Demo] Creating a dummy hive for testing...")
    target_hive = os.getenv("TEMP") .. "\\test_hive_" .. os.time()
    -- 利用 reg save 生成一个合法的 Hive 文件结构
    local k = win.reg.open_key("HKCU", "Software\\Microsoft")
    win.reg.save_hive(k, target_hive)
    k:close()
end

-- 2. 挂载并修复
-- 挂载点：HKLM\pe_repair_tmp
local mount_point = "HKLM\\pe_repair_tmp"

print("  > Mounting Hive: " .. target_hive)
print("  > Applying ACL Reset (HIVE -super)...")

local ok, err = logic.with_super_hive(mount_point, target_hive, function(root_key)
    print("    [Inside Callback] Hive is mounted and writable.")
    
    -- 业务：注入自启动修复工具
    -- 在 HKLM\pe_repair_tmp\Microsoft\Windows\CurrentVersion\RunOnce 下写入
    local sub_key = "Microsoft\\Windows\\CurrentVersion\\RunOnce"
    
    -- 创建或打开子键
    local k_run = win.reg.open_key(root_key.hkey, sub_key) -- 使用底层句柄
    
    if not k_run then
        -- 如果不存在（例如是空 Hive），我们就在根目录下写一个测试值
        print("    > RunOnce not found, writing to root...")
        root_key:write("PE_Repair_Log", "Fixed by Lua at " .. os.date())
    else
        print("    > Injecting RunOnce entry...")
        local w_ok, w_err = k_run:write("PE_Fixer", "X:\\Tools\\FixSystem.exe /silent")
        if w_ok then
            print("    > Write Success!")
        else
            print("    > Write Failed: " .. tostring(w_err))
        end
        k_run:close()
    end
    
    -- 读取验证
    local val = root_key:read("PE_Repair_Log")
    if val then print("    > Verification Read: " .. val) end
end)

if ok then
    print("  > Operation Completed Successfully.")
else
    print("  > Operation Failed: " .. tostring(err))
end

-- 清理测试文件
if target_hive:find("test_hive") then
    os.remove(target_hive)
end

print("\n=== Demo Finished ===")