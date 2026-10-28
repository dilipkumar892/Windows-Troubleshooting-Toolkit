<#
.SYNOPSIS
    Performance Diagnostics Module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Monitors real-time CPU, RAM, pagefile load, identifies high-resource processes,
    and provides performance inspection tools.
#>

function Get-PerformanceSnapshot {
    [CmdletBinding()]
    param()

    # CPU load snapshot
    $cpuLoad = 0
    try {
        $cpuMetric = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue |
            Measure-Object -Property LoadPercentage -Average
        if ($cpuMetric.Average -ne $null) { $cpuLoad = [Math]::Round($cpuMetric.Average, 1) }
    } catch {}

    # Memory snapshot
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $totalRamMB = if ($os) { [Math]::Round([double]$os.TotalVisibleMemorySize / 1024, 0) } else { 1 }
    $freeRamMB = if ($os) { [Math]::Round([double]$os.FreePhysicalMemory / 1024, 0) } else { 0 }
    $usedRamMB = [Math]::Max([double]0, [double]($totalRamMB - $freeRamMB))
    $ramPct = [Math]::Round(($usedRamMB / $totalRamMB) * 100, 1)

    # Pagefile
    $pagefiles = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue
    $pagefilePct = 0
    if ($pagefiles) {
        $pagefilePct = ($pagefiles | Measure-Object -Property CurrentUsage -Average).Average
    }

    # Top processes
    $topCpu = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object CPU -Descending |
        Select-Object -First 10 -Property Id, ProcessName, CPU, @{Name="WorkingSetMB"; Expression={[Math]::Round($_.WorkingSet64 / 1MB, 1)}}, @{Name="Handles"; Expression={$_.HandleCount}}

    $topMem = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 -Property Id, ProcessName, @{Name="WorkingSetMB"; Expression={[Math]::Round($_.WorkingSet64 / 1MB, 1)}}, @{Name="PM_MB"; Expression={[Math]::Round($_.PagedMemorySize64 / 1MB, 1)}}

    return [PSCustomObject]@{
        CpuLoadPercent   = $cpuLoad
        TotalRamMB       = $totalRamMB
        UsedRamMB        = $usedRamMB
        FreeRamMB        = $freeRamMB
        RamPercentUsed   = $ramPct
        PagefilePercent  = $pagefilePct
        TopCpuProcesses  = $topCpu
        TopMemProcesses  = $topMem
    }
}

function Invoke-PerformanceDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "SYSTEM PERFORMANCE & RESOURCE MONITORING" -Subtitle "Real-time snapshot of CPU, Memory, Pagefile, and Process Load"

    $snap = Get-PerformanceSnapshot

    Write-Host " [RESOURCE UTILIZATION SUMMARY]" -ForegroundColor Yellow
    $cpuColor = if ($snap.CpuLoadPercent -gt 85) { "Red" } elseif ($snap.CpuLoadPercent -gt 60) { "Yellow" } else { "Green" }
    $ramColor = if ($snap.RamPercentUsed -gt 85) { "Red" } elseif ($snap.RamPercentUsed -gt 70) { "Yellow" } else { "Green" }

    Write-Host ("  CPU Overall Utilization : {0}%" -f $snap.CpuLoadPercent) -ForegroundColor $cpuColor
    Write-Host ("  RAM In-Use             : {0} MB / {1} MB ({2}%)" -f $snap.UsedRamMB, $snap.TotalRamMB, $snap.RamPercentUsed) -ForegroundColor $ramColor
    Write-Host ("  Pagefile Usage         : {0}%" -f $snap.PagefilePercent) -ForegroundColor White

    Write-Host ""
    Write-Host " [TOP 10 PROCESSES BY CPU TIME]" -ForegroundColor Yellow
    $snap.TopCpuProcesses | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White

    Write-Host " [TOP 10 PROCESSES BY MEMORY FOOTPRINT]" -ForegroundColor Yellow
    $snap.TopMemProcesses | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White

    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Open Windows Task Manager (taskmgr.exe)" -ForegroundColor White
    Write-Host "  [2] Open Windows Resource Monitor (resmon.exe)" -ForegroundColor White
    Write-Host "  [3] Open Performance Monitor (perfmon.exe)" -ForegroundColor White
    Write-Host "  [4] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-4]: " -Min 1 -Max 4

    switch ($choice) {
        "1" { Start-Process "taskmgr.exe"; Wait-ReturnToMenu }
        "2" { Start-Process "resmon.exe"; Wait-ReturnToMenu }
        "3" { Start-Process "perfmon.exe"; Wait-ReturnToMenu }
        "4" { return }
    }
}
