<#
.SYNOPSIS
    Advanced System Repair Subsystem for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Encapsulates advanced guided repairs (Winsock/IP stack, Print Spooler,
    Time synchronization, BCD inspection) with strict confirmation and safety checks.
#>

function Invoke-AdvancedRepairMenu {
    [CmdletBinding()]
    param()

    while ($true) {
        Show-SectionHeader -Title "ADVANCED SYSTEM REPAIR UTILITIES" -Subtitle "Guided repairs with strict safety gates and recovery guidance"

        Write-Host " Available Repairs:" -ForegroundColor Cyan
        Write-Host "  [1] Reset Winsock & TCP/IP Stack" -ForegroundColor White
        Write-Host "  [2] Reset Windows Update Services and Cache" -ForegroundColor White
        Write-Host "  [3] Restart Print Spooler & Purge Stuck Print Queue" -ForegroundColor White
        Write-Host "  [4] Resynchronize System Clock with Windows Time Service" -ForegroundColor White
        Write-Host "  [5] Inspect Boot Configuration Data (BCD) Health" -ForegroundColor White
        Write-Host "  [6] Return to Main Menu" -ForegroundColor DarkGray
        Write-Host ""

        $choice = Get-ValidatedMenuChoice -Prompt "Select repair tool [1-6]: " -Min 1 -Max 6

        switch ($choice) {
            "1" {
                Invoke-ResetNetworkStack
            }
            "2" {
                Invoke-SafeWindowsUpdateReset
            }
            "3" {
                Invoke-RepairPrintSpooler
            }
            "4" {
                Invoke-RepairTimeSync
            }
            "5" {
                Invoke-InspectBcdHealth
            }
            "6" {
                return
            }
        }
    }
}

function Invoke-RepairPrintSpooler {
    [CmdletBinding()]
    param()

    $title = "Restart Print Spooler & Clear Stuck Print Queue"
    $desc = "Stops 'spooler' service, removes corrupt pending print jobs (.SPL and .SHD) from C:\Windows\System32\spool\PRINTERS, and restarts the spooler."
    $consequences = "Any pending, unprinted documents queued in printer spoolers will be deleted. Print drivers remain untouched."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -Action {
        Write-Host " Stopping Print Spooler service..." -ForegroundColor DarkGray
        Stop-Service -Name "spooler" -Force -ErrorAction SilentlyContinue

        $spoolFolder = "$env:windir\System32\spool\PRINTERS"
        if (Test-Path -Path $spoolFolder) {
            $files = Get-ChildItem -Path $spoolFolder -File -ErrorAction SilentlyContinue
            Write-Host " Clearing $($files.Count) orphaned spool file(s)..." -ForegroundColor DarkGray
            foreach ($f in $files) {
                Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host " Starting Print Spooler service..." -ForegroundColor DarkGray
        Start-Service -Name "spooler" -ErrorAction Stop

        Write-Host " Print Spooler restarted successfully." -ForegroundColor Green
        return 0
    }

    Wait-ReturnToMenu
}

function Invoke-RepairTimeSync {
    [CmdletBinding()]
    param()

    $title = "Resynchronize System Time"
    $desc = "Starts the Windows Time service (w32time) and triggers an immediate resync via 'w32tm /resync'."
    $consequences = "Corrects clock drift with time.windows.com or domain hierarchy. Fixes SSL/TLS certificate errors caused by inaccurate system clock."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -RecoveryAdvice "If time sync fails, ensure UDP port 123 is not blocked by your firewall/router." -Action {
        Write-Host " Ensuring w32time service is running..." -ForegroundColor DarkGray
        Start-Service -Name "w32time" -ErrorAction SilentlyContinue

        Write-Host " Executing w32tm /resync..." -ForegroundColor DarkGray
        $p = Start-Process -FilePath "w32tm.exe" -ArgumentList "/resync" -Wait -PassThru -NoNewWindow
        return $p.ExitCode
    }

    Wait-ReturnToMenu
}

function Invoke-InspectBcdHealth {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "BOOT CONFIGURATION DATA (BCD) AUDIT" -Subtitle "Inspect Windows Boot Manager and Boot Loader entries"

    if (-not (Assert-Administrator -OperationName "BCD Inspection")) {
        Wait-ReturnToMenu
        return
    }

    Write-Host " Querying Windows Boot Configuration Data via bcdedit /enum..." -ForegroundColor Cyan
    Write-Host " (Read-only inspection - does not alter boot parameters)" -ForegroundColor DarkGray
    Write-Host ""

    $p = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/enum" -Wait -PassThru -NoNewWindow
    Write-CommandExecutionLog -Command "bcdedit /enum" -ExitCode $p.ExitCode

    Wait-ReturnToMenu
}

