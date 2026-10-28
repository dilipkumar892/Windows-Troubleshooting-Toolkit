<#
.SYNOPSIS
    Safety gatekeeper and execution guardian for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Ensures that any modifying or repair action adheres to safety rules:
    - Pre-check for administrative privileges
    - Transparent disclosure of what the operation does
    - Plain-language explanation of potential consequences
    - Explicit user confirmation requirement
    - Safe logging and exit code tracking
    - Failure recovery recommendations
#>

function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Assert-Administrator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "This operation"
    )

    if (-not (Test-IsAdministrator)) {
        Write-Host ""
        Write-Host " [ERROR] ELEVATED PRIVILEGES REQUIRED" -ForegroundColor Red
        Write-Host " $OperationName requires Administrator rights to execute safely." -ForegroundColor Yellow
        Write-Host " Please close this session and relaunch 'launcher.bat' by right-clicking and selecting 'Run as Administrator'." -ForegroundColor White
        Write-Host ""
        Write-ToolkitLog -Message "Operation blocked: '$OperationName' attempted without administrator privileges." -Level 'WARN'
        return $false
    }
    return $true
}

function Invoke-SafeRepairOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Consequences,

        [Parameter(Mandatory = $false)]
        [string]$RecoveryAdvice = "If issues persist, check system event logs, run SFC/DISM, or revert to a recent System Restore point.",

        [Parameter(Mandatory = $false)]
        [bool]$RequiresAdmin = $true,

        [Parameter(Mandatory = $false)]
        [bool]$DryRun = $false,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  REPAIR SAFETY REVIEW: $Title" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  ACTION       : " -NoNewline -ForegroundColor Gray
    Write-Host "$Description" -ForegroundColor White
    Write-Host "  CONSEQUENCES : " -NoNewline -ForegroundColor Gray
    Write-Host "$Consequences" -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "  MODE         : " -NoNewline -ForegroundColor Gray
        Write-Host "[SIMULATION / DRY RUN - NO CHANGES WILL BE MADE]" -ForegroundColor Magenta
        Write-ToolkitLog -Message "Dry run simulation initiated for: $Title" -Level 'INFO'
        return @{ Success = $true; ExitCode = 0; Message = "Simulated run successful." }
    }

    if ($RequiresAdmin) {
        if (-not (Test-IsAdministrator)) {
            Write-Host "  ADMIN CHECK  : " -NoNewline -ForegroundColor Gray
            Write-Host "[FAIL] Requires Administrator privileges." -ForegroundColor Red
            Write-ToolkitLog -Message "Safe repair '$Title' denied: Not running as Administrator." -Level 'ERROR'
            return @{ Success = $false; ExitCode = -1; Message = "Requires administrator privileges." }
        } else {
            Write-Host "  ADMIN CHECK  : " -NoNewline -ForegroundColor Gray
            Write-Host "[PASS] Running as Administrator." -ForegroundColor Green
        }
    }

    Write-Host ""
    $proceed = Confirm-UserAction -PromptMessage " Do you want to proceed with this repair?" -DefaultChoice "N"

    if (-not $proceed) {
        Write-Host " Operation canceled by user. No changes were made." -ForegroundColor Yellow
        Write-ToolkitLog -Message "Safe repair '$Title' canceled by user." -Level 'INFO'
        return @{ Success = $false; ExitCode = 0; Message = "Operation canceled by user." }
    }

    Write-Host ""
    Write-Host " [RUNNING] Executing: $Title..." -ForegroundColor Cyan
    Write-ToolkitLog -Message "Initiating safe repair: '$Title' - $Description" -Level 'AUDIT'

    $startTime = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = 0
    $success = $true
    $errorMessage = ""
    $capturedOutput = @()

    try {
        $result = & $Action
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            $success = ($exitCode -eq 0)
        }
        $capturedOutput += $result
    } catch {
        $success = $false
        $exitCode = if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
        $errorMessage = $_.Exception.Message
        Write-Host " [ERROR] An exception occurred during repair: $errorMessage" -ForegroundColor Red
    } finally {
        $startTime.Stop()
    }

    $elapsedSec = $startTime.Elapsed.TotalSeconds
    Write-CommandExecutionLog -Command $Title -ExitCode $exitCode -DurationSeconds $elapsedSec -OutputSummary ($errorMessage + " " + ($capturedOutput -join " "))

    Write-Host ""
    if ($success -and $exitCode -eq 0) {
        Write-Host " [COMPLETED] '$Title' finished successfully in $([Math]::Round($elapsedSec, 2))s." -ForegroundColor Green
        Write-ToolkitLog -Message "Safe repair '$Title' completed successfully (ExitCode: 0)." -Level 'SUCCESS'
    } else {
        Write-Host " [WARNING/FAILURE] '$Title' reported exit code $exitCode." -ForegroundColor Yellow
        if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
            Write-Host " Details: $errorMessage" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host " RECOVERY GUIDANCE:" -ForegroundColor Cyan
        Write-Host " $RecoveryAdvice" -ForegroundColor White
        Write-ToolkitLog -Message "Safe repair '$Title' failed with exit code $exitCode. Error: $errorMessage" -Level 'WARN'
    }

    return @{
        Success = $success
        ExitCode = $exitCode
        DurationSeconds = $elapsedSec
        Output = $capturedOutput
        ErrorMessage = $errorMessage
    }
}
