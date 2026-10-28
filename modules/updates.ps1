<#
.SYNOPSIS
    Windows Update diagnostics and safe repair module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Checks health of Windows Update services, queries recent hotfixes, identifies
    update logs, and provides guided non-destructive repair of update caches.
#>

function Get-WindowsUpdateHealthReport {
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Checking Windows Update components and services..." -Level 'INFO'

    $servicesToCheck = @('wuauserv', 'bits', 'cryptsvc', 'TrustedInstaller', 'dosvc')
    $serviceStatuses = @()

    foreach ($svcName in $servicesToCheck) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $serviceStatuses += [PSCustomObject]@{
                ServiceName = $svc.Name
                DisplayName = $svc.DisplayName
                Status      = $svc.Status.ToString()
                StartType   = $svc.StartType.ToString()
                IsHealthy   = ($svc.Status -eq 'Running' -or $svc.StartType -in @('Automatic', 'Manual'))
            }
        } else {
            $serviceStatuses += [PSCustomObject]@{
                ServiceName = $svcName
                DisplayName = "Not Found"
                Status      = "Missing"
                StartType   = "Unknown"
                IsHealthy   = $false
            }
        }
    }

    # Query recent updates
    $recentUpdates = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 5 -Property HotFixID, Description, InstalledOn, InstalledBy

    # Check SoftwareDistribution size
    $sdPath = "$env:windir\SoftwareDistribution"
    $sdExists = Test-Path -Path $sdPath
    $sdSizeMB = 0
    if ($sdExists) {
        try {
            $files = Get-ChildItem -Path $sdPath -Recurse -File -ErrorAction SilentlyContinue
            $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
            if ($totalBytes) {
                $sdSizeMB = [Math]::Round($totalBytes / 1MB, 2)
            }
        } catch {}
    }

    return [PSCustomObject]@{
        Services               = $serviceStatuses
        RecentUpdates          = $recentUpdates
        SoftwareDistributionSizeMB = $sdSizeMB
        SoftwareDistributionPath   = $sdPath
    }
}

function Invoke-WindowsUpdateDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "WINDOWS UPDATE DIAGNOSTICS & SAFE REPAIR" -Subtitle "Inspect update services, logs, and cache health"

    $report = Get-WindowsUpdateHealthReport

    Write-Host " [CRITICAL UPDATE SERVICES]" -ForegroundColor Yellow
    foreach ($svc in $report.Services) {
        $color = if ($svc.Status -eq 'Running') { "Green" } elseif ($svc.Status -eq 'Stopped') { "Yellow" } else { "Red" }
        $tag = if ($svc.IsHealthy) { "[OK]" } else { "[ATTENTION]" }
        Write-Host ("  {0,-5} {1,-18} Status: {2,-10} Startup: {3}" -f $tag, $svc.ServiceName, $svc.Status, $svc.StartType) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host " [UPDATE CACHE DIRECTORY]" -ForegroundColor Yellow
    Write-Host ("  Path: {0} (Size: ~{1} MB)" -f $report.SoftwareDistributionPath, $report.SoftwareDistributionSizeMB) -ForegroundColor White

    Write-Host ""
    Write-Host " [RECENTLY INSTALLED WINDOWS UPDATES]" -ForegroundColor Yellow
    if ($report.RecentUpdates -and $report.RecentUpdates.Count -gt 0) {
        $report.RecentUpdates | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
    } else {
        Write-Host "  No recent hotfix records retrieved via WMI." -ForegroundColor DarkGray
    }

    Write-Host " [RELEVANT UPDATE LOG LOCATIONS]" -ForegroundColor Yellow
    Write-Host "  1. Windows Update ETL logs : Get-WindowsUpdateLog (extracts to Desktop/logs)" -ForegroundColor DarkGray
    Write-Host "  2. CBS Servicing Log      : C:\Windows\Logs\CBS\CBS.log" -ForegroundColor DarkGray
    Write-Host "  3. Setup API Log          : C:\Windows\INF\setupapi.dev.log" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Reset Windows Update Services and Cache (Safe Soft Reset)" -ForegroundColor White
    Write-Host "  [2] Re-register Core Windows Update DLLs" -ForegroundColor White
    Write-Host "  [3] Generate Formatted Windows Update Log (Get-WindowsUpdateLog)" -ForegroundColor White
    Write-Host "  [4] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-4]: " -Min 1 -Max 4

    switch ($choice) {
        "1" {
            Invoke-SafeWindowsUpdateReset
        }
        "2" {
            Invoke-ReregisterUpdateDlls
        }
        "3" {
            Invoke-GenerateWindowsUpdateLog
        }
        "4" {
            return
        }
    }
}

function Invoke-SafeWindowsUpdateReset {
    [CmdletBinding()]
    param()

    $title = "Safe Windows Update Cache & Component Reset"
    $desc = "Temporarily halts wuauserv, bits, cryptsvc, renames SoftwareDistribution and Catroot2 folders to .bak, and restarts services."
    $consequences = "Active downloads will be cleared and re-scanned. Update history view may temporarily reset, but installed updates will NOT be uninstalled."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RecoveryAdvice "If update services do not start, run 'net start wuauserv' manually or restart Windows." -Action {
        Write-Host " [1/4] Stopping Windows Update related services..." -ForegroundColor Cyan
        $services = @('wuauserv', 'bits', 'cryptsvc', 'dosvc')
        foreach ($s in $services) {
            Write-Host "       Stopping service '$s'..." -ForegroundColor DarkGray
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        }

        Start-Sleep -Seconds 2

        Write-Host " [2/4] Archiving update cache directories (safe rename, no file deletion)..." -ForegroundColor Cyan
        $sd = "$env:windir\SoftwareDistribution"
        $sdBak = "$env:windir\SoftwareDistribution.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (Test-Path $sd) {
            Write-Host "       Renaming $sd -> $sdBak" -ForegroundColor DarkGray
            Rename-Item -Path $sd -NewName (Split-Path $sdBak -Leaf) -ErrorAction SilentlyContinue
        }

        $cr = "$env:windir\System32\catroot2"
        $crBak = "$env:windir\System32\catroot2.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (Test-Path $cr) {
            Write-Host "       Renaming $cr -> $crBak" -ForegroundColor DarkGray
            Rename-Item -Path $cr -NewName (Split-Path $crBak -Leaf) -ErrorAction SilentlyContinue
        }

        Write-Host " [3/4] Restarting services..." -ForegroundColor Cyan
        foreach ($s in $services) {
            Write-Host "       Starting service '$s'..." -ForegroundColor DarkGray
            Start-Service -Name $s -ErrorAction SilentlyContinue
        }

        Write-Host " [4/4] Verifying services restarted..." -ForegroundColor Cyan
        Get-Service -Name @('wuauserv', 'bits') | Select-Object Name, Status | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor Green

        return 0
    }

    Wait-ReturnToMenu
}

function Invoke-ReregisterUpdateDlls {
    [CmdletBinding()]
    param()

    $title = "Re-register Core Update DLLs"
    $desc = "Re-registers core cryptographic and update dynamic libraries (wups.dll, wups2.dll, atl.dll, oleaut32.dll, etc.)"
    $consequences = "Safe registration. Fixes corrupted COM bindings without altering files."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -Action {
        $dlls = @("atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll", "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll", "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll", "wuaueng.dll", "wucltui.dll", "wups.dll", "wups2.dll", "wuwebv.dll")

        $successCount = 0
        foreach ($dll in $dlls) {
            $regPath = Join-Path "$env:windir\System32" $dll
            if (Test-Path $regPath) {
                $p = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s `"$regPath`"" -Wait -PassThru -NoNewWindow
                if ($p.ExitCode -eq 0) { $successCount++ }
            }
        }
        Write-Host " Successfully registered $successCount core libraries." -ForegroundColor Green
        return 0
    }

    Wait-ReturnToMenu
}

function Invoke-GenerateWindowsUpdateLog {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "CONVERTING WINDOWS UPDATE ETL LOGS" -Subtitle "Invoking Get-WindowsUpdateLog"

    $baseDir = Split-Path -Parent $PSScriptRoot
    $outDir = Join-Path $baseDir "logs"
    $outLog = Join-Path $outDir "WindowsUpdate_Decoded.log"

    Write-Host " Running Get-WindowsUpdateLog (decodes Windows ETL traces using Microsoft public symbols)..." -ForegroundColor Cyan
    Write-Host " Output file: $outLog" -ForegroundColor DarkGray

    try {
        Get-WindowsUpdateLog -LogPath $outLog -ErrorAction Stop
        Write-Host " [SUCCESS] Windows Update log generated at: $outLog" -ForegroundColor Green
        Write-ToolkitLog -Message "Decoded Windows Update log exported to $outLog" -Level 'SUCCESS'
    } catch {
        Write-Host " [WARNING] Could not run Get-WindowsUpdateLog directly: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host " Note: Public symbol server lookup may be throttled or unavailable offline." -ForegroundColor DarkGray
        Write-ToolkitLog -Message "Get-WindowsUpdateLog failure: $($_.Exception.Message)" -Level 'WARN'
    }

    Wait-ReturnToMenu
}

