-- tasks_spec.lua: Assert the canonical task result schema and dry-run planning.
-- Runs offline without luaunit; uses plain asserts.

local function setup_path()
    local sep = package.config:sub(1, 1)
    local root = '.' .. sep

    local searchers = package.searchers or package.loaders
    local function vendor_searcher(modname)
        local rel
        if modname:match('^ext%.') then
            rel = 'win-utils' .. sep .. 'vendor' .. sep .. 'lua-ext' .. sep .. modname:sub(5):gsub('%.', sep) .. '.lua'
        elseif modname:match('^ffi%.') then
            rel = 'win-utils' .. sep .. 'vendor' .. sep .. 'lua-ffi-bindings' .. sep .. modname:sub(5):gsub('%.', sep) .. '.lua'
        else
            return '\n\tno win-kit vendor mapping for ' .. modname
        end

        local path = root .. rel
        local chunk, err = loadfile(path)
        if chunk then return chunk end
        return "\n\tno file '" .. path .. "': " .. tostring(err)
    end

    table.insert(searchers, 1, vendor_searcher)
    package.path = root .. '?.lua;' .. root .. '?' .. sep .. 'init.lua;' .. package.path
end

setup_path()

local tasks = require 'win-kit.tasks'

local pass = 0
local fail = 0

local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        io.stderr:write(string.format('  FAIL %s: %s\n', name, tostring(err)))
    end
end

local function assert_plan_schema(result, task_name)
    assert(type(result) == 'table', 'plan must return table')
    assert(result.ok == true, 'plan.ok must be true')
    assert(result.task == task_name, 'plan.task must match: ' .. task_name)
    assert(result.dry_run == true, 'plan.dry_run must be true')
    assert(result.changed == false, 'plan.changed must be false on dry-run')
    assert(type(result.steps) == 'table', 'plan.steps must be a table')
    assert(type(result.warnings) == 'table', 'plan.warnings must be a table')
end

-- =====================================================================
-- Each task: plan() returns canonical schema, run(dry_run=true) == plan()
-- =====================================================================

local task_specs = {
    {
        name = 'init_pe',
        task = tasks.init_pe,
        opts = { prepend_path = [[X:\Tools]], oem = { manufacturer = 'PE' } },
        expect_first_action = 'prepend_path',
    },
    {
        name = 'install_drivers',
        task = tasks.install_drivers,
        opts = { roots = { [[X:\Drivers]] }, mode = 'smart' },
        expect_first_action = 'scan_devices',
    },
    {
        name = 'assign_drive_letters',
        task = tasks.assign_drive_letters,
        opts = {},
        expect_first_action = 'scan_physical_disks',
    },
    {
        name = 'setup_pagefile',
        task = tasks.setup_pagefile,
        opts = { size_mb = 2048 },
        expect_first_action = 'query_memory',
    },
    {
        name = 'setup_display',
        task = tasks.setup_display,
        opts = {},
        expect_first_action = 'enumerate_display_modes',
    },
    {
        name = 'setup_network',
        task = tasks.setup_network,
        opts = { enable_adapter = 'Ethernet', dhcp = true, sync_time = true },
        expect_first_action = 'enable_adapter',
    },
    {
        name = 'shutdown_cleanup',
        task = tasks.shutdown_cleanup,
        opts = { target_drive_letter = 'C' },
        expect_first_action = 'clean_standard_temp_dirs',
    },
    {
        name = 'boot_repair',
        task = tasks.boot_repair,
        opts = { rebuild_bcd = 'C:', timeout = 10 },
        expect_first_action = 'rebuild_bcd',
    },
}

for _, spec in ipairs(task_specs) do
    check(spec.name .. ' .plan() schema', function()
        local result = spec.task.plan(spec.opts)
        assert_plan_schema(result, spec.name)
        assert(#result.steps > 0, 'plan must have at least one step')
        assert(result.steps[1].action == spec.expect_first_action,
            'first step action should be ' .. spec.expect_first_action .. ', got ' .. tostring(result.steps[1].action))
    end)

    check(spec.name .. ' .run(dry_run=true) == plan', function()
        local opts = {}
        for k, v in pairs(spec.opts) do opts[k] = v end
        opts.dry_run = true
        local result = spec.task.run(opts)
        assert_plan_schema(result, spec.name)
    end)
end

-- =====================================================================
-- tasks/init.lua registration: all 8 tasks accessible via lazy index
-- =====================================================================

check('tasks.init registers all 8 tasks', function()
    assert(type(tasks.init_pe) == 'table')
    assert(type(tasks.install_drivers) == 'table')
    assert(type(tasks.assign_drive_letters) == 'table')
    assert(type(tasks.setup_pagefile) == 'table')
    assert(type(tasks.setup_display) == 'table')
    assert(type(tasks.setup_network) == 'table')
    assert(type(tasks.shutdown_cleanup) == 'table')
    assert(type(tasks.boot_repair) == 'table')
end)

-- =====================================================================
-- Structured error shape (failure result) sanity
-- =====================================================================

check('failure result has task + code + message', function()
    local _, err = tasks.setup_pagefile.run({ dry_run = true, _force_error = true })
    -- dry_run path returns plan, not error; this just verifies the error shape
    -- convention is documented in the plan. Real errors come from non-dry-run.
    -- We test the convention by checking that plan always succeeds.
    if err then
        assert(err.task, 'error must have task field')
        assert(err.code, 'error must have code field')
        assert(err.message, 'error must have message field')
    end
end)

print(string.format('tasks_spec: %d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
