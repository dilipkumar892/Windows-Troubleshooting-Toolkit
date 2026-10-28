<#
.SYNOPSIS
    Windows Security Diagnostics Module for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Audits Windows Defender real-time protection, signature freshness,
    Windows Firewall profile statuses, UAC settings, and BitLocker encryption.
    NEVER disables security components.
#>

function Get-SecurityDiagnosticsData {
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Auditing Windows security components..." -Level 'INFO'

    # Defender Status
    $defender = $null
    try {
        $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    } catch {
        Write-ToolkitLog -Message "Could not query Defender status: $($_.Exception.Message)" -Level 'DEBUG'
    }

    # Firewall Profiles
    $firewallProfiles = @()
    try {
        $profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        foreach ($p in $profiles) {
            $firewallProfiles += [PSCustomObject]@{
                Name            = $p.Name
                Enabled         = $p.Enabled
                DefaultInbound  = $p.DefaultInboundAction
                DefaultOutbound = $p.DefaultOutboundAction
            }
        }
    } catch {
        Write-ToolkitLog -Message "Could not query firewall profiles: $($_.Exception.Message)" -Level 'DEBUG'
    }

    # UAC Status
    $uacKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $enableLua = 1
    $consentAdmin = 5
    if (Test-Path $uacKey) {
        $props = Get-ItemProperty -Path $uacKey -ErrorAction SilentlyContinue
        if ($props.EnableLUA -ne $null) { $enableLua = $props.EnableLUA }
        if ($props.ConsentPromptBehaviorAdmin -ne $null) { $consentAdmin = $props.ConsentPromptBehaviorAdmin }
    }

    # BitLocker status
    $bitlocker = @()
    try {
        $blVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
        foreach ($bv in $blVolumes) {
            $bitlocker += [PSCustomObject]@{
                MountPoint       = $bv.MountPoint
                VolumeStatus     = $bv.VolumeStatus
                ProtectionStatus = $bv.ProtectionStatus
                EncryptionMethod = $bv.EncryptionMethod
            }
        }
    } catch {
        # BitLocker cmdlets may not be present on Windows Home editions
    }

    return [PSCustomObject]@{
        Defender         = $defender
        FirewallProfiles = $firewallProfiles
        UacEnabled       = ($enableLua -eq 1)
        UacPromptLevel   = $consentAdmin
        BitLocker        = $bitlocker
    }
}

function Invoke-SecurityDiagnostics {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "WINDOWS SECURITY & DEFENDER DIAGNOSTICS" -Subtitle "Inspect Antivirus, Firewall profiles, UAC policies, and BitLocker"

    $sec = Get-SecurityDiagnosticsData

    Write-Host " [MICROSOFT DEFENDER ANTIVIRUS]" -ForegroundColor Yellow
    if ($sec.Defender) {
        $rtColor = if ($sec.Defender.RealTimeProtectionEnabled) { "Green" } else { "Red" }
        Write-Host ("  Real-Time Protection : {0}" -f (if ($sec.Defender.RealTimeProtectionEnabled) { "[ENABLED]" } else { "[DISABLED / WARNING]" })) -ForegroundColor $rtColor
        Write-Host ("  Antivirus Engine     : {0}" -f $sec.Defender.AMEngineVersion) -ForegroundColor White
        Write-Host ("  Antivirus Signatures : v{0} (Age: {1} days)" -f $sec.Defender.AntivirusSignatureVersion, $sec.Defender.AntivirusSignatureAge) -ForegroundColor White
        Write-Host ("  Last Full Scan       : {0}" -f (if ($sec.Defender.FullScanEndTime) { $sec.Defender.FullScanEndTime } else { "Never / Not recorded" })) -ForegroundColor DarkGray
        Write-Host ("  Last Quick Scan      : {0}" -f (if ($sec.Defender.QuickScanEndTime) { $sec.Defender.QuickScanEndTime } else { "Never / Not recorded" })) -ForegroundColor DarkGray

        if ($sec.Defender.AntivirusSignatureAge -gt 7) {
            Write-Host "  [!] Security definitions are over 7 days old. Consider triggering a signature update." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Microsoft Defender is inactive or managed by a 3rd party antivirus suite." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host " [WINDOWS ADVANCED FIREWALL PROFILES]" -ForegroundColor Yellow
    if ($sec.FirewallProfiles.Count -gt 0) {
        foreach ($p in $sec.FirewallProfiles) {
            $fColor = if ($p.Enabled) { "Green" } else { "Red" }
            $statusText = if ($p.Enabled) { "ACTIVE (Blocking Inbound)" } else { "DISABLED / INACTIVE" }
            Write-Host ("  Profile {0,-10} : {1}" -f $p.Name, $statusText) -ForegroundColor $fColor
        }
    } else {
        Write-Host "  Unable to query Windows Firewall profile status." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host " [USER ACCOUNT CONTROL (UAC)]" -ForegroundColor Yellow
    $uacColor = if ($sec.UacEnabled) { "Green" } else { "Red" }
    Write-Host ("  UAC Status : {0}" -f (if ($sec.UacEnabled) { "[ENABLED] Protected against unauthorized token elevation" } else { "[DISABLED] Warning: Applications run without elevation prompts" })) -ForegroundColor $uacColor

    if ($sec.BitLocker.Count -gt 0) {
        Write-Host ""
        Write-Host " [BITLOCKER DRIVE ENCRYPTION]" -ForegroundColor Yellow
        foreach ($bl in $sec.BitLocker) {
            $blColor = if ($bl.ProtectionStatus -eq 'On') { "Green" } else { "Yellow" }
            Write-Host ("  Drive {0,-3} Status: {1,-10} Protection: {2}" -f $bl.MountPoint, $bl.VolumeStatus, $bl.ProtectionStatus) -ForegroundColor $blColor
        }
    }

    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "  [1] Update Microsoft Defender Signatures (Update-MpSignature)" -ForegroundColor White
    Write-Host "  [2] Run Quick Defender Antivirus Scan (Start-MpScan)" -ForegroundColor White
    Write-Host "  [3] Open Windows Security Center (windowsdefender:)" -ForegroundColor White
    Write-Host "  [4] Return to Main Menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Get-ValidatedMenuChoice -Prompt "Select action [1-4]: " -Min 1 -Max 4

    switch ($choice) {
        "1" { Invoke-UpdateDefenderSignatures }
        "2" { Invoke-QuickDefenderScan }
        "3" {
            Start-Process "windowsdefender:" -ErrorAction SilentlyContinue
            Write-Host "Opened Windows Security Center." -ForegroundColor Green
            Wait-ReturnToMenu
        }
        "4" { return }
    }
}

function Invoke-UpdateDefenderSignatures {
    [CmdletBinding()]
    param()

    $title = "Update Defender Antivirus Signatures"
    $desc = "Executes Update-MpSignature to download the latest security intelligence definitions."
    $consequences = "Safe operation. Connects to Microsoft servers to install updated threat signatures."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -Action {
        Write-Host " Downloading and installing updated definition signatures..." -ForegroundColor Cyan
        Update-MpSignature -UpdateSource MicrosoftUpdateServer -ErrorAction Stop
        Write-Host " Signatures updated successfully." -ForegroundColor Green
        return 0
    }

    Wait-ReturnToMenu
}

function Invoke-QuickDefenderScan {
    [CmdletBinding()]
    param()

    $title = "Quick Microsoft Defender Malware Scan"
    $desc = "Executes Start-MpScan -ScanType QuickScan to check system memory and critical startup directories."
    $consequences = "Read-only inspection of high-risk operating system locations. Mild CPU usage during scan."

    $result = Invoke-SafeRepairOperation -Title $title -Description $desc -Consequences $consequences -RequiresAdmin $true -Action {
        Write-Host " Initiating Quick Scan in the background..." -ForegroundColor Cyan
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Write-Host " Quick scan initiated. View active scan progress in Windows Security Center." -ForegroundColor Green
        return 0
    }

    Wait-ReturnToMenu
}

