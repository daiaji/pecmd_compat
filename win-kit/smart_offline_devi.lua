local win = require 'win-utils'
local bit = require 'bit'

-- ============================================================================
-- 配置区域
-- ============================================================================
-- 模拟场景：
-- 当前系统是 WinPE，挂载了目标系统到 D:\
-- 驱动包位于 U:\Drivers
local DRIVER_SOURCE = [[U:\Drivers]]
local OFFLINE_IMAGE = [[D:\]]

print("=== Smart Offline DEVI Demo ===")
print("Context: Injecting drivers from " .. DRIVER_SOURCE .. " into offline image " .. OFFLINE_IMAGE)

-- ============================================================================
-- 1. 扫描本机硬件 ID
-- ============================================================================
-- 即便是离线注入，我们通常也是为了让目标系统能在 *当前机器* 上启动，
-- 所以我们依据当前 WinPE 识别到的物理硬件 ID 进行匹配。
print("\n[Step 1] Scanning local hardware IDs...")

-- enum_devices 默认返回所有设备
local local_devs = win.sys.dev_info.enum_devices({ present = true })
if not local_devs then
    print("Error: Failed to enumerate devices.")
    return
end

-- 构建目标 ID 查找表 (Set)
local target_ids = {}
local id_count = 0

for _, dev in ipairs(local_devs) do
    if dev.hwids then
        for _, id in ipairs(dev.hwids) do 
            target_ids[id:upper()] = true 
            id_count = id_count + 1
        end
    end
    if dev.compat_ids then
        for _, id in ipairs(dev.compat_ids) do 
            target_ids[id:upper()] = true 
            id_count = id_count + 1
        end
    end
end

print(string.format("    Found %d devices, collected %d unique hardware IDs.", #local_devs, id_count))

-- ============================================================================
-- 2. 扫描并匹配 INF 文件
-- ============================================================================
print(string.format("\n[Step 2] Scanning drivers in '%s'...", DRIVER_SOURCE))

if not win.fs.is_dir(DRIVER_SOURCE) then
    print("Error: Driver source directory not found. Please update DRIVER_SOURCE path.")
    return
end

local matched_infs = {}

-- 递归扫描函数
local function scan_match_recursive(dir)
    for name, attr in win.fs.scandir(dir) do
        if name ~= "." and name ~= ".." then
            local full_path = dir .. "\\" .. name
            local is_dir = bit.band(attr, 0x10) ~= 0
            
            if is_dir then
                scan_match_recursive(full_path)
            elseif name:match("%.[iI][nN][fF]$") then
                -- 核心逻辑：调用 sys.inf 模块解析 INF
                local supported_ids = win.sys.inf.get_hwids(full_path)
                
                if supported_ids then
                    -- 检查该 INF 支持的 ID 是否在我们的目标硬件列表中
                    for id, _ in pairs(supported_ids) do
                        if target_ids[id:upper()] then
                            print("    [MATCH] " .. name .. " matches hardware " .. id)
                            table.insert(matched_infs, full_path)
                            break -- 只要匹配到一个 ID，该 INF 就需要安装
                        end
                    end
                end
            end
        end
    end
end

scan_match_recursive(DRIVER_SOURCE)
print(string.format("    Total matched INF files: %d", #matched_infs))

-- ============================================================================
-- 3. 执行离线注入
-- ============================================================================
if #matched_infs == 0 then
    print("\n[Step 3] No matching drivers found to inject.")
    return
end

print(string.format("\n[Step 3] Injecting into offline image: %s", OFFLINE_IMAGE))

-- 调用 DismApi 批量注入
-- 我们逐个注入以便于显示进度
for i, inf in ipairs(matched_infs) do
    io.write(string.format("    [%d/%d] Injecting %s ... ", i, #matched_infs, win.fs.path.basename(inf)))
    
    local ok, res = win.sys.dism.add_driver_offline(OFFLINE_IMAGE, inf, { force_unsigned = true })
    
    if ok then
        print("OK")
    else
        print("FAILED")
        if type(res) == "string" then 
            print("      Error: " .. res) 
        elseif type(res) == "table" and res.errors then
            for _, e in ipairs(res.errors) do 
                print("      Log: " .. e) 
            end
        end
    end
end

-- 清理 DISM 资源
win.sys.dism.shutdown()

print("\n=== Driver Injection Completed ===")