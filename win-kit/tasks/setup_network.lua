local win = require 'win-utils'

local M = {}

function M.plan(opts)
    opts = opts or {}
    local steps = {}

    if opts.enable_adapter then
        table.insert(steps, { action = 'enable_adapter', adapter = opts.enable_adapter })
    end
    if opts.dhcp then
        table.insert(steps, { action = 'set_dhcp', adapter = opts.dhcp_adapter or opts.enable_adapter })
    elseif opts.static_ip then
        table.insert(steps, {
            action = 'set_static_ipv4',
            adapter = opts.static_ip.adapter,
            address = opts.static_ip.address,
            mask = opts.static_ip.mask,
            gateway = opts.static_ip.gateway,
        })
    end
    if opts.dns_servers then
        table.insert(steps, { action = 'set_dns', adapter = opts.dns_adapter or opts.enable_adapter, servers = opts.dns_servers })
    end
    if opts.sync_time then
        table.insert(steps, { action = 'sync_ntp', server = opts.ntp_server or 'time.windows.com' })
    end

    return {
        ok = true,
        task = 'setup_network',
        dry_run = true,
        changed = false,
        steps = steps,
        warnings = {},
    }
end

function M.run(opts)
    opts = opts or {}
    if opts.dry_run then
        return M.plan(opts)
    end

    local details = {}

    if opts.enable_adapter then
        local ok, err = win.net.adapter.enable(opts.enable_adapter, opts)
        if not ok then
            return nil, { task = 'setup_network', code = 'enable_adapter_failed', message = tostring(err) }
        end
        details.adapter_enabled = opts.enable_adapter
    end

    if opts.dhcp then
        local adapter = opts.dhcp_adapter or opts.enable_adapter
        local ok, err = win.net.adapter.set_ipv4(adapter, { dhcp = true })
        if not ok then
            return nil, { task = 'setup_network', code = 'dhcp_failed', message = tostring(err) }
        end
        details.dhcp_enabled = adapter
    elseif opts.static_ip then
        local ok, err = win.net.adapter.set_ipv4(opts.static_ip.adapter, {
            address = opts.static_ip.address,
            mask = opts.static_ip.mask,
            gateway = opts.static_ip.gateway,
        })
        if not ok then
            return nil, { task = 'setup_network', code = 'static_ip_failed', message = tostring(err) }
        end
        details.static_ip_set = opts.static_ip.adapter
    end

    if opts.dns_servers then
        local adapter = opts.dns_adapter or opts.enable_adapter
        local ok, err = win.net.dns.set_servers(adapter, opts.dns_servers, opts)
        if not ok then
            return nil, { task = 'setup_network', code = 'dns_set_failed', message = tostring(err) }
        end
        details.dns_set = adapter
    end

    if opts.sync_time then
        local ok, err = win.net.ntp.sync(opts.ntp_server or 'time.windows.com', opts)
        if not ok then
            return nil, { task = 'setup_network', code = 'ntp_sync_failed', message = tostring(err) }
        end
        details.ntp_synced = true
    end

    return {
        ok = true,
        task = 'setup_network',
        changed = details.adapter_enabled ~= nil or details.dhcp_enabled ~= nil or details.static_ip_set ~= nil or details.dns_set ~= nil or details.ntp_synced ~= nil,
        details = details,
    }
end

return M
