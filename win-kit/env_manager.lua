local win = require 'win-utils'
local M = {}

function M.plan_path(action, new_path, scope)
    return {
        ok = true,
        task = 'init_pe',
        dry_run = true,
        changed = false,
        steps = {
            { action = action, path = new_path, scope = scope or 'System' },
        },
        warnings = {},
    }
end

-- [Internal] 规范化 PATH 列表 (去重，移除空项)
local function normalize_path_list(str)
    local list = {}
    local seen = {}
    for p in str:gmatch("[^;]+") do
        local norm = win.core.normalize_path(p):lower() -- 大小写不敏感比较
        if not seen[norm] and p ~= "" then
            table.insert(list, p) -- 保留原始大小写
            seen[norm] = true
        end
    end
    return list
end

-- [API] 追加路径到系统 PATH
-- @param new_path: 要添加的路径
-- @param scope: "System" (默认) 或 "User"
function M.append_path(new_path, scope, opts)
    opts = opts or {}
    scope = scope or "System"
    if opts.dry_run then return true, M.plan_path('append_path', new_path, scope) end

    local current = win.sys.env.get("PATH") or ""
    
    -- 检查是否已存在
    local check_path = win.core.normalize_path(new_path):lower()
    local check_current = ";" .. current:lower() .. ";"
    if check_current:find(";" .. check_path:gsub("%-", "%%-") .. ";", 1, true) then
        return true, { ok = true, task = 'init_pe', changed = false, skipped = true, action = 'append_path', path = new_path, scope = scope }
    end
    
    local new_val = current
    if new_val ~= "" and new_val:sub(-1) ~= ";" then new_val = new_val .. ";" end
    new_val = new_val .. new_path
    
    local ok, err = win.sys.env.set_persistent("PATH", new_val, scope)
    if not ok then return false, err end
    return true, { ok = true, task = 'init_pe', changed = true, action = 'append_path', path = new_path, scope = scope }
end

-- [API] 前置路径到系统 PATH (高优先级)
-- 会将该路径移动到 PATH 的最前面
function M.prepend_path(new_path, scope, opts)
    opts = opts or {}
    scope = scope or "System"
    if opts.dry_run then return true, M.plan_path('prepend_path', new_path, scope) end

    local current = win.sys.env.get("PATH") or ""
    
    -- 移除旧的如果存在，为了置顶
    local list = normalize_path_list(current)
    local final_list = { new_path }
    
    local target = win.core.normalize_path(new_path):lower()
    for _, p in ipairs(list) do
        if win.core.normalize_path(p):lower() ~= target then
            table.insert(final_list, p)
        end
    end
    
    local new_val = table.concat(final_list, ";")
    local ok, err = win.sys.env.set_persistent("PATH", new_val, scope)
    if not ok then return false, err end
    return true, { ok = true, task = 'init_pe', changed = true, action = 'prepend_path', path = new_path, scope = scope }
end

return M
