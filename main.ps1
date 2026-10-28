<#
.SYNOPSIS
    Main interactive entrypoint for Windows 10/11 Advanced Troubleshooting Toolkit.
.DESCRIPTION
    Initializes runtime, loads modular libraries, renders the 15-option interactive menu,
    dispatches diagnostic and repair operations, and ensures complete safety and logging.
#>

# Enforce UTF-8 console output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Set console title
try {
    $Host.UI.RawUI.WindowTitle = "Windows Troubleshooting Toolkit v1.0.0"
} catch {}

# Resolve script root directory
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# Dot-source libraries
. (Join-Path $scriptDir "lib\common.ps1")
. (Join-Path $scriptDir "lib\logging.ps1")
. (Join-Path $scriptDir "lib\validation.ps1")
. (Join-Path $scriptDir "lib\safety.ps1")

# Dot-source modules
. (Join-Path $scriptDir "modules\system.ps1")
. (Join-Path $scriptDir "modules\sfc_dism.ps1")
. (Join-Path $scriptDir "modules\updates.ps1")
. (Join-Path $scriptDir "modules\network.ps1")
. (Join-Path $scriptDir "modules\disk.ps1")
. (Join-Path $scriptDir "modules\hardware.ps1")
. (Join-Path $scriptDir "modules\security.ps1")
. (Join-Path $scriptDir "modules\restore.ps1")
. (Join-Path $scriptDir "modules\performance.ps1")
. (Join-Path $scriptDir "modules\report.ps1")
. (Join-Path $scriptDir "modules\logs.ps1")
. (Join-Path $scriptDir "modules\repair.ps1")

# Load configuration and initialize logging
$config = Get-ToolkitConfig
$logFile = Initialize-Logger -LogDirPath (Join-Path $scriptDir "logs") -MinLevel $config.logging.level -RetentionDays $config.logging.maxLogRetentionDays
Write-ToolkitLog -Message "Windows Troubleshooting Toolkit initialized successfully. Session log: $logFile" -Level 'INFO'

# Main application loop
$isRunning = $true

while ($isRunning) {
    Clear-Host
    Show-ToolkitBanner -Version $config.application.version

    Write-Host "  CORE DIAGNOSTIC MODULES:" -ForegroundColor DarkCyan
    Write-Host "   [1]  System Information & Health Snapshot" -ForegroundColor White
    Write-Host "   [2]  System File Checker (SFC - Scan & Repair)" -ForegroundColor White
    Write-Host "   [3]  DISM Component Store Health Check" -ForegroundColor White
    Write-Host "   [4]  Windows Update Diagnostics & Safe Reset" -ForegroundColor White
    Write-Host "   [5]  Network Connectivity & Adapter Diagnostics" -ForegroundColor White
    Write-Host "   [6]  DNS Troubleshooting & Benchmark Tests" -ForegroundColor White
    Write-Host "   [7]  Disk Health & Storage Space Diagnostics" -ForegroundColor White
    Write-Host "   [8]  Hardware Diagnostics & Problem Device Audit" -ForegroundColor White
    Write-Host "   [9]  Windows Security & Defender Diagnostics" -ForegroundColor White
    Write-Host "   [10] System Restore Point Management" -ForegroundColor White
    Write-Host "   [11] Real-time Performance & Resource Diagnostics" -ForegroundColor White

    Write-Host ""
    Write-Host "  REPORTING & MAINTENANCE:" -ForegroundColor DarkCyan
    Write-Host "   [12] Generate Comprehensive Diagnostic Report (HTML & JSON)" -ForegroundColor White
    Write-Host "   [13] View Session Logs & Windows Event Errors" -ForegroundColor White
    Write-Host "   [14] Advanced Guided Repair Subsystem" -ForegroundColor White
    Write-Host "   [15] Exit Toolkit" -ForegroundColor Yellow

    Write-Host ""
    $choice = Get-ValidatedMenuChoice -Prompt "Select an option [1-15]: " -Min 1 -Max 15

    Write-ToolkitLog -Message "User selected menu option: $choice" -Level 'DEBUG' -NoConsole

    try {
        switch ($choice) {
            "1"  { Show-SystemInformationMenu }
            "2"  { Invoke-SfcDiagnostics }
            "3"  { Invoke-DismDiagnostics }
            "4"  { Invoke-WindowsUpdateDiagnostics }
            "5"  { Invoke-NetworkDiagnostics }
            "6"  { Invoke-DnsDiagnostics }
            "7"  { Invoke-DiskDiagnostics }
            "8"  { Invoke-HardwareDiagnostics }
            "9"  { Invoke-SecurityDiagnostics }
            "10" { Invoke-RestorePointManagement }
            "11" { Invoke-PerformanceDiagnostics }
            "12" { Invoke-GenerateDiagnosticReport }
            "13" { Invoke-LogsMenu }
            "14" { Invoke-AdvancedRepairMenu }
            "15" {
                Write-Host ""
                Write-Host "Exiting Windows Troubleshooting Toolkit. Have a productive day!" -ForegroundColor Green
                Write-ToolkitLog -Message "Session closed cleanly by user." -Level 'INFO'
                $isRunning = $false
            }
            Default {
                Write-Host " [!] Unrecognized choice. Please enter a number between 1 and 15." -ForegroundColor Red
                Wait-ReturnToMenu
            }
        }
    } catch {
        Write-Host ""
        Write-Host " [CRITICAL ERROR] An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
        Write-ToolkitLog -Message "Unhandled exception in option [${choice}]: $($_.Exception.ToString())" -Level 'ERROR'
        Wait-ReturnToMenu
    }
}
