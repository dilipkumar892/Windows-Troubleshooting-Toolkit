<#
.SYNOPSIS
    System information and diagnostics module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Collects and displays OS details, Windows build, CPU, RAM, uptime,
    active processes, startup applications, and basic health metrics.
#>

function Get-SystemInformationReport {
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Collecting System Information..." -Level 'INFO'

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $proc = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

    $uptime = if ($os -and $os.LastBootUpTime) {
        (Get-Date) - $os.LastBootUpTime
    } else {
        [TimeSpan]::Zero
    }

    $totalRamBytes = if ($cs) { [double]$cs.TotalPhysicalMemory } else { 0.0 }
    $freeRamBytes = if ($os) { [double]$os.FreePhysicalMemory * 1KB } else { 0.0 }
    $usedRamBytes = [Math]::Max(0.0, [double]($totalRamBytes - $freeRamBytes))
    $ramPercentUsed = if ($totalRamBytes -gt 0) { [Math]::Round(($usedRamBytes / $totalRamBytes) * 100, 1) } else { 0 }

    # Query startup apps from registry
    $startupApps = @()
    $runKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($rk in $runKeys) {
        if (Test-Path $rk) {
            $props = (Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue).psobject.properties |
                Where-Object { $_.Name -notmatch '^PS.*' }
            foreach ($p in $props) {
                $startupApps += [PSCustomObject]@{
                    Name = $p.Name
                    Command = $p.Value
                    Location = $rk
                }
            }
        }
    }

    # Top processes
    $topProcessesCpu = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object CPU -Descending |
        Select-Object -First 5 -Property Id, ProcessName, CPU, @{Name="MemoryMB"; Expression={[Math]::Round($_.WorkingSet64 / 1MB, 1)}}

    $topProcessesMem = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 5 -Property Id, ProcessName, @{Name="MemoryMB"; Expression={[Math]::Round($_.WorkingSet64 / 1MB, 1)}}

    return [PSCustomObject]@{
        OSName           = if ($os) { $os.Caption } else { "Unknown" }
        OSVersion        = if ($os) { $os.Version } else { "Unknown" }
        OSBuild          = if ($os) { $os.BuildNumber } else { "Unknown" }
        OSArchitecture   = if ($os) { $os.OSArchitecture } else { "Unknown" }
        InstallDate      = if ($os) { $os.InstallDate } else { $null }
        LastBootTime     = if ($os) { $os.LastBootUpTime } else { $null }
        UptimeFormatted  = Format-TimeSpanReadable -Span $uptime
        ComputerName     = if ($cs) { $cs.Name } else { $env:COMPUTERNAME }
        Domain           = if ($cs) { $cs.Domain } else { "WORKGROUP" }
        Manufacturer     = if ($cs) { $cs.Manufacturer } else { "Unknown" }
        Model            = if ($cs) { $cs.Model } else { "Unknown" }
        ProcessorName    = if ($proc) { $proc.Name.Trim() } else { "Unknown" }
        ProcessorCores   = if ($proc) { $proc.NumberOfCores } else { 0 }
        ProcessorLogical = if ($proc) { $proc.NumberOfLogicalProcessors } else { 0 }
        TotalRAM         = Format-ByteSize -Bytes $totalRamBytes
        FreeRAM          = Format-ByteSize -Bytes $freeRamBytes
        UsedRAM          = Format-ByteSize -Bytes $usedRamBytes
        RAMPercentUsed   = $ramPercentUsed
        StartupAppsCount = $startupApps.Count
        StartupApps      = $startupApps
        TopCpuProcesses  = $topProcessesCpu
        TopMemProcesses  = $topProcessesMem
    }
}

function Show-SystemInformationMenu {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "SYSTEM INFORMATION & HEALTH SNAPSHOT" -Subtitle "Operating System, Hardware, Memory, and Processes"

    $sys = Get-SystemInformationReport

    Write-Host " [OS & ENVIRONMENT]" -ForegroundColor Yellow
    Write-Host ("  Operating System : {0} ({1})" -f $sys.OSName, $sys.OSArchitecture)
    Write-Host ("  Version / Build  : {0} (Build {1})" -f $sys.OSVersion, $sys.OSBuild)
    Write-Host ("  Machine / Model  : {0} - {1}" -f $sys.Manufacturer, $sys.Model)
    Write-Host ("  Computer / Domain: {0} ({1})" -f $sys.ComputerName, $sys.Domain)
    Write-Host ("  System Uptime    : {0} (Boot: {1})" -f $sys.UptimeFormatted, $sys.LastBootTime)

    Write-Host ""
    Write-Host " [CPU & MEMORY]" -ForegroundColor Yellow
    Write-Host ("  Processor        : {0}" -f $sys.ProcessorName)
    Write-Host ("  Cores / Threads  : {0} Cores / {1} Logical Processors" -f $sys.ProcessorCores, $sys.ProcessorLogical)
    Write-Host ("  Memory (RAM)     : {0} Used / {1} Total ({2}% in use)" -f $sys.UsedRAM, $sys.TotalRAM, $sys.RAMPercentUsed)

    if ($sys.RAMPercentUsed -gt 85) {
        Write-Host "  [!] High memory pressure detected (> 85%). Consider investigating memory-heavy apps." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host " [TOP 5 PROCESSES BY CPU TIME]" -ForegroundColor Yellow
    $sys.TopCpuProcesses | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White

    Write-Host " [TOP 5 PROCESSES BY MEMORY CONSUMPTION]" -ForegroundColor Yellow
    $sys.TopMemProcesses | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White

    Write-Host " [STARTUP APPLICATIONS (${sys.StartupAppsCount} discovered in registry)]" -ForegroundColor Yellow
    if ($sys.StartupApps.Count -gt 0) {
        $sys.StartupApps | Select-Object -First 10 -Property Name, Command | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor DarkGray
        if ($sys.StartupApps.Count -gt 10) {
            Write-Host "  ... and $($sys.StartupApps.Count - 10) more startup applications." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  No startup applications registered under standard Run keys." -ForegroundColor DarkGray
    }

    Write-ToolkitLog -Message "System information displayed successfully." -Level 'SUCCESS'
    Wait-ReturnToMenu
}
