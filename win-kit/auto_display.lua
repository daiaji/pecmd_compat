local win = require 'win-utils'

local M = {}

local function default_log(fmt, ...)
    print(string.format("[Display] " .. fmt, ...))
end

local function get_logger(opts)
    if opts and opts.logger then return opts.logger end
    return default_log
end

function M.plan(opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'setup_display',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'enumerate_display_modes' },
            { action = 'select_best_display_mode' },
            { action = 'apply_display_mode' },
        },
        warnings = {},
    }
end

-- [API] 自动应用最佳显示模式
-- 策略：分辨率优先 > 刷新率优先 > 色深优先
function M.auto_set(opts)
    opts = opts or {}
    if opts.dry_run then return true, M.plan(opts) end

    local log = get_logger(opts)
    log("Detecting supported modes...")
    local modes = win.sys.display.get_modes()
    
    if #modes == 0 then 
        return false, "No display modes found" 
    end
    
    -- 排序逻辑
    table.sort(modes, function(a, b)
        local area_a = a.w * a.h
        local area_b = b.w * b.h
        
        -- 1. 像素总数 (面积) 大的优先
        if area_a ~= area_b then return area_a > area_b end
        
        -- 2. 刷新率高的优先
        if a.hz ~= b.hz then return a.hz > b.hz end
        
        -- 3. 色深高的优先
        return a.bpp > b.bpp
    end)
    
    local best = modes[1]
    log("Applying best mode: %dx%d @ %dHz (%d bit)", best.w, best.h, best.hz, best.bpp)
    
    local ok, err = win.sys.display.set_res(best.w, best.h, best.hz, best.bpp)
    if not ok then
        return false, "Failed to apply mode: " .. tostring(err)
    end
    
    return true, { ok = true, task = 'setup_display', changed = true, mode = best }
end

return M
