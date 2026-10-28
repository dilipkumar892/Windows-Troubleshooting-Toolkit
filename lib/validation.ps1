<#
.SYNOPSIS
    Input validation and sanitization library for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Validates user choices, numbers, drive letters, hostnames, IP addresses,
    and confirmations to prevent crashes, command injection, and unexpected behavior.
#>

function Test-IsNumeric {
    param([string]$InputString)
    if ([string]::IsNullOrWhiteSpace($InputString)) { return $false }
    return ($InputString -match '^\d+$')
}

function Test-MenuChoiceValid {
    [CmdletBinding()]
    param(
        [string]$Choice,
        [int]$Min = 1,
        [int]$Max = 15
    )

    if ([string]::IsNullOrWhiteSpace($Choice)) {
        return $false
    }

    $trimmed = $Choice.Trim()
    if ($trimmed -match '^\d+$') {
        $num = [int]$trimmed
        return ($num -ge $Min -and $num -le $Max)
    }

    # Also support 'q' or 'exit' as valid exit aliases if needed
    if ($trimmed.ToLower() -in @('q', 'exit', 'quit')) {
        return $true
    }

    return $false
}

function Get-ValidatedMenuChoice {
    [CmdletBinding()]
    param(
        [string]$Prompt = "Enter choice [1-15] (or 'Q' to quit): ",
        [int]$Min = 1,
        [int]$Max = 15
    )

    while ($true) {
        Write-Host -NoNewline "$Prompt" -ForegroundColor Cyan
        $raw = [Console]::ReadLine()

        if ($null -eq $raw) {
            # Stream closed or EOF
            return "15"
        }

        $inputClean = $raw.Trim()

        if ([string]::IsNullOrWhiteSpace($inputClean)) {
            Write-Host " [!] Empty input. Please enter a valid number between $Min and $Max." -ForegroundColor Yellow
            continue
        }

        if ($inputClean.ToLower() -in @('q', 'quit', 'exit')) {
            return [string]$Max
        }

        if ($inputClean -match '^\d+$') {
            $num = [int]$inputClean
            if ($num -ge $Min -and $num -le $Max) {
                return [string]$num
            } else {
                Write-Host " [!] Out of range ($num). Please enter a choice between $Min and $Max." -ForegroundColor Yellow
            }
        } else {
            Write-Host " [!] Invalid input '$inputClean'. Please enter numeric digits only." -ForegroundColor Red
        }
    }
}

function Confirm-UserAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptMessage,

        [Parameter(Mandatory = $false)]
        [string]$DefaultChoice = "N"
    )

    $promptSuffix = if ($DefaultChoice.ToUpper() -eq "Y") { "[Y/n]" } else { "[y/N]" }

    while ($true) {
        Write-Host -NoNewline "$PromptMessage ${promptSuffix}: " -ForegroundColor Yellow
        $raw = [Console]::ReadLine()

        if ($null -eq $raw -or [string]::IsNullOrWhiteSpace($raw)) {
            return ($DefaultChoice.ToUpper() -eq "Y")
        }

        $clean = $raw.Trim().ToUpper()
        if ($clean -in @('Y', 'YES')) {
            return $true
        }
        if ($clean -in @('N', 'NO')) {
            return $false
        }

        Write-Host " [!] Please answer 'Y' for Yes or 'N' for No." -ForegroundColor DarkYellow
    }
}

function Test-ValidDriveLetter {
    param([string]$DriveLetter)

    if ([string]::IsNullOrWhiteSpace($DriveLetter)) { return $false }
    $clean = $DriveLetter.Trim().ToUpper()
    if ($clean -match '^[A-Z]:?$') {
        $letterOnly = $clean.Substring(0, 1)
        return (Test-Path -Path "${letterOnly}:\")
    }
    return $false
}

function Test-ValidHostnameOrIp {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
    $clean = $Target.Trim()

    # Disallow shell metacharacters for safety
    if ($clean -match '[;&|<>`$]') {
        return $false
    }

    # Check if string looks like an IPv4 quad (4 numeric parts)
    if ($clean -match '^\d+\.\d+\.\d+\.\d+$') {
        $ip = $null
        return [System.Net.IPAddress]::TryParse($clean, [ref]$ip)
    }

    # IPv6 check
    if ($clean -match ':') {
        $ip = $null
        return [System.Net.IPAddress]::TryParse($clean, [ref]$ip)
    }

    # Hostname check: TLD cannot be all digits, label lengths <= 63, total length <= 253
    if ($clean.Length -le 253 -and $clean -match '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$') {
        return $true
    }

    # Single-label local hostname (e.g. "localhost", "server01")
    if ($clean -match '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$') {
        return $true
    }

    return $false
}

function Sanitize-CliString {
    param([string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) { return "" }
    # Strip dangerous characters that could cause injection in sub-shells
    return ($InputText -replace '[;&|<>`$]', '')
}
