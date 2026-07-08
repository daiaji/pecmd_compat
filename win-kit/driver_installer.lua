local win = require 'win-utils'

local M = {}

function M.plan(cab_path, opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'install_drivers',
        dry_run = true,
        changed = false,
        cab_path = cab_path,
        steps = {
            { action = 'extract_cab', path = cab_path },
            { action = 'scan_extracted_inf_files' },
            { action = 'install_extracted_inf_files' },
            { action = 'cleanup_extract_dir' },
        },
        warnings = {},
    }
end

-- [API] 安装 CAB 驱动包并显示详细进度
-- @param cab_path: CAB 文件路径
-- @return: boolean success
function M.install_cab_verbose(cab_path, opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan(cab_path, opts) end

    print("[DriverInstall] Processing CAB: " .. cab_path)
    
    local extract_dir = os.getenv("TEMP") .. "\\Drv_Extract_" .. os.time()
    local count = 0
    
    -- 1. 解压并显示进度 (仅解压，不安装)
    print("[DriverInstall] Extracting...")
    local ok, res = win.sys.driver.install_cab(cab_path, extract_dir, function(stage, name, size)
        if stage == "extracting" then
            count = count + 1
            -- 每解压 10 个文件打印一个点，避免刷屏
            if count % 10 == 0 then io.write("."); io.flush() end
        end
        return true -- Continue
    end)
    print("\n[DriverInstall] Extraction complete.")
    
    if not ok then 
        print("[DriverInstall] Extraction failed: " .. tostring(res))
        return false, res 
    end
    
    -- 2. 显式调用 scanner 递归安装 (因为 win-utils 已解耦)
    print("[DriverInstall] Scanning for INF files and installing...")
    
    -- res 包含 extracted_path，如果 win-utils 版本正确返回
    local target_path = (type(res) == "table" and res.extracted_path) or extract_dir
    
    local scanner = require 'win-kit.driver_scanner' -- 使用新的扫描模块
    local s_cnt, f_cnt, errs = scanner.install_recursive(target_path, {
        cb = function(path, idx, total)
            -- 显示简短文件名
            local basename = win.fs.path.basename(path)
            print(string.format("  [%d/%d] Installing: %s", idx, total, basename))
        end
    })
    
    -- 3. 清理
    print("[DriverInstall] Cleaning up temp files...")
    win.fs.delete(target_path)
    
    print(string.format("[DriverInstall] Result: %d Success, %d Failed.", s_cnt, f_cnt))
    
    if #errs > 0 then
        print("[DriverInstall] Errors:")
        for _, e in ipairs(errs) do print("  - " .. e) end
    end
    
    return true, { ok = true, task = 'install_drivers', changed = s_cnt > 0, success_count = s_cnt, fail_count = f_cnt, errors = errs }
end

return M
