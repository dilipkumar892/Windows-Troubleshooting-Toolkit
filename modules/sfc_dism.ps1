<#
.SYNOPSIS
    System File Checker (SFC) and DISM Diagnostics Module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Provides guided, safe verification and repair of protected Windows system files
    and the Windows Component Store image using native sfc.exe and dism.exe tools.
#>

function Invoke-SfcDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "SYSTEM FILE CHECKER (SFC) DIAGNOSTICS" -Subtitle "Verify and repair protected Windows system files"

    Write-Host " SFC scans the integrity of all protected system files and replaces corrupted" -ForegroundColor White
    Write-Host " versions with correct Microsoft original versions from the Component Store." -ForegroundColor White
    Write-Host ""
    Write-Host " Select operation mode:" -ForegroundColor Cyan
    Write-Host "  [1] Verification Scan Only  (sfc /verifyonly - Safe, read-only scan)" -ForegroundColor White
    Write-Host "  [2] Scan and Repair         (sfc /scannow    - Scans and automatically repairs files)" -ForegroundColor White
    Write-Host "  [3] Cancel and Return" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select option [1-3]: " -Min 1 -Max 3

    if ($choice -eq "3") {
        Write-Host "Operation canceled." -ForegroundColor Yellow
        Wait-ReturnToMenu
        return
    }

    if (-not (Assert-Administrator -OperationName "System File Checker")) {
        Wait-ReturnToMenu
        return
    }

    $isRepair = ($choice -eq "2")
    $cmdArg = if ($isRepair) { "/scannow" } else { "/verifyonly" }
    $title = if ($isRepair) { "SFC System File Repair" } else { "SFC System File Integrity Scan" }
    $desc = if ($isRepair) {
        "Executes 'sfc /scannow' to detect and replace corrupted system files."
    } else {
        "Executes 'sfc /verifyonly' to inspect files without making any changes."
    }
    $consequences = if ($isRepair) {
        "Corrupted files will be overwritten with clean copies. A system reboot may be needed if in-use files are replaced."
    } else {
        "Read-only operation. Zero risk of system modification."
    }

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RecoveryAdvice "If SFC cannot repair files, run DISM /RestoreHealth first to fix the component store, then re-run SFC." -Action {
        Write-Host " Launching sfc.exe $cmdArg... (This may take several minutes, please wait)" -ForegroundColor DarkCyan
        $process = Start-Process -FilePath "sfc.exe" -ArgumentList $cmdArg -NoNewWindow -Wait -PassThru
        return $process.ExitCode
    }

    Write-Host ""
    Write-Host " CBS Log Reference:" -ForegroundColor Cyan
    Write-Host " Detailed logs are recorded in: C:\Windows\Logs\CBS\CBS.log" -ForegroundColor DarkGray
    Write-Host " Tip: To filter SFC entries, run: findstr /c:`"[SR]`" %windir%\Logs\CBS\CBS.log" -ForegroundColor DarkGray

    Wait-ReturnToMenu
}

function Invoke-DismDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "DISM COMPONENT STORE DIAGNOSTICS & HEALTH" -Subtitle "Deployment Image Servicing and Management"

    Write-Host " DISM services the Windows Component Store (WinSxS). If SFC fails to repair files," -ForegroundColor White
    Write-Host " repairing the component store via DISM provides the healthy source files needed." -ForegroundColor White
    Write-Host ""
    Write-Host " Select operation mode:" -ForegroundColor Cyan
    Write-Host "  [1] Check Health  (/CheckHealth   - Fast check if corruption marker is set [Read-Only])" -ForegroundColor White
    Write-Host "  [2] Scan Health   (/ScanHealth    - Thorough scan for component store corruption [Read-Only])" -ForegroundColor White
    Write-Host "  [3] Restore Health(/RestoreHealth - Scans and repairs component store using Windows Update)" -ForegroundColor White
    Write-Host "  [4] Cancel and Return" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select option [1-4]: " -Min 1 -Max 4

    if ($choice -eq "4") {
        Write-Host "Operation canceled." -ForegroundColor Yellow
        Wait-ReturnToMenu
        return
    }

    if (-not (Assert-Administrator -OperationName "DISM Operations")) {
        Wait-ReturnToMenu
        return
    }

    $operationMap = @{
        "1" = @{
            Arg = "/Online /Cleanup-Image /CheckHealth"
            Title = "DISM Check Health"
            Desc = "Checks if the operating system has flagged the image as corrupted."
            Consequences = "Fast read-only check (takes seconds). No system changes."
        }
        "2" = @{
            Arg = "/Online /Cleanup-Image /ScanHealth"
            Title = "DISM Scan Health"
            Desc = "Deeply scans the component store to detect any internal corruption."
            Consequences = "Read-only scan (takes 3-10 minutes). High CPU and disk I/O while running."
        }
        "3" = @{
            Arg = "/Online /Cleanup-Image /RestoreHealth"
            Title = "DISM Restore Health"
            Desc = "Repairs corrupted component store packages using Windows Update / CBS source."
            Consequences = "Modifies corrupted component store files. Requires working internet/update connection."
        }
    }

    $selected = $operationMap[$choice]

    $result = Invoke-SafeRepairOperation -Title $selected.Title -Description $selected.Desc -Consequences $selected.Consequences -RecoveryAdvice "Ensure internet connectivity is active so DISM can download clean component files from Windows Update. Alternatively specify an offline WIM source." -Action {
        Write-Host " Launching dism.exe $($selected.Arg)..." -ForegroundColor DarkCyan
        $process = Start-Process -FilePath "dism.exe" -ArgumentList $selected.Arg -NoNewWindow -Wait -PassThru
        return $process.ExitCode
    }

    Write-Host ""
    Write-Host " DISM Log Reference:" -ForegroundColor Cyan
    Write-Host " Detailed DISM logs are recorded in: C:\Windows\Logs\DISM\dism.log" -ForegroundColor DarkGray

    Wait-ReturnToMenu
}

