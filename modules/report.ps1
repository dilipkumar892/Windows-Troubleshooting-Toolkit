<#
.SYNOPSIS
    HTML and JSON Diagnostic Report Generator for Windows Troubleshooting Toolkit.
.DESCRIPTION
    Compiles full-system telemetry into a responsive, executive-ready HTML dashboard
    with status badges, metrics cards, and structured JSON export.
#>

function Invoke-GenerateDiagnosticReport {
    [CmdletBinding()]
    param()

    Show-SectionHeader -Title "GENERATE COMPREHENSIVE DIAGNOSTIC REPORT" -Subtitle "Compiles complete system telemetry into an interactive HTML dashboard"

    $baseDir = Split-Path -Parent $PSScriptRoot
    $reportsDir = Join-Path $baseDir "reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }

    Write-Host " [1/6] Gathering system and OS metrics..." -ForegroundColor Cyan
    $sys = Get-SystemInformationReport

    Write-Host " [2/6] Gathering storage and volume status..." -ForegroundColor Cyan
    $disk = Get-DiskDiagnosticsData

    Write-Host " [3/6] Gathering network and connectivity..." -ForegroundColor Cyan
    $net = Get-NetworkDiagnosticsData

    Write-Host " [4/6] Gathering security and Defender status..." -ForegroundColor Cyan
    $sec = Get-SecurityDiagnosticsData

    Write-Host " [5/6] Gathering hardware and device manager logs..." -ForegroundColor Cyan
    $hw = Get-HardwareDiagnosticsData

    Write-Host " [6/6] Gathering Windows Update service status..." -ForegroundColor Cyan
    $wu = Get-WindowsUpdateHealthReport

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $htmlPath = Join-Path $reportsDir "diagnostic_report_$timestamp.html"
    $jsonPath = Join-Path $reportsDir "diagnostic_report_$timestamp.json"

    # Export JSON
    $fullData = [PSCustomObject]@{
        ReportGeneratedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
        System = $sys
        Storage = $disk
        Network = $net
        Security = $sec
        Hardware = $hw
        WindowsUpdate = $wu
    }
    $fullData | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding UTF8

    # Format dynamic HTML rows before string interpolation
    $volumeRows = if ($disk.Volumes) {
        ($disk.Volumes | ForEach-Object {
            "<tr><td>$($_.DriveLetter)</td><td>$($_.FileSystemLabel)</td><td>$($_.FreeSpace)</td><td><span class='badge $(if ($_.IsLowSpace) { 'badge-danger' } else { 'badge-success' })'>$($_.PercentFree)%</span></td></tr>"
        }) -join "`n"
    } else {
        "<tr><td colspan='4'>No volume data available</td></tr>"
    }

    $problemDeviceRows = ""
    if ($hw.ProblemDevices -and @($hw.ProblemDevices).Count -gt 0) {
        $deviceItems = (@($hw.ProblemDevices) | ForEach-Object { "<tr><td>$($_.Name)</td><td>Code $($_.ErrorCode)</td></tr>" }) -join ""
        $problemDeviceRows = "<table><thead><tr><th>Device</th><th>Code</th></tr></thead><tbody>$deviceItems</tbody></table>"
    }

    $topProcessRows = if ($sys.TopCpuProcesses) {
        ($sys.TopCpuProcesses | ForEach-Object {
            "<tr><td><strong>$($_.ProcessName)</strong></td><td>$($_.Id)</td><td>$($_.CPU)</td><td>$($_.MemoryMB) MB</td></tr>"
        }) -join "`n"
    } else {
        "<tr><td colspan='4'>No process data available</td></tr>"
    }

    # Generate HTML Dashboard
    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows Diagnostics Report - $($sys.ComputerName)</title>
    <style>
        :root {
            --bg-primary: #0f172a;
            --bg-card: #1e293b;
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --accent: #38bdf8;
            --success: #22c55e;
            --warning: #eab308;
            --danger: #ef4444;
            --border: #334155;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            padding: 2rem;
            line-height: 1.5;
        }
        .header {
            border-bottom: 2px solid var(--border);
            padding-bottom: 1.5rem;
            margin-bottom: 2rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 1rem;
        }
        .title h1 { color: var(--accent); font-size: 1.8rem; }
        .meta { color: var(--text-secondary); font-size: 0.9rem; }
        .badge {
            display: inline-block;
            padding: 0.25rem 0.6rem;
            border-radius: 9999px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        .badge-success { background: rgba(34, 197, 94, 0.2); color: var(--success); border: 1px solid var(--success); }
        .badge-warning { background: rgba(234, 179, 8, 0.2); color: var(--warning); border: 1px solid var(--warning); }
        .badge-danger { background: rgba(239, 68, 68, 0.2); color: var(--danger); border: 1px solid var(--danger); }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        .card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 1.25rem;
        }
        .card h2 {
            font-size: 1.15rem;
            color: var(--accent);
            margin-bottom: 1rem;
            border-bottom: 1px solid var(--border);
            padding-bottom: 0.5rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .kv-row {
            display: flex;
            justify-content: space-between;
            padding: 0.4rem 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            font-size: 0.9rem;
        }
        .kv-label { color: var(--text-secondary); }
        .kv-val { font-weight: 500; text-align: right; }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 0.75rem;
            font-size: 0.85rem;
        }
        th, td {
            text-align: left;
            padding: 0.5rem;
            border-bottom: 1px solid var(--border);
        }
        th { color: var(--accent); }
        .footer {
            text-align: center;
            font-size: 0.8rem;
            color: var(--text-secondary);
            margin-top: 3rem;
            border-top: 1px solid var(--border);
            padding-top: 1rem;
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="title">
            <h1>Windows Advanced Troubleshooting Report</h1>
            <div class="meta">Target: <strong>$($sys.ComputerName)</strong> | Domain: $($sys.Domain)</div>
        </div>
        <div>
            <span class="badge $(if ($hw.ProblemDevices.Count -eq 0 -and $sec.Defender.RealTimeProtectionEnabled) { 'badge-success' } else { 'badge-warning' })">
                $(if ($hw.ProblemDevices.Count -eq 0) { 'HEALTHY' } else { 'ISSUES DETECTED' })
            </span>
            <div class="meta" style="margin-top: 0.5rem;">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
        </div>
    </div>

    <div class="grid">
        <!-- System Info -->
        <div class="card">
            <h2>Operating System</h2>
            <div class="kv-row"><span class="kv-label">OS:</span><span class="kv-val">$($sys.OSName)</span></div>
            <div class="kv-row"><span class="kv-label">Build:</span><span class="kv-val">$($sys.OSBuild) ($($sys.OSArchitecture))</span></div>
            <div class="kv-row"><span class="kv-label">Uptime:</span><span class="kv-val">$($sys.UptimeFormatted)</span></div>
            <div class="kv-row"><span class="kv-label">Processor:</span><span class="kv-val">$($sys.ProcessorName)</span></div>
            <div class="kv-row"><span class="kv-label">Memory:</span><span class="kv-val">$($sys.UsedRAM) / $($sys.TotalRAM) ($($sys.RAMPercentUsed)%)</span></div>
        </div>

        <!-- Security -->
        <div class="card">
            <h2>Security Posture</h2>
            <div class="kv-row"><span class="kv-label">Real-Time Protection:</span><span class="kv-val $(if ($sec.Defender.RealTimeProtectionEnabled) { 'badge badge-success' } else { 'badge badge-danger' })">$(if ($sec.Defender.RealTimeProtectionEnabled) { 'Enabled' } else { 'Disabled' })</span></div>
            <div class="kv-row"><span class="kv-label">Antivirus Signatures:</span><span class="kv-val">$($sec.Defender.AntivirusSignatureVersion)</span></div>
            <div class="kv-row"><span class="kv-label">UAC Token Filter:</span><span class="kv-val $(if ($sec.UacEnabled) { 'badge badge-success' } else { 'badge badge-danger' })">$(if ($sec.UacEnabled) { 'Active' } else { 'Disabled' })</span></div>
            <div class="kv-row"><span class="kv-label">Firewall Profiles:</span><span class="kv-val">$(($sec.FirewallProfiles | Where-Object { $_.Enabled }).Count) of $($sec.FirewallProfiles.Count) Active</span></div>
        </div>

        <!-- Storage -->
        <div class="card">
            <h2>Storage Health</h2>
            <table>
                <thead><tr><th>Drive</th><th>Label</th><th>Free</th><th>% Free</th></tr></thead>
                <tbody>
$volumeRows
                </tbody>
            </table>
        </div>

        <!-- Problem Devices -->
        <div class="card">
            <h2>Hardware Devices</h2>
            <div class="kv-row"><span class="kv-label">Driver Errors:</span><span class="kv-val $(if ($hw.ProblemDevices.Count -eq 0) { 'badge badge-success' } else { 'badge badge-danger' })">$($hw.ProblemDevices.Count) Detected</span></div>
            $problemDeviceRows
        </div>
    </div>

    <!-- Processes -->
    <div class="card" style="margin-bottom: 2rem;">
        <h2>Top Processes by Resource Demand</h2>
        <table>
            <thead><tr><th>Process</th><th>PID</th><th>CPU Time (s)</th><th>Memory (MB)</th></tr></thead>
            <tbody>
$topProcessRows
            </tbody>
        </table>
    </div>

    <div class="footer">
        Generated by Windows Troubleshooting Toolkit v1.0.0 &bull; File: $htmlPath
    </div>
</body>
</html>
"@

    [System.IO.File]::WriteAllText($htmlPath, $htmlContent, [System.Text.Encoding]::UTF8)

    Write-Host ""
    Write-Host " [SUCCESS] Diagnostic reports successfully generated!" -ForegroundColor Green
    Write-Host "  HTML Dashboard : $htmlPath" -ForegroundColor White
    Write-Host "  Raw JSON Data  : $jsonPath" -ForegroundColor White
    Write-ToolkitLog -Message "Diagnostic report generated at $htmlPath and $jsonPath" -Level 'SUCCESS'

    Write-Host ""
    $open = Confirm-UserAction -PromptMessage " Open HTML Diagnostic Report in default browser?" -DefaultChoice "Y"
    if ($open) {
        Start-Process $htmlPath
    }

    Wait-ReturnToMenu
}

