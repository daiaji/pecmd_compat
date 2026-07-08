-- winpe_test_profile.lua
-- WinPE CI test profile: runs win-kit tasks in QEMU and outputs results via serial.
-- This profile is injected into boot.wim and executed by peshell via winpeshl.ini.
--
-- Output protocol (written to stdout, captured by QEMU serial):
--   WINPE_CI_START
--   WINPE_CI_TASK: <name> ... PASS|FAIL|SKIP
--   WINPE_CI_RESULT: <task> <status> <detail>
--   WINPE_CI_SUMMARY: <passed> <failed> <skipped>
--   WINPE_CI_EXIT: <code>

-- Set up package path for WinPE environment
local system32 = os.getenv("SYSTEMROOT") or "X:\\Windows"
local lua_dir = system32 .. "\\System32\\lua"
package.path = lua_dir .. "\\?.lua;" .. lua_dir .. "\\?\\init.lua;;"

local raw_print = print
local serial = io.open("COM1", "w")
local function emit(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    raw_print(line)
    if serial then
        serial:write(line, "\r\n")
        serial:flush()
    end
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
local test_profile = {
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
        assign_drive_letters = {},  -- Safe: just assigns letters
        setup_pagefile = false,  -- Skip in QEMU (no persistent disk)
        setup_display = {},  -- Safe: queries display info
        setup_network = false,  -- Skip: QEMU network is limited
        shutdown_cleanup = false,  -- We handle shutdown via QEMU
    },
}

local pass = 0
local fail = 0
local skip = 0

print("WINPE_CI_START")
print("WINPE_CI_INFO: profile=" .. test_profile.name)
log.info("WinPE CI test started")

-- Phase 1: Dry-run plan (validate all task APIs work)
print("WINPE_CI_PHASE: dry_run_plan")
local plan, plan_err = runner.plan(test_profile, {})
if not plan then
    print("WINPE_CI_FATAL: plan failed: " .. tostring(plan_err))
    print("WINPE_CI_EXIT: 1")
    os.exit(1)
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

-- Custom progress handler that outputs to serial
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

local run_result, run_err = runner.run(test_profile, {
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

local win = require("win-utils")
local checks = {
    {"firmware_type", function()
        local info = win.sys.info.get_firmware_type()
        return info ~= nil, "firmware=" .. tostring(info)
    end},
    {"is_winpe", function()
        local pe = win.sys.info.is_winpe()
        return pe == true, "is_winpe=" .. tostring(pe)
    end},
    {"memory_info", function()
        local mem = win.sys.info.get_memory_info()
        return mem ~= nil, "memory=" .. tostring(mem and mem.total_phys or "?")
    end},
    {"power_status", function()
        local ps = win.sys.info.get_power_status()
        return ps ~= nil, "ac=" .. tostring(ps and ps.ac_on or "?")
    end},
    {"process_list", function()
        local procs = win.process.list()
        return procs ~= nil and #procs > 0, "count=" .. tostring(procs and #procs or 0)
    end},
    {"disk_physical_list", function()
        local disks = win.disk.physical.list()
        return disks ~= nil, "count=" .. tostring(disks and #disks or 0)
    end},
    {"volume_list", function()
        local vols = win.disk.volume.list()
        return vols ~= nil, "count=" .. tostring(vols and #vols or 0)
    end},
    {"service_list", function()
        local svcs = win.sys.service.list()
        return svcs ~= nil and #svcs > 0, "count=" .. tostring(svcs and #svcs or 0)
    end},
}

for _, check in ipairs(checks) do
    local name, fn = check[1], check[2]
    local ok, detail = pcall(fn)
    if ok then
        local success, msg = detail()
        if success then
            print("WINPE_CI_CHECK: " .. name .. " PASS (" .. msg .. ")")
            pass = pass + 1
        else
            print("WINPE_CI_CHECK: " .. name .. " FAIL (" .. msg .. ")")
            fail = fail + 1
        end
    else
        print("WINPE_CI_CHECK: " .. name .. " ERROR (" .. tostring(detail) .. ")")
        fail = fail + 1
    end
end

-- Summary
print(string.format("WINPE_CI_SUMMARY: %d %d %d", pass, fail, skip))
log.info(string.format("WinPE CI complete: %d passed, %d failed, %d skipped", pass, fail, skip))

local exit_code = fail > 0 and 1 or 0
print("WINPE_CI_EXIT: " .. exit_code)

-- In WinPE, exiting the shell process triggers reboot.
-- QEMU with -no-reboot will shut down instead of rebooting.
os.exit(exit_code)
