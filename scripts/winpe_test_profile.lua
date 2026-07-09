-- winpe_test_profile.lua
-- WinPE CI test profile: runs win-kit tasks in QEMU and writes results to stdout.
-- This profile is injected into boot.wim and executed by pe_ci_run.cmd.
--
-- Output protocol (written to stdout, captured by pe_ci_run.cmd):
--   WINPE_CI_START
--   WINPE_CI_TASK: <name> ... PASS|FAIL|SKIP
--   WINPE_CI_RESULT: <task> <status> <detail>
--   WINPE_CI_SUMMARY: <passed> <failed> <skipped>
--   WINPE_CI_EXIT: <code>

-- Set up package path for WinPE environment
local system32 = os.getenv("SYSTEMROOT") or "X:\\Windows"
local lua_dir = system32 .. "\\System32\\lua"
package.path = lua_dir .. "\\?.lua;" .. lua_dir .. "\\?\\init.lua;;"

local function emit(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    io.write(line, "\n")
    io.flush()
end

print = emit

local log = _G.log or {
    info = function(...) print(...) end,
    warn = function(...) print("[WARN]", ...) end,
    error = function(...) print("[ERROR]", ...) end,
    critical = function(...) print("[CRITICAL]", ...) end,
}

local runner = require("tasks.runner")

-- Test profile: runs all tasks in dry_run mode first, then non-destructive tasks for real
local dry_run_profile = {
    name = "winpe-ci",
    dry_run = false,
    defaults = {},
    order = {
        'init_pe',
        'assign_drive_letters',
        'setup_display',
        'setup_network',
    },
    tasks = {
        init_pe = {
            refresh_icons = false,
        },
        install_drivers = false,  -- No real drivers in QEMU
        assign_drive_letters = {},  -- API validation only in dry-run plan
        setup_pagefile = false,  -- Skip in QEMU (no persistent disk)
        setup_display = {},  -- Safe: queries display info
        setup_network = false,  -- Skip: QEMU network is limited
        shutdown_cleanup = false,  -- We handle shutdown via QEMU
    },
}

local run_profile = {
    name = dry_run_profile.name,
    dry_run = false,
    defaults = dry_run_profile.defaults,
    order = dry_run_profile.order,
    tasks = {
        init_pe = {
            refresh_icons = false,
        },
        install_drivers = false,
        assign_drive_letters = false,  -- Avoid changing CI result drive letters
        setup_pagefile = false,
        setup_display = false,  -- Dry-run only; changing display mode can reset QEMU output
        setup_network = false,
        shutdown_cleanup = false,
    },
}

local pass = 0
local fail = 0
local skip = 0

print("WINPE_CI_START")
print("WINPE_CI_INFO: profile=" .. dry_run_profile.name)
log.info("WinPE CI test started")

-- Phase 1: Dry-run plan (validate all task APIs work)
print("WINPE_CI_PHASE: dry_run_plan")
local plan, plan_err = runner.plan(dry_run_profile, {})
if not plan then
    print("WINPE_CI_FATAL: plan failed: " .. tostring(plan_err))
    print("WINPE_CI_EXIT: 1")
    return 1
end

for _, task_plan in ipairs(plan.tasks or {}) do
    if task_plan.ok then
        print("WINPE_CI_TASK: " .. task_plan.task .. " PLAN PASS (" .. #task_plan.steps .. " steps)")
        pass = pass + 1
    else
        print("WINPE_CI_TASK: " .. tostring(task_plan.task) .. " PLAN FAIL")
        fail = fail + 1
    end
end

-- Phase 2: Real execution of non-destructive tasks
print("WINPE_CI_PHASE: real_execution")
log.info("Running non-destructive tasks...")

-- Custom progress handler that outputs to the CI result log
local function on_progress(name, i, total)
    print(string.format("WINPE_CI_PROGRESS: %s (%d/%d)", name, i, total))
end

local function on_task_complete(name, result, err)
    if result and result.ok then
        print("WINPE_CI_RESULT: " .. name .. " PASS")
        pass = pass + 1
    elseif result and result.skipped then
        print("WINPE_CI_RESULT: " .. name .. " SKIP")
        skip = skip + 1
    else
        print("WINPE_CI_RESULT: " .. name .. " FAIL: " .. tostring(err and err.error or err or "unknown"))
        fail = fail + 1
    end
end

local run_result, run_err = runner.run(run_profile, {
    logger = log,
    on_progress = on_progress,
    on_task_complete = on_task_complete,
})

if not run_result then
    print("WINPE_CI_FATAL: run failed: " .. tostring(run_err and run_err.error or run_err))
    fail = fail + 1
end

-- Phase 3: WinPE-specific environment checks
print("WINPE_CI_PHASE: environment_checks")

local checks = {
    {"firmware_type", function()
        local info = require("win-utils.sys.info")
        local firmware = info.get_firmware_type()
        return firmware ~= nil, "firmware=" .. tostring(firmware)
    end},
    {"is_winpe", function()
        local info = require("win-utils.sys.info")
        local pe = info.is_winpe()
        return pe == true, "is_winpe=" .. tostring(pe)
    end},
    {"memory_info", function()
        local info = require("win-utils.sys.info")
        local mem, err = info.get_memory_info()
        if not mem then return false, tostring(err) end
        return true, "total_mb=" .. tostring(mem.total_mb) .. ",avail_mb=" .. tostring(mem.avail_mb)
    end},
    {"power_status", function()
        local info = require("win-utils.sys.info")
        local ps, err = info.get_power_status()
        if not ps then return false, tostring(err) end
        return true, "ac_line_status=" .. tostring(ps.ac_line_status)
    end},
    {"process_list", function()
        local process = require("win-utils.process.init")
        local procs = process.list()
        return procs ~= nil and #procs > 0, "count=" .. tostring(procs and #procs or 0)
    end},
    {"disk_physical_list", function()
        local physical = require("win-utils.disk.physical")
        local disks = physical.list()
        return disks ~= nil, "count=" .. tostring(disks and #disks or 0)
    end},
    {"volume_list", function()
        local volume = require("win-utils.disk.volume")
        local vols = volume.list()
        return vols ~= nil, "count=" .. tostring(vols and #vols or 0)
    end},
    {"service_list", function()
        local service = require("win-utils.sys.service")
        local svcs = service.list()
        return svcs ~= nil and #svcs > 0, "count=" .. tostring(svcs and #svcs or 0)
    end},
}

for _, check in ipairs(checks) do
    local name, fn = check[1], check[2]
    print("WINPE_CI_CHECK_BEGIN: " .. name)
    local ok, success, msg = pcall(fn)
    if not ok then
        print("WINPE_CI_CHECK: " .. name .. " ERROR (" .. tostring(success) .. ")")
        fail = fail + 1
    elseif success then
        print("WINPE_CI_CHECK: " .. name .. " PASS (" .. tostring(msg) .. ")")
        pass = pass + 1
    else
        print("WINPE_CI_CHECK: " .. name .. " FAIL (" .. tostring(msg) .. ")")
        fail = fail + 1
    end
end

-- Summary
print(string.format("WINPE_CI_SUMMARY: %d %d %d", pass, fail, skip))
log.info(string.format("WinPE CI complete: %d passed, %d failed, %d skipped", pass, fail, skip))

local exit_code = fail > 0 and 1 or 0
print("WINPE_CI_EXIT: " .. exit_code)
return exit_code
