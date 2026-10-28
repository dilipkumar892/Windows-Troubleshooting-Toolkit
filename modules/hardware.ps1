<#
.SYNOPSIS
    Hardware and Device Diagnostics Module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Audits physical processors, memory modules, motherboard/BIOS, power/battery state,
    and identifies hardware devices reporting Device Manager error codes.
#>

function Get-HardwareDiagnosticsData {
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Auditing hardware components and device manager status..." -Level 'INFO'

    # Motherboard & BIOS
    $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue

    # Processor
    $proc = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

    # RAM Modules
    $ramSticks = @()
    $physicalMem = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue
    foreach ($m in $physicalMem) {
        $ramSticks += [PSCustomObject]@{
            BankLabel    = $m.BankLabel
            DeviceLocator = $m.DeviceLocator
            Capacity     = Format-ByteSize -Bytes ([double]$m.Capacity)
            Speed        = "$($m.Speed) MHz"
            Manufacturer = if ($m.Manufacturer) { $m.Manufacturer.Trim() } else { "Unknown" }
            PartNumber   = if ($m.PartNumber) { $m.PartNumber.Trim() } else { "Unknown" }
        }
    }

    # Battery
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $batteryInfo = if ($battery) {
        [PSCustomObject]@{
            Present         = $true
            ChargePercent   = "$($battery.EstimatedChargeRemaining)%"
            EstimatedRuntime = "$($battery.EstimatedRunTime) mins"
            Status          = $battery.Status
        }
    } else {
        [PSCustomObject]@{ Present = $false }
    }

    # Problem Devices (Device Manager Error Codes)
    $problemDevices = @()
    $pnpEntities = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null }

    foreach ($dev in $pnpEntities) {
        $problemDevices += [PSCustomObject]@{
            Name        = $dev.Name
            Description = $dev.Description
            ErrorCode   = $dev.ConfigManagerErrorCode
            Status      = $dev.Status
            DeviceID    = $dev.DeviceID
        }
    }

    return [PSCustomObject]@{
        Board          = $board
        BIOS           = $bios
        Processor      = $proc
        RAMSticks      = $ramSticks
        Battery        = $batteryInfo
        ProblemDevices = $problemDevices
    }
}

function Invoke-HardwareDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "HARDWARE & DEVICE SUBSYSTEM DIAGNOSTICS" -Subtitle "Audit CPU, memory slots, power, motherboard, and failed device drivers"

    $hw = Get-HardwareDiagnosticsData

    Write-Host " [MOTHERBOARD & BIOS]" -ForegroundColor Yellow
    Write-Host ("  Motherboard : {0} (Model: {1})" -f $hw.Board.Manufacturer, $hw.Board.Product) -ForegroundColor White
    Write-Host ("  BIOS Info   : {0} {1} (Release: {2})" -f $hw.BIOS.Manufacturer, $hw.BIOS.SMBIOSBIOSVersion, $hw.BIOS.ReleaseDate) -ForegroundColor White

    Write-Host ""
    Write-Host " [PROCESSOR ARCHITECTURE]" -ForegroundColor Yellow
    Write-Host ("  Model       : {0}" -f $hw.Processor.Name) -ForegroundColor White
    Write-Host ("  Clock Speed : {0} MHz | Cores: {1} | Threads: {2}" -f $hw.Processor.MaxClockSpeed, $hw.Processor.NumberOfCores, $hw.Processor.NumberOfLogicalProcessors) -ForegroundColor White

    Write-Host ""
    Write-Host " [PHYSICAL MEMORY SLOTS]" -ForegroundColor Yellow
    if ($hw.RAMSticks.Count -gt 0) {
        $hw.RAMSticks | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
    } else {
        Write-Host "  Could not enumerate individual memory sticks (virtualized or limited WMI permissions)." -ForegroundColor DarkGray
    }

    if ($hw.Battery.Present) {
        Write-Host " [BATTERY SUBSYSTEM]" -ForegroundColor Yellow
        Write-Host ("  Charge Level     : {0}" -f $hw.Battery.ChargePercent) -ForegroundColor Green
        Write-Host ("  Estimated Runtime: {0}" -f $hw.Battery.EstimatedRuntime) -ForegroundColor White
        Write-Host ("  Operational State: {0}" -f $hw.Battery.Status) -ForegroundColor White
        Write-Host ""
    }

    Write-Host " [DEVICE MANAGER ERROR AUDIT]" -ForegroundColor Yellow
    if ($hw.ProblemDevices.Count -eq 0) {
        Write-Host "  [PASS] No device hardware errors detected. All PnP devices are operating normally." -ForegroundColor Green
    } else {
        Write-Host ("  [!] Detected {0} device(s) reporting error codes in Device Manager:" -f $hw.ProblemDevices.Count) -ForegroundColor Red
        foreach ($d in $hw.ProblemDevices) {
            $codeExplanation = switch ($d.ErrorCode) {
                1  { "Device not configured correctly (Code 1)" }
                10 { "Device cannot start - driver error or hardware failure (Code 10)" }
                12 { "Resource conflict (Code 12)" }
                14 { "Computer requires reboot to complete device setup (Code 14)" }
                22 { "Device is disabled by user or policy (Code 22)" }
                28 { "Drivers for this device are not installed (Code 28)" }
                31 { "Windows cannot load driver (Code 31)" }
                43 { "Device stopped because it reported problems (Code 43 - common GPU/USB failure)" }
                Default { "Device error code $($d.ErrorCode)" }
            }

            Write-Host ("  - {0}" -f $d.Name) -ForegroundColor Yellow
            Write-Host ("    Issue : {0}" -f $codeExplanation) -ForegroundColor Red
            Write-Host ("    ID    : {0}" -f $d.DeviceID) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Open Windows Device Manager (devmgmt.msc)" -ForegroundColor White
    Write-Host "  [2] Generate Battery Health Report (powercfg /batteryreport)" -ForegroundColor White
    Write-Host "  [3] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-3]: " -Min 1 -Max 3

    switch ($choice) {
        "1" {
            Start-Process "devmgmt.msc" -ErrorAction SilentlyContinue
            Write-Host "Launched Device Manager." -ForegroundColor Green
            Wait-ReturnToMenu
        }
        "2" {
            Invoke-BatteryReport
        }
        "3" { return }
    }
}

function Invoke-BatteryReport {
    [CmdletBinding()]
    param()

    $baseDir = Split-Path -Parent $PSScriptRoot
    $outPath = Join-Path $baseDir "reports\battery_report.html"

    Write-Host " Generating Windows battery diagnostics report via powercfg..." -ForegroundColor Cyan
    $p = Start-Process -FilePath "powercfg.exe" -ArgumentList "/batteryreport /output `"$outPath`"" -Wait -PassThru -NoNewWindow

    if (Test-Path -Path $outPath) {
        Write-Host " [SUCCESS] Battery health report created at: $outPath" -ForegroundColor Green
        $open = Confirm-UserAction -PromptMessage " Open report in default browser?" -DefaultChoice "Y"
        if ($open) {
            Start-Process $outPath
        }
    } else {
        Write-Host " [NOTICE] Battery report is only supported on battery-powered devices (laptops/tablets)." -ForegroundColor Yellow
    }

    Wait-ReturnToMenu
}

