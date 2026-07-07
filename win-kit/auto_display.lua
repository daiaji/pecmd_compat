local win = require 'win-utils'

local M = {}

-- [API] 自动应用最佳显示模式
-- 策略：分辨率优先 > 刷新率优先 > 色深优先
function M.auto_set()
    print("[Display] Detecting supported modes...")
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
    print(string.format("[Display] Applying best mode: %dx%d @ %dHz (%d bit)", 
        best.w, best.h, best.hz, best.bpp))
    
    local ok, err = win.sys.display.set_res(best.w, best.h, best.hz, best.bpp)
    if not ok then
        return false, "Failed to apply mode: " .. tostring(err)
    end
    
    return true
end

return M