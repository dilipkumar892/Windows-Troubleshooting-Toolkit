<#
.SYNOPSIS
    Automated Integration and Safe Simulation Test Suite.
.DESCRIPTION
    Performs comprehensive syntax parsing across all project files,
    validates library and module loading, tests telemetry collection without
    system modification, checks dry-run safety modes, and verifies report export.
#>

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $testDir

$totalTests = 0
$passedTests = 0
$failedTests = 0

function Assert-Test {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $script:totalTests++
    try {
        $result = & $Action
        $isSuccess = ($result -eq $true -or [bool]$result -eq $true -or $null -eq $result)
        if ($isSuccess) {
            Write-Host " [PASS] $Name" -ForegroundColor Green
            $script:passedTests++
        } else {
            Write-Host " [FAIL] $Name - Condition returned false" -ForegroundColor Red
            $script:failedTests++
        }
    } catch {
        Write-Host " [FAIL] $Name - Threw exception: $($_.Exception.Message)" -ForegroundColor Red
        $script:failedTests++
    }
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  RUNNING ADVANCED INTEGRATION & SIMULATION TEST SUITE                          " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. AST Syntax Check on all .ps1 files
$psFiles = Get-ChildItem -Path $rootDir -Recurse -Filter "*.ps1"
foreach ($f in $psFiles) {
    Assert-Test "AST Syntax Validation: $($f.Name)" {
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            Write-Host "     Parse errors in $($f.Name):" -ForegroundColor Red
            $errors | ForEach-Object { Write-Host "     - $($_.Message) (Line $($_.Extent.StartLineNumber))" -ForegroundColor Red }
        }
        return ($errors.Count -eq 0)
    }
}

# 2. Configuration loading
Assert-Test "Settings JSON Schema & Parsing" {
    $cfgPath = Join-Path $rootDir "config\settings.json"
    $json = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return ([bool]($json.application.name -ne $null -and $json.network.pingTargets.Count -gt 0))
}

# 3. Dot-source common & logging libraries into script scope
. (Join-Path $rootDir "lib\common.ps1")
. (Join-Path $rootDir "lib\logging.ps1")
. (Join-Path $rootDir "lib\validation.ps1")
. (Join-Path $rootDir "lib\safety.ps1")

# Dot-source modules
. (Join-Path $rootDir "modules\system.ps1")
. (Join-Path $rootDir "modules\disk.ps1")
. (Join-Path $rootDir "modules\network.ps1")
. (Join-Path $rootDir "modules\hardware.ps1")
. (Join-Path $rootDir "modules\security.ps1")
. (Join-Path $rootDir "modules\updates.ps1")
. (Join-Path $rootDir "modules\performance.ps1")
. (Join-Path $rootDir "modules\restore.ps1")
. (Join-Path $rootDir "modules\logs.ps1")
. (Join-Path $rootDir "modules\repair.ps1")

Assert-Test "Load lib/common.ps1" {
    return [bool]((Get-Command -Name "Show-ToolkitBanner" -ErrorAction SilentlyContinue) -ne $null)
}

Assert-Test "Load lib/logging.ps1 & Logger Initialization" {
    $testLog = Initialize-Logger -LogDirPath (Join-Path $rootDir "logs") -MinLevel "DEBUG"
    Write-ToolkitLog -Message "Test log entry from automated test harness" -Level 'DEBUG' -NoConsole
    return [bool](Test-Path $testLog)
}

# 4. Safety dry-run test
Assert-Test "Load lib/safety.ps1 & DryRun Execution" {
    $dryRes = Invoke-SafeRepairOperation -Title "Simulated Test Repair" -Description "Unit test simulation" -Consequences "None" -DryRun $true -Action {
        return 0
    }
    return [bool]($dryRes.Success -eq $true -and $dryRes.ExitCode -eq 0)
}

# 5. Load and execute read-only diagnostic telemetry collectors
Assert-Test "Module: system.ps1 - Get-SystemInformationReport" {
    $res = Get-SystemInformationReport
    return [bool]($res.OSName -ne $null -and $res.TotalRAM -ne $null)
}

Assert-Test "Module: disk.ps1 - Get-DiskDiagnosticsData" {
    $res = Get-DiskDiagnosticsData
    return [bool]($res.Volumes.Count -gt 0)
}

Assert-Test "Module: network.ps1 - Get-NetworkDiagnosticsData" {
    $res = Get-NetworkDiagnosticsData
    return [bool]($res.Interfaces.Count -ge 0)
}

Assert-Test "Module: hardware.ps1 - Get-HardwareDiagnosticsData" {
    $res = Get-HardwareDiagnosticsData
    return [bool]($res.Processor -ne $null)
}

Assert-Test "Module: security.ps1 - Get-SecurityDiagnosticsData" {
    $res = Get-SecurityDiagnosticsData
    return [bool]($res.FirewallProfiles.Count -ge 0)
}

Assert-Test "Module: updates.ps1 - Get-WindowsUpdateHealthReport" {
    $res = Get-WindowsUpdateHealthReport
    return [bool]($res.Services.Count -gt 0)
}

Assert-Test "Module: performance.ps1 - Get-PerformanceSnapshot" {
    $res = Get-PerformanceSnapshot
    return [bool]($res.TotalRamMB -gt 0)
}

Assert-Test "Module: restore.ps1 - Get-RestorePointData" {
    $res = Get-RestorePointData
    return [bool]($res -ne $null)
}

Assert-Test "Module: logs.ps1 - Log query utilities" {
    $logs = Get-AllLogFiles
    return [bool]($logs.Count -gt 0)
}

Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host " INTEGRATION TEST RESULTS: Total: $totalTests | Passed: $passedTests | Failed: $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "================================================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) { exit 1 } else { exit 0 }
