<#
.SYNOPSIS
    Common UI, system inspection, and utility functions for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Provides reusable presentation helpers, platform checks, configuration loaders,
    and formatting utilities used across all diagnostic and repair modules.
#>

function Get-ToolkitConfig {
    [CmdletBinding()]
    param()

    $baseDir = Split-Path -Parent $PSScriptRoot
    $configPath = Join-Path $baseDir "config\settings.json"

    if (Test-Path -Path $configPath) {
        try {
            $rawJson = Get-Content -Path $configPath -Raw -Encoding UTF8
            return ($rawJson | ConvertFrom-Json)
        } catch {
            Write-ToolkitLog -Message "Could not parse config/settings.json: $($_.Exception.Message). Using defaults." -Level 'WARN' -NoConsole
        }
    }

    # Fallback default configuration
    return [PSCustomObject]@{
        application = [PSCustomObject]@{
            name = "Windows Troubleshooting Toolkit"
            version = "1.0.0"
            build = "2026.10"
        }
        network = [PSCustomObject]@{
            pingTargets = @(
                [PSCustomObject]@{ name = "Google DNS"; host = "8.8.8.8" },
                [PSCustomObject]@{ name = "Cloudflare DNS"; host = "1.1.1.1" }
            )
            dnsLookupDomains = @("microsoft.com", "google.com")
            pingCount = 4
            timeoutMs = 2000
        }
        safety = [PSCustomObject]@{
            requireConfirmation = $true
            dryRunMode = $false
        }
    }
}

function Show-ToolkitBanner {
    [CmdletBinding()]
    param(
        [string]$Version = "1.0.0"
    )

    $isAdmin = Test-IsAdministrator
    $adminTag = if ($isAdmin) { "[ADMINISTRATOR: ELEVATED]" } else { "[STANDARD USER: LIMITED]" }
    $adminColor = if ($isAdmin) { "Green" } else { "Yellow" }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $osName = if ($os) { $os.Caption } else { [System.Environment]::OSVersion.VersionString }
    $buildNumber = if ($os) { $os.BuildNumber } else { [System.Environment]::OSVersion.Version.Build }

    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "         WINDOWS 10/11 ADVANCED TROUBLESHOOTING TOOLKIT  v$Version              " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  System    : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$osName (Build $buildNumber)" -ForegroundColor White
    Write-Host "  Privilege : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$adminTag" -ForegroundColor $adminColor
    Write-Host "  Computer  : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$env:COMPUTERNAME ($env:USERNAME)" -ForegroundColor Gray
    Write-Host "  Time      : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Show-SectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$Subtitle = ""
    )

    Write-Host ""
    Write-Host ">> $Title" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host "   $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host ("-" * [Math]::Max(40, ($Title.Length + 5))) -ForegroundColor DarkCyan
}

function Wait-ReturnToMenu {
    [CmdletBinding()]
    param(
        [string]$Prompt = "Press [Enter] to return to the main menu..."
    )

    Write-Host ""
    Write-Host $Prompt -ForegroundColor DarkYellow
    [void][Console]::ReadLine()
}

function Format-ByteSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Bytes
    )

    if ($Bytes -ge 1TB) {
        return "$([Math]::Round($Bytes / 1TB, 2)) TB"
    } elseif ($Bytes -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 2)) MB"
    } elseif ($Bytes -ge 1KB) {
        return "$([Math]::Round($Bytes / 1KB, 2)) KB"
    } else {
        return "$Bytes B"
    }
}

function Format-TimeSpanReadable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [TimeSpan]$Span
    )

    $parts = @()
    if ($Span.Days -gt 0) { $parts += "$($Span.Days)d" }
    if ($Span.Hours -gt 0) { $parts += "$($Span.Hours)h" }
    if ($Span.Minutes -gt 0) { $parts += "$($Span.Minutes)m" }
    if ($Span.Seconds -gt 0 -or $parts.Count -eq 0) { $parts += "$($Span.Seconds)s" }

    return ($parts -join " ")
}

