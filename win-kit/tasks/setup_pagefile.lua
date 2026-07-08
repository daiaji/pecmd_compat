local smart_pagefile = require 'win-kit.smart_pagefile'

local M = {}

function M.plan(opts)
    opts = opts or {}
    return {
        ok = true,
        task = 'setup_pagefile',
        dry_run = true,
        changed = false,
        steps = {
            { action = 'query_memory' },
            { action = 'select_fixed_drive', size_mb = opts.size_mb or opts.page_size_mb or 1024 },
            { action = 'create_pagefile', size_mb = opts.size_mb or opts.page_size_mb or 1024 },
        },
        warnings = {},
    }
end

function M.run(opts)
    opts = opts or {}
    if opts.dry_run then
        return M.plan(opts)
    end

    local min_ram_mb = opts.min_ram_mb or 4096
    local page_size_mb = opts.size_mb or opts.page_size_mb or 1024
    local ok, err = smart_pagefile.smart_set(min_ram_mb, page_size_mb, opts)
    if not ok then
        return nil, { task = 'setup_pagefile', code = 'pagefile_setup_failed', message = tostring(err) }
    end

    return err or { ok = true, task = 'setup_pagefile', changed = true }
end

return M
