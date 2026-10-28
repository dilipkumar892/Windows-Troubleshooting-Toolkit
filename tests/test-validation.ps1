<#
.SYNOPSIS
    Automated Unit Tests for Input Validation and Sanitization.
.DESCRIPTION
    Validates boundary conditions, edge cases, injection attempts,
    and choice validators without modifying system state.
#>

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$libDir = Join-Path (Split-Path -Parent $testDir) "lib"
. (Join-Path $libDir "validation.ps1")

$totalTests = 0
$passedTests = 0
$failedTests = 0

function Assert-Equal {
    param(
        [string]$TestName,
        $Actual,
        $Expected
    )

    $script:totalTests++
    if ($Actual -eq $Expected) {
        Write-Host " [PASS] $TestName" -ForegroundColor Green
        $script:passedTests++
    } else {
        Write-Host " [FAIL] $TestName - Expected: '$Expected', Got: '$Actual'" -ForegroundColor Red
        $script:failedTests++
    }
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  RUNNING VALIDATION TEST SUITE                                                " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# Test Test-IsNumeric
Assert-Equal "IsNumeric: Valid number" (Test-IsNumeric "123") $true
Assert-Equal "IsNumeric: Leading zero" (Test-IsNumeric "05") $true
Assert-Equal "IsNumeric: Negative" (Test-IsNumeric "-1") $false
Assert-Equal "IsNumeric: Alpha string" (Test-IsNumeric "abc") $false
Assert-Equal "IsNumeric: Empty string" (Test-IsNumeric "") $false
Assert-Equal "IsNumeric: Whitespace" (Test-IsNumeric "   ") $false
Assert-Equal "IsNumeric: Injected symbols" (Test-IsNumeric "12;dir") $false

# Test Test-MenuChoiceValid
Assert-Equal "MenuChoice: Option 1 (Min)" (Test-MenuChoiceValid "1") $true
Assert-Equal "MenuChoice: Option 15 (Max)" (Test-MenuChoiceValid "15") $true
Assert-Equal "MenuChoice: Option 10 (Multi-digit)" (Test-MenuChoiceValid "10") $true
Assert-Equal "MenuChoice: Option 14 (Multi-digit)" (Test-MenuChoiceValid "14") $true
Assert-Equal "MenuChoice: Option 0 (Out of bounds)" (Test-MenuChoiceValid "0") $false
Assert-Equal "MenuChoice: Option 16 (Out of bounds)" (Test-MenuChoiceValid "16") $false
Assert-Equal "MenuChoice: Trimmed input ' 7 '" (Test-MenuChoiceValid " 7 ") $true
Assert-Equal "MenuChoice: Quit alias 'q'" (Test-MenuChoiceValid "q") $true
Assert-Equal "MenuChoice: Exit alias 'exit'" (Test-MenuChoiceValid "exit") $true
Assert-Equal "MenuChoice: Invalid word" (Test-MenuChoiceValid "format") $false

# Test Test-ValidDriveLetter
Assert-Equal "ValidDrive: System drive C:" (Test-ValidDriveLetter "C:") $true
Assert-Equal "ValidDrive: Lowercase c" (Test-ValidDriveLetter "c") $true
Assert-Equal "ValidDrive: Nonexistent drive Z" (Test-ValidDriveLetter "Z") (Test-Path "Z:\")
Assert-Equal "ValidDrive: Injected drive C:&calc" (Test-ValidDriveLetter "C:&calc") $false

# Test Test-ValidHostnameOrIp
Assert-Equal "Hostname: Valid domain" (Test-ValidHostnameOrIp "microsoft.com") $true
Assert-Equal "Hostname: Valid sub-domain" (Test-ValidHostnameOrIp "dns.google.com") $true
Assert-Equal "Hostname: Valid IPv4" (Test-ValidHostnameOrIp "8.8.8.8") $true
Assert-Equal "Hostname: Invalid IPv4" (Test-ValidHostnameOrIp "999.999.999.999") $false
Assert-Equal "Hostname: Command injection attempt" (Test-ValidHostnameOrIp "google.com;calc.exe") $false
Assert-Equal "Hostname: Pipe attempt" (Test-ValidHostnameOrIp "8.8.8.8|whoami") $false

# Test Sanitize-CliString
Assert-Equal "Sanitize: Clean string unchanged" (Sanitize-CliString "Checkpoint_1") "Checkpoint_1"
Assert-Equal "Sanitize: Strip semicolons" (Sanitize-CliString "test;calc") "testcalc"
Assert-Equal "Sanitize: Strip pipes and redirects" (Sanitize-CliString "test|dir>out") "testdirout"

Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host " TEST RESULTS: Total: $totalTests | Passed: $passedTests | Failed: $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "================================================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) { exit 1 } else { exit 0 }

