<#
.SYNOPSIS
    Disk and Storage Diagnostics Module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Analyzes storage volumes, free capacity, physical drive health status,
    media types, file system consistency, and provides safe guided CHKDSK scans.
#>

function Get-DiskDiagnosticsData {
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Gathering disk volume and physical storage metrics..." -Level 'INFO'

    # Logical Volumes
    $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 'Fixed' }
    $volumeList = @()

    foreach ($v in $volumes) {
        $sizeBytes = [double]$v.Size
        $freeBytes = [double]$v.SizeRemaining
        $pctFree = if ($sizeBytes -gt 0) { [Math]::Round(($freeBytes / $sizeBytes) * 100, 1) } else { 0 }

        $volumeList += [PSCustomObject]@{
            DriveLetter    = "$($v.DriveLetter):"
            FileSystemLabel = $v.FileSystemLabel
            FileSystem     = $v.FileSystem
            TotalSize      = Format-ByteSize -Bytes $sizeBytes
            FreeSpace      = Format-ByteSize -Bytes $freeBytes
            PercentFree    = $pctFree
            HealthStatus   = $v.HealthStatus.ToString()
            Operational    = $v.OperationalStatus.ToString()
            IsLowSpace     = ($pctFree -lt 10)
        }
    }

    # Physical Disks
    $physDisks = @()
    try {
        $pDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        foreach ($pd in $pDisks) {
            $physDisks += [PSCustomObject]@{
                DeviceId     = $pd.DeviceId
                FriendlyName = $pd.FriendlyName
                MediaType    = $pd.MediaType
                Size         = Format-ByteSize -Bytes ([double]$pd.Size)
                HealthStatus = $pd.HealthStatus
                Operational  = ($pd.OperationalStatus -join ", ")
            }
        }
    } catch {
        Write-ToolkitLog -Message "Physical disk query unavailable: $($_.Exception.Message)" -Level 'DEBUG'
    }

    return [PSCustomObject]@{
        Volumes       = $volumeList
        PhysicalDisks = $physDisks
    }
}

function Invoke-DiskDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "DISK HEALTH & STORAGE CAPACITY DIAGNOSTICS" -Subtitle "Volume free space, physical drive health, and CHKDSK"

    $data = Get-DiskDiagnosticsData

    Write-Host " [PHYSICAL STORAGE DRIVES]" -ForegroundColor Yellow
    if ($data.PhysicalDisks.Count -gt 0) {
        foreach ($pd in $data.PhysicalDisks) {
            $color = if ($pd.HealthStatus -eq 'Healthy') { "Green" } else { "Red" }
            Write-Host ("  Disk #{0} : {1} ({2}, {3})" -f $pd.DeviceId, $pd.FriendlyName, $pd.MediaType, $pd.Size) -ForegroundColor Cyan
            Write-Host ("           Health: {0} | Status: {1}" -f $pd.HealthStatus, $pd.Operational) -ForegroundColor $color
        }
    } else {
        Write-Host "  Physical disk telemetry requires administrative WMI/Storage access." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host " [LOGICAL VOLUMES & PARTITIONS]" -ForegroundColor Yellow
    foreach ($vol in $data.Volumes) {
        $warnText = if ($vol.IsLowSpace) { " [! LOW SPACE WARNING < 10%]" } else { "" }
        $color = if ($vol.IsLowSpace) { "Red" } else { "White" }

        Write-Host ("  Volume {0,-3} Label: '{1,-12}' Format: {2,-5} Free: {3} / {4} ({5}% Free){6}" -f `
            $vol.DriveLetter, $vol.FileSystemLabel, $vol.FileSystem, $vol.FreeSpace, $vol.TotalSize, $vol.PercentFree, $warnText) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Run Read-Only CHKDSK Scan (Safe, non-invasive)" -ForegroundColor White
    Write-Host "  [2] Schedule CHKDSK Repair on System Drive (Requires Reboot)" -ForegroundColor White
    Write-Host "  [3] Launch Windows Storage Sense Settings" -ForegroundColor White
    Write-Host "  [4] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-4]: " -Min 1 -Max 4

    switch ($choice) {
        "1" { Invoke-ChkdskReadOnly }
        "2" { Invoke-ScheduleChkdskRepair }
        "3" {
            Start-Process "ms-settings:storagesense" -ErrorAction SilentlyContinue
            Write-Host "Opened Storage Sense in Windows Settings." -ForegroundColor Green
            Wait-ReturnToMenu
        }
        "4" { return }
    }
}

function Invoke-ChkdskReadOnly {
    [CmdletBinding()]
    param()

    Write-Host -NoNewline "Enter drive letter to scan (e.g. C): " -ForegroundColor Cyan
    $drv = [Console]::ReadLine()

    if (-not (Test-ValidDriveLetter -DriveLetter $drv)) {
        Write-Host "Invalid drive letter or drive not found." -ForegroundColor Red
        Wait-ReturnToMenu
        return
    }

    $driveClean = $drv.Trim().Substring(0, 1).ToUpper() + ":"

    $title = "Read-Only CHKDSK Scan ($driveClean)"
    $desc = "Executes 'chkdsk.exe $driveClean' in read-only mode to check file system integrity."
    $consequences = "Non-destructive. Scans file allocation tables and security descriptors. Does NOT lock or modify drive files."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -Action {
        $p = Start-Process -FilePath "chkdsk.exe" -ArgumentList $driveClean -Wait -PassThru -NoNewWindow
        return $p.ExitCode
    }

    Wait-ReturnToMenu
}

function Invoke-ScheduleChkdskRepair {
    [CmdletBinding()]
    param()

    Write-Host -NoNewline "Enter drive letter for repair scheduling (e.g. C): " -ForegroundColor Cyan
    $drv = [Console]::ReadLine()

    if (-not (Test-ValidDriveLetter -DriveLetter $drv)) {
        Write-Host "Invalid drive letter." -ForegroundColor Red
        Wait-ReturnToMenu
        return
    }

    $driveClean = $drv.Trim().Substring(0, 1).ToUpper() + ":"

    $title = "Schedule CHKDSK File System Repair ($driveClean /f /r)"
    $desc = "Schedules an offline CHKDSK repair with bad sector detection on next system boot."
    $consequences = "Since active system volumes cannot be unmounted while Windows is running, this prompts Windows to lock and check the volume during the next system reboot. Depending on drive size, startup may take 10-60 minutes."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -RecoveryAdvice "If startup scan gets stuck, allow it to complete or power cycle into Windows Recovery Environment (WinRE)." -Action {
        Write-Host " Running chkdsk $driveClean /f..." -ForegroundColor DarkCyan
        $p = Start-Process -FilePath "chkdsk.exe" -ArgumentList "$driveClean /f" -Wait -PassThru -NoNewWindow
        return $p.ExitCode
    }

    Wait-ReturnToMenu
}

