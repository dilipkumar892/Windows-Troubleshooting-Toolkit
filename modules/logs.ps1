<#
.SYNOPSIS
    Log viewer, search, and Windows Event Log module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Provides interactive viewing and searching of active session logs, historical
    logs, and queries Windows Event Logs for recent System and Application errors.
#>

function Invoke-LogsMenu {
    [CmdletBinding()]
    param()

    while ($true) {
        Show-SectionHeader -Title "LOGGING, TRANSCRIPTS & WINDOWS EVENT AUDIT" -Subtitle "Review session logs, command history, and system error events"

        $currentLog = Get-CurrentLogFilePath
        Write-Host "  Active Session Log: $currentLog" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host " Available Log Tools:" -ForegroundColor Cyan
        Write-Host "  [1] View Last 30 Lines of Current Session Log" -ForegroundColor White
        Write-Host "  [2] Search Session Log for Errors/Warnings" -ForegroundColor White
        Write-Host "  [3] List All Toolkit Log Files" -ForegroundColor White
        Write-Host "  [4] Query Windows Event Log (System & App Errors in Last 24h)" -ForegroundColor White
        Write-Host "  [5] Export Current Log to Custom Location" -ForegroundColor White
        Write-Host "  [6] Return to Main Menu" -ForegroundColor DarkGray
        Write-Host ""

        $choice = Get-ValidatedMenuChoice -Prompt "Select log option [1-6]: " -Min 1 -Max 6

        switch ($choice) {
            "1" {
                Show-RecentSessionLogs -Lines 30
            }
            "2" {
                Search-SessionLog
            }
            "3" {
                Show-AllLogFiles
            }
            "4" {
                Invoke-WindowsEventLogAudit
            }
            "5" {
                Invoke-ExportLogAction
            }
            "6" {
                return
            }
        }
    }
}

function Show-RecentSessionLogs {
    param([int]$Lines = 30)

    $currentLog = Get-CurrentLogFilePath
    if (-not (Test-Path $currentLog)) {
        Write-Host "No active log file created yet." -ForegroundColor Yellow
        Wait-ReturnToMenu
        return
    }

    Write-Host ""
    Write-Host "--- [LAST $Lines LINES OF SESSION LOG] ---" -ForegroundColor DarkCyan
    Get-Content -Path $currentLog -Tail $Lines | ForEach-Object {
        if ($_ -match '\[ERROR\]') {
            Write-Host $_ -ForegroundColor Red
        } elseif ($_ -match '\[WARN\]') {
            Write-Host $_ -ForegroundColor Yellow
        } elseif ($_ -match '\[SUCCESS\]') {
            Write-Host $_ -ForegroundColor Green
        } else {
            Write-Host $_ -ForegroundColor White
        }
    }
    Write-Host "--- [END OF LOG] ---" -ForegroundColor DarkCyan

    Wait-ReturnToMenu
}

function Search-SessionLog {
    $currentLog = Get-CurrentLogFilePath
    if (-not (Test-Path $currentLog)) {
        Write-Host "No active log file." -ForegroundColor Yellow
        Wait-ReturnToMenu
        return
    }

    Write-Host -NoNewline "Enter keyword to search (default: ERROR): " -ForegroundColor Cyan
    $term = [Console]::ReadLine()
    if ([string]::IsNullOrWhiteSpace($term)) { $term = "ERROR" }

    Write-Host ""
    Write-Host "--- [MATCHES FOR '$term'] ---" -ForegroundColor DarkCyan
    $matches = Select-String -Path $currentLog -Pattern $term -SimpleMatch
    if ($matches.Count -gt 0) {
        foreach ($m in $matches) {
            Write-Host "Line $($m.LineNumber): $($m.Line)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No entries matched '$term'." -ForegroundColor Green
    }
    Write-Host "--- [END OF RESULTS] ---" -ForegroundColor DarkCyan

    Wait-ReturnToMenu
}

function Show-AllLogFiles {
    $logs = Get-AllLogFiles
    Write-Host ""
    Write-Host "--- [ALL TOOLKIT LOG FILES] ---" -ForegroundColor DarkCyan
    if ($logs.Count -gt 0) {
        $logs | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
    } else {
        Write-Host "No archived log files found." -ForegroundColor DarkGray
    }

    Wait-ReturnToMenu
}

function Invoke-WindowsEventLogAudit {
    Show-SectionHeader -Title "WINDOWS EVENT LOG AUDIT" -Subtitle "Recent Critical & Error events from System & Application logs (past 24h)"

    $filter = @{
        LogName   = @('System', 'Application')
        Level     = @(1, 2) # 1 = Critical, 2 = Error
        StartTime = (Get-Date).AddHours(-24)
    }

    Write-Host " Querying Windows Event Log for past 24 hours..." -ForegroundColor Cyan

    try {
        $events = Get-WinEvent -FilterHashtable $filter -MaxEvents 30 -ErrorAction Stop
        if ($events.Count -gt 0) {
            Write-Host (" Found {0} recent error events:" -f $events.Count) -ForegroundColor Yellow
            $events | Select-Object -Property TimeCreated, LogName, ProviderName, Id, @{Name="Message"; Expression={$_.Message.Replace("`r`n", " ").Substring(0, [Math]::Min(80, $_.Message.Length))}} |
                Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
        } else {
            Write-Host " [PASS] No Critical or Error events recorded in System or Application logs in the last 24 hours." -ForegroundColor Green
        }
    } catch {
        Write-Host " Notice: No events matched filter or insufficient permissions: $($_.Exception.Message)" -ForegroundColor DarkGray
    }

    Wait-ReturnToMenu
}

function Invoke-ExportLogAction {
    Write-Host -NoNewline "Enter destination file path (e.g. C:\Users\Public\toolkit_export.log): " -ForegroundColor Cyan
    $dest = [Console]::ReadLine()

    if ([string]::IsNullOrWhiteSpace($dest)) {
        Write-Host "Export canceled. No path provided." -ForegroundColor Yellow
    } else {
        $sanitized = Sanitize-CliString -InputText $dest
        Export-ToolkitLogs -DestinationPath $sanitized
    }

    Wait-ReturnToMenu
}

