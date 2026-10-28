<#
.SYNOPSIS
    Centralized logging module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Provides thread-safe, UTF-8 encoded, timestamped file and console logging
    with log levels, command tracking, exit-code recording, and export features.
#>

# Module-scoped logger state
$script:LogFile = $null
$script:LogDirectory = $null
$script:LogLevels = @{
    'DEBUG'   = 0
    'INFO'    = 1
    'SUCCESS' = 1
    'AUDIT'   = 1
    'WARN'    = 2
    'ERROR'   = 3
}
$script:ConfiguredLevel = 1

function Initialize-Logger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$LogDirPath,

        [Parameter(Mandatory = $false)]
        [string]$MinLevel = "INFO",

        [Parameter(Mandatory = $false)]
        [int]$RetentionDays = 30
    )

    if ([string]::IsNullOrWhiteSpace($LogDirPath)) {
        $baseDir = Split-Path -Parent $PSScriptRoot
        $script:LogDirectory = Join-Path $baseDir "logs"
    } else {
        $script:LogDirectory = $LogDirPath
    }

    if (-not (Test-Path -Path $script:LogDirectory)) {
        New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null
    }

    if ($script:LogLevels.ContainsKey($MinLevel.ToUpper())) {
        $script:ConfiguredLevel = $script:LogLevels[$MinLevel.ToUpper()]
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $script:LogFile = Join-Path $script:LogDirectory "troubleshooting_$timestamp.log"

    # Initialize log file with UTF-8 header
    $header = @"
================================================================================
Windows Troubleshooting Toolkit - Session Log
Session Started : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
Host Machine    : $env:COMPUTERNAME
User Context    : $env:USERDOMAIN\$env:USERNAME
Is Elevated     : $([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
PowerShell Ver  : $($PSVersionTable.PSVersion.ToString())
Log File        : $script:LogFile
================================================================================

"@
    [System.IO.File]::WriteAllText($script:LogFile, $header, [System.Text.Encoding]::UTF8)

    # Perform log rotation on old files
    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $script:LogDirectory -Filter "troubleshooting_*.log" -File |
            Where-Object { $_.LastWriteTime -lt $cutoffDate } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore rotation failure to not block logger
    }

    return $script:LogFile
}

function Write-ToolkitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'AUDIT', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )

    $levelUpper = $Level.ToUpper()
    $msgLevelVal = if ($script:LogLevels.ContainsKey($levelUpper)) { $script:LogLevels[$levelUpper] } else { 1 }

    # Check minimum log level
    if ($msgLevelVal -lt $script:ConfiguredLevel -and $levelUpper -ne 'SUCCESS' -and $levelUpper -ne 'AUDIT') {
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $formattedLogLine = "[$timestamp] [$levelUpper] $Message"

    # Write to log file in UTF-8
    if ($script:LogFile -and (Test-Path -Path (Split-Path -Parent $script:LogFile))) {
        try {
            [System.IO.File]::AppendAllText($script:LogFile, "$formattedLogLine`r`n", [System.Text.Encoding]::UTF8)
        } catch {
            # Fallback if file is locked
        }
    }

    # Write to console if requested
    if (-not $NoConsole) {
        $fgColor = switch ($levelUpper) {
            'DEBUG'   { 'DarkGray' }
            'INFO'    { 'White' }
            'SUCCESS' { 'Green' }
            'AUDIT'   { 'Cyan' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            Default   { 'White' }
        }

        $tagColor = switch ($levelUpper) {
            'DEBUG'   { 'DarkGray' }
            'INFO'    { 'Cyan' }
            'SUCCESS' { 'Green' }
            'AUDIT'   { 'Magenta' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            Default   { 'Gray' }
        }

        Write-Host -NoNewline "[$timestamp] " -ForegroundColor DarkGray
        Write-Host -NoNewline "[$levelUpper] " -ForegroundColor $tagColor
        Write-Host $Message -ForegroundColor $fgColor
    }
}

function Write-CommandExecutionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [int]$ExitCode = 0,

        [Parameter(Mandatory = $false)]
        [double]$DurationSeconds = 0.0,

        [Parameter(Mandatory = $false)]
        [string]$OutputSummary = ""
    )

    $status = if ($ExitCode -eq 0) { "SUCCESS" } else { "FAILED (ExitCode: $ExitCode)" }
    $entry = "COMMAND EXECUTED: '$Command' | Result: $status | Duration: $([Math]::Round($DurationSeconds, 2))s"
    if (-not [string]::IsNullOrWhiteSpace($OutputSummary)) {
        $entry += " | Output: $OutputSummary"
    }

    $level = if ($ExitCode -eq 0) { 'AUDIT' } else { 'ERROR' }
    Write-ToolkitLog -Message $entry -Level $level -NoConsole
}

function Get-CurrentLogFilePath {
    return $script:LogFile
}

function Get-AllLogFiles {
    if (-not $script:LogDirectory -or -not (Test-Path -Path $script:LogDirectory)) {
        return @()
    }
    return Get-ChildItem -Path $script:LogDirectory -Filter "troubleshooting_*.log" -File |
        Sort-Object LastWriteTime -Descending
}

function Export-ToolkitLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    try {
        if (Test-Path -Path $script:LogFile) {
            Copy-Item -Path $script:LogFile -Destination $DestinationPath -Force
            Write-ToolkitLog -Message "Exported active log file to: $DestinationPath" -Level 'SUCCESS'
            return $true
        } else {
            Write-ToolkitLog -Message "Active log file not found for export." -Level 'WARN'
            return $false
        }
    } catch {
        Write-ToolkitLog -Message "Failed to export logs: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

