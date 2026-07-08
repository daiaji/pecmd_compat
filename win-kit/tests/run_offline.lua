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

local modules = {
    'win-kit',
    'win-kit.tasks',
    'win-kit.smart_devi',
    'win-kit.smart_offline_devi',
    'win-kit.tasks.install_drivers',
    'win-kit.tasks.assign_drive_letters',
    'win-kit.tasks.setup_pagefile',
    'win-kit.tasks.setup_display',
    'win-kit.tasks.shutdown_cleanup',
    'win-kit.tasks.init_pe',
    'win-kit.env_manager',
    'win-kit.oem',
    'win-kit.icon_refresh',
    'win-kit.devi',
    'win-kit.driver_scanner',
    'win-kit.driver_installer',
    'win-kit.partition_tools',
    'win-kit.registry',
    'win-kit.repair',
    'win-kit.pecmd_logic',
}

local failures = 0

for _, name in ipairs(modules) do
    local ok, err = pcall(require, name)
    if not ok then
        failures = failures + 1
        io.stderr:write(string.format('FAILED require %s: %s\n', name, tostring(err)))
    end
end

if failures > 0 then
    error(string.format('win-kit offline tests failed: %d', failures))
end

local smart_devi = require 'win-kit.smart_devi'
local driver_plan = assert(smart_devi.plan({ root = [[X:\Drivers]] }))
assert(driver_plan.dry_run == true)
assert(driver_plan.steps[1].action == 'scan_devices')

local smart_offline_devi = require 'win-kit.smart_offline_devi'
local offline_plan = assert(smart_offline_devi.plan({ offline_image = [[D:\]] }))
assert(offline_plan.offline == true)
assert(offline_plan.steps[3].action == 'inject_offline_drivers')

local tasks = require 'win-kit.tasks'
assert(tasks.assign_drive_letters.plan({}).steps[3].action == 'assign_missing_drive_letters')
assert(tasks.setup_pagefile.plan({ size_mb = 2048 }).steps[3].action == 'create_pagefile')
assert(tasks.setup_display.plan({}).steps[2].action == 'select_best_display_mode')
assert(tasks.shutdown_cleanup.plan({}).steps[1].action == 'clean_standard_temp_dirs')
assert(tasks.init_pe.plan({}).steps[1].action == 'refresh_icon_cache')

local env_manager = require 'win-kit.env_manager'
local ok_path, path_plan = env_manager.append_path([[X:\Tools]], 'System', { dry_run = true })
assert(ok_path and path_plan.steps[1].action == 'append_path')

local oem = require 'win-kit.oem'
local ok_oem, oem_plan = oem.set({ manufacturer = 'PE' }, { dry_run = true })
assert(ok_oem and oem_plan.steps[1].action == 'set_oem_information')

local icon_refresh = require 'win-kit.icon_refresh'
local ok_icon, icon_plan = icon_refresh.refresh_icons({ dry_run = true })
assert(ok_icon and icon_plan.steps[1].action == 'stop_explorer')

local devi = require 'win-kit.devi'
local ok_devi, devi_plan = devi.install([[X:\Drivers]], { dry_run = true })
assert(ok_devi and devi_plan.steps[1].action == 'classify_driver_path')

local driver_scanner = require 'win-kit.driver_scanner'
local _, _, _, scanner_plan = driver_scanner.install_recursive([[X:\Drivers]], { dry_run = true })
assert(scanner_plan.steps[1].action == 'scan_inf_files')

local driver_installer = require 'win-kit.driver_installer'
local ok_cab, cab_plan = driver_installer.install_cab_verbose([[X:\Drivers\pack.cab]], { dry_run = true })
assert(ok_cab and cab_plan.steps[1].action == 'extract_cab')

local partition_tools = require 'win-kit.partition_tools'
local ok_part, part_plan = partition_tools.set_hidden(0, 1, true, { dry_run = true })
assert(ok_part and part_plan.steps[1].action == 'set_hidden')

local registry = require 'win-kit.registry'
local ok_reg, reg_plan = registry.write([[HKLM\Software\PE]], 'Value', 'Data', nil, { dry_run = true })
assert(ok_reg and reg_plan.steps[1].action == 'write_value')

local repair = require 'win-kit.repair'
local _, _, exec_plan = repair.exec_capture('ipconfig', 1000, { dry_run = true })
assert(exec_plan.steps[1].action == 'exec_capture')
local ok_hive, hive_plan = repair.with_super_hive([[HKLM\Tmp]], [[X:\SOFTWARE]], function() end, { dry_run = true })
assert(ok_hive and hive_plan.steps[1].action == 'load_hive')

print(string.format('win-kit offline tests: %d modules loaded, 0 failed', #modules))
