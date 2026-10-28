<#
.SYNOPSIS
    System Restore Point Management Module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Audits System Protection status, lists existing restore points, explains
    architectural limitations, and provides safe creation and recovery workflows.
#>

function Get-RestorePointData {
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Checking System Protection and Restore Points..." -Level 'INFO'

    # System protection status
    $protectionStatus = @()
    try {
        $protectionStatus = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    } catch {
        Write-ToolkitLog -Message "Could not query restore points: $($_.Exception.Message)" -Level 'DEBUG'
    }

    # Volume Shadow Copy Service status
    $vss = Get-Service -Name "VSS" -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        RestorePoints = $protectionStatus
        VssService    = $vss
    }
}

function Invoke-RestorePointManagement {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "SYSTEM RESTORE POINT MANAGEMENT" -Subtitle "Inspect, create, and launch Windows System Restore"

    $data = Get-RestorePointData

    Write-Host " [UNDERSTANDING SYSTEM RESTORE]" -ForegroundColor Yellow
    Write-Host "  * What it does : Reverts Windows system files, registry hives, and installed" -ForegroundColor White
    Write-Host "                   drivers to a previous healthy snapshot in time." -ForegroundColor White
    Write-Host "  * Limitations  : Does NOT affect or back up personal user files (Documents, Photos," -ForegroundColor DarkYellow
    Write-Host "                   Desktop). It cannot repair physical disk failures." -ForegroundColor DarkYellow
    Write-Host "  * Dependencies : Requires the Volume Shadow Copy Service (VSS)." -ForegroundColor DarkGray

    Write-Host ""
    Write-Host " [VOLUME SHADOW COPY SERVICE (VSS)]" -ForegroundColor Yellow
    if ($data.VssService) {
        $vssColor = if ($data.VssService.Status -eq 'Running') { "Green" } else { "DarkGray" }
        Write-Host ("  Status: {0} | Startup Type: {1}" -f $data.VssService.Status, $data.VssService.StartType) -ForegroundColor $vssColor
    }

    Write-Host ""
    Write-Host " [EXISTING RESTORE POINTS]" -ForegroundColor Yellow
    if ($data.RestorePoints -and $data.RestorePoints.Count -gt 0) {
        $data.RestorePoints | Select-Object -Property SequenceNumber, Description, CreationTime, EventType |
            Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
    } else {
        Write-Host "  No restore points found. System Protection may be disabled or shadow storage full." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Create New System Restore Point" -ForegroundColor White
    Write-Host "  [2] Enable System Protection on C: Drive" -ForegroundColor White
    Write-Host "  [3] Launch Windows System Restore Wizard (rstrui.exe)" -ForegroundColor White
    Write-Host "  [4] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-4]: " -Min 1 -Max 4

    switch ($choice) {
        "1" { Invoke-CreateRestorePoint }
        "2" { Invoke-EnableSystemProtection }
        "3" { Invoke-LaunchRestoreWizard }
        "4" { return }
    }
}

function Invoke-CreateRestorePoint {
    [CmdletBinding()]
    param()

    if (-not (Assert-Administrator -OperationName "Create Restore Point")) {
        Wait-ReturnToMenu
        return
    }

    Write-Host -NoNewline "Enter description for this restore point: " -ForegroundColor Cyan
    $customDesc = [Console]::ReadLine()
    if ([string]::IsNullOrWhiteSpace($customDesc)) {
        $customDesc = "Manual_WTT_Checkpoint_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }
    $sanitizedDesc = Sanitize-CliString -InputText $customDesc

    $title = "Create System Restore Point"
    $desc = "Creates a checkpoint named '$sanitizedDesc' using Checkpoint-Computer."
    $consequences = "Takes a snapshot of system files and registry. Consumes ~500MB - 2GB of shadow storage."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -Action {
        Write-Host " Creating restore point '$sanitizedDesc'..." -ForegroundColor Cyan
        # In Windows 10/11, Checkpoint-Computer is throttled if one was created in the last 24h unless frequency registry key is adjusted
        Checkpoint-Computer -Description $sanitizedDesc -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host " System restore point created successfully." -ForegroundColor Green
        return 0
    }

    Wait-ReturnToMenu
}

function Invoke-EnableSystemProtection {
    [CmdletBinding()]
    param()

    $title = "Enable System Protection on C: Drive"
    $desc = "Executes 'Enable-ComputerRestore -Drive C:' to allocate shadow copy storage."
    $consequences = "Turns on restore point creation for the main operating system volume."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -Action {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop
        Write-Host " System protection enabled on C:\." -ForegroundColor Green
        return 0
    }

    Wait-ReturnToMenu
}

function Invoke-LaunchRestoreWizard {
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host " [WARNING] Launching the System Restore Wizard will allow you to revert your system" -ForegroundColor Yellow
    Write-Host " to an earlier point. Reverting will restart Windows and uninstall programs added after that point." -ForegroundColor Yellow
    Write-Host ""

    $proceed = Confirm-UserAction -PromptMessage " Open System Restore Wizard (rstrui.exe)?" -DefaultChoice "N"
    if ($proceed) {
        Write-ToolkitLog -Message "User opened System Restore Wizard (rstrui.exe)." -Level 'AUDIT'
        Start-Process "rstrui.exe"
    } else {
        Write-Host "Operation canceled." -ForegroundColor DarkGray
    }

    Wait-ReturnToMenu
}

