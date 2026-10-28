<#
.SYNOPSIS
    Network and DNS Diagnostics Module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Provides comprehensive network interface analysis, IP and gateway verification,
    internet connectivity tests, DNS lookup benchmarks, hosts file audit,
    and safe network stack repair utilities.
#>

function Get-NetworkDiagnosticsData {
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Gathering network adapter and IP configurations..." -Level 'INFO'

    # Get active IP configurations
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
    $ipConfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue

    $activeInterfaces = @()
    foreach ($adapter in $adapters) {
        $ipConf = $ipConfigs | Where-Object { $_.InterfaceIndex -eq $adapter.InterfaceIndex } | Select-Object -First 1

        $ipv4 = if ($ipConf.IPv4Address) { $ipConf.IPv4Address.IPAddress } else { "None" }
        $gateway = if ($ipConf.IPv4DefaultGateway) { $ipConf.IPv4DefaultGateway.NextHop } else { "None" }
        $dnsServers = if ($ipConf.DNSServer) { ($ipConf.DNSServer.ServerAddresses -join ", ") } else { "None" }

        $activeInterfaces += [PSCustomObject]@{
            Name        = $adapter.Name
            Description = $adapter.InterfaceDescription
            Status      = $adapter.Status
            LinkSpeed   = $adapter.LinkSpeed
            MacAddress  = $adapter.MacAddress
            IPv4Address = $ipv4
            Gateway     = $gateway
            DNSServers  = $dnsServers
        }
    }

    return [PSCustomObject]@{
        Interfaces = $activeInterfaces
    }
}

function Invoke-NetworkDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "NETWORK CONNECTIVITY & INTERFACE DIAGNOSTICS" -Subtitle "Inspect adapters, gateway routing, and internet reachability"

    $data = Get-NetworkDiagnosticsData
    $cfg = Get-ToolkitConfig

    Write-Host " [ACTIVE NETWORK ADAPTERS]" -ForegroundColor Yellow
    if ($data.Interfaces.Count -eq 0) {
        Write-Host "  [!] No active (Up) network interfaces detected." -ForegroundColor Red
    } else {
        foreach ($iface in $data.Interfaces) {
            Write-Host ("  Adapter     : {0} ({1})" -f $iface.Name, $iface.Description) -ForegroundColor Cyan
            Write-Host ("  Status      : {0} | Speed: {1} | MAC: {2}" -f $iface.Status, $iface.LinkSpeed, $iface.MacAddress) -ForegroundColor White
            Write-Host ("  IPv4 / Gate : {0} | Gateway: {1}" -f $iface.IPv4Address, $iface.Gateway) -ForegroundColor White
            Write-Host ("  DNS Servers : {0}" -f $iface.DNSServers) -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # Connectivity / Ping Tests
    Write-Host " [CONNECTIVITY TESTS]" -ForegroundColor Yellow

    # Test Default Gateway
    $testedGateways = @()
    foreach ($iface in $data.Interfaces) {
        if ($iface.Gateway -ne "None" -and $iface.Gateway -notin $testedGateways) {
            $testedGateways += $iface.Gateway
            Write-Host -NoNewline "  Testing Default Gateway ($($iface.Gateway))... "
            $pingGw = Test-Connection -ComputerName $iface.Gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($pingGw) {
                Write-Host "[REACHABLE]" -ForegroundColor Green
            } else {
                Write-Host "[UNREACHABLE / PACKET LOSS]" -ForegroundColor Red
            }
        }
    }

    # Test External Ping Targets
    $pingTargets = $cfg.network.pingTargets
    foreach ($target in $pingTargets) {
        Write-Host -NoNewline ("  Testing Internet Target ({0} - {1})... " -f $target.name, $target.host)
        try {
            $ping = Test-Connection -ComputerName $target.host -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($ping) {
                Write-Host "[ONLINE / SUCCESS]" -ForegroundColor Green
            } else {
                Write-Host "[FAILED / NO RESPONSE]" -ForegroundColor Red
            }
        } catch {
            Write-Host "[ERROR]" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Flush DNS Resolver Cache (ipconfig /flushdns)" -ForegroundColor White
    Write-Host "  [2] Release and Renew DHCP Leases (ipconfig /renew)" -ForegroundColor White
    Write-Host "  [3] Reset TCP/IP Stack & Winsock (Requires Admin & Reboot)" -ForegroundColor White
    Write-Host "  [4] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-4]: " -Min 1 -Max 4

    switch ($choice) {
        "1" { Invoke-FlushDnsCache }
        "2" { Invoke-RenewDhcpLeases }
        "3" { Invoke-ResetNetworkStack }
        "4" { return }
    }
}

function Invoke-DnsDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "DNS RESOLUTION & NAME SERVER TROUBLESHOOTING" -Subtitle "Test DNS resolution, timings, and inspect hosts file"

    $cfg = Get-ToolkitConfig
    $testDomains = $cfg.network.dnsLookupDomains

    Write-Host " [DNS RESOLUTION BENCHMARKS]" -ForegroundColor Yellow
    foreach ($domain in $testDomains) {
        Write-Host -NoNewline ("  Resolving '{0}'... " -f $domain)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $res = Resolve-DnsName -Name $domain -ErrorAction Stop | Select-Object -First 1
            $sw.Stop()
            $ip = if ($res.IPAddress) { $res.IPAddress } else { $res.NameHost }
            Write-Host ("[RESOLVED: {0} in {1}ms]" -f $ip, $sw.ElapsedMilliseconds) -ForegroundColor Green
        } catch {
            $sw.Stop()
            Write-Host ("[FAILED: {0}]" -f $_.Exception.Message) -ForegroundColor Red
            Write-ToolkitLog -Message "DNS lookup failed for '$domain': $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Inspect hosts file
    Write-Host ""
    Write-Host " [SYSTEM HOSTS FILE INSPECTION]" -ForegroundColor Yellow
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    if (Test-Path -Path $hostsPath) {
        $lines = Get-Content -Path $hostsPath -Encoding UTF8 -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.Trim().StartsWith('#') }

        if ($lines.Count -gt 0) {
            Write-Host "  Found custom entries in $hostsPath :" -ForegroundColor Yellow
            foreach ($l in $lines) {
                Write-Host "    $l" -ForegroundColor White
            }
        } else {
            Write-Host "  Hosts file is clean (contains only default comments/localhost mappings)." -ForegroundColor Green
        }
    } else {
        Write-Host "  Hosts file not found at default location ($hostsPath)." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Flush DNS Resolver Cache" -ForegroundColor White
    Write-Host "  [2] Register DNS with Network Servers (ipconfig /registerdns)" -ForegroundColor White
    Write-Host "  [3] Custom Domain Lookup Test" -ForegroundColor White
    Write-Host "  [4] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-4]: " -Min 1 -Max 4

    switch ($choice) {
        "1" { Invoke-FlushDnsCache }
        "2" {
            Invoke-SafeRepairOperation -Title "Register DNS with Network Servers" -Description "Executes 'ipconfig /registerdns' to refresh DHCP leases and re-register DNS names." -Consequences "Safe operation. Forces registration of DNS names and IP addresses with authorized DNS servers." -Action {
                $p = Start-Process -FilePath "ipconfig.exe" -ArgumentList "/registerdns" -Wait -PassThru -NoNewWindow
                return $p.ExitCode
            }
            Wait-ReturnToMenu
        }
        "3" {
            Write-Host -NoNewline "Enter domain name to resolve: " -ForegroundColor Cyan
            $customDomain = [Console]::ReadLine()
            if (Test-ValidHostnameOrIp -Target $customDomain) {
                Write-Host "Resolving '$customDomain'..." -ForegroundColor Cyan
                try {
                    $records = Resolve-DnsName -Name $customDomain -ErrorAction Stop
                    $records | Select-Object Name, Type, IPAddress, NameHost, TTL | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
                } catch {
                    Write-Host "Resolution failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "Invalid domain format." -ForegroundColor Red
            }
            Wait-ReturnToMenu
        }
        "4" { return }
    }
}

function Invoke-FlushDnsCache {
    [CmdletBinding()]
    param()

    $title = "Flush DNS Resolver Cache"
    $desc = "Executes 'ipconfig /flushdns' to clear all cached DNS name records."
    $consequences = "Safe operation. Resolves stale or poisoned DNS mappings without affecting network adapters."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $false -Action {
        $p = Start-Process -FilePath "ipconfig.exe" -ArgumentList "/flushdns" -Wait -PassThru -NoNewWindow
        return $p.ExitCode
    }

    Wait-ReturnToMenu
}

function Invoke-RenewDhcpLeases {
    [CmdletBinding()]
    param()

    $title = "Release and Renew DHCP Leases"
    $desc = "Releases existing DHCP leases and requests new IP configuration from the local router/DHCP server."
    $consequences = "Network connectivity will be briefly interrupted for 2-5 seconds while new IP addresses are acquired."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $false -Action {
        Write-Host " Releasing current IP leases..." -ForegroundColor DarkGray
        Start-Process -FilePath "ipconfig.exe" -ArgumentList "/release" -Wait -NoNewWindow
        Start-Sleep -Seconds 1
        Write-Host " Requesting renewed IP leases..." -ForegroundColor DarkGray
        $p = Start-Process -FilePath "ipconfig.exe" -ArgumentList "/renew" -Wait -PassThru -NoNewWindow
        return $p.ExitCode
    }

    Wait-ReturnToMenu
}

function Invoke-ResetNetworkStack {
    [CmdletBinding()]
    param()

    $title = "Reset TCP/IP Stack and Winsock Catalog"
    $desc = "Executes 'netsh winsock reset' and 'netsh int ip reset' to restore network protocols to default state."
    $consequences = "Removes third-party Layered Service Providers (LSPs) and custom IP configurations. REQUIRES A SYSTEM REBOOT to complete."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -Action {
        Write-Host " Resetting Winsock catalog..." -ForegroundColor DarkGray
        Start-Process -FilePath "netsh.exe" -ArgumentList "winsock reset" -Wait -NoNewWindow
        Write-Host " Resetting TCP/IP protocol stack..." -ForegroundColor DarkGray
        $p = Start-Process -FilePath "netsh.exe" -ArgumentList "int ip reset" -Wait -PassThru -NoNewWindow
        Write-Host " [IMPORTANT] A reboot is required to finish reinitializing the network subsystem." -ForegroundColor Yellow
        return $p.ExitCode
    }

    Wait-ReturnToMenu
}

