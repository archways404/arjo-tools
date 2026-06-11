# ==============================================================================
# arjo-tools — Install26 Pipeline
# ==============================================================================

$StatusApiUrl = "https://arjo-metrics.k14net.org/install-status"
$repo = "https://raw.githubusercontent.com/archways404/arjo-tools/master/pipelines/install26/components"

$UdpLogHost = "arjo-metrics.k14net.org"
$UdpLogPort = 9999

$script:UdpClient = $null

function Log {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "HEADER")]
        [string]$Level,
        [Parameter(Mandatory)]
        [string]$Message
    )

    Send-UdpLog -Message "[$Level] $Message"

    switch ($Level) {
        "INFO"    { $color = "Cyan";    $prefix = "[INFO]    " }
        "SUCCESS" { $color = "Green";   $prefix = "[SUCCESS] " }
        "WARN"    { $color = "Yellow";  $prefix = "[WARN]    " }
        "ERROR"   { $color = "Red";     $prefix = "[ERROR]   " }
        "HEADER"  { Write-Host "`n==== $Message ====" -ForegroundColor Magenta; return }
    }

    Write-Host "$prefix$Message" -ForegroundColor $color
}

function Send-UdpLines {
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines,
        [string]$Level = "INFO"
    )
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        Send-UdpLog -Message "[$Level] $line"
    }
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Script,
        [string]$Level = "INFO"
    )

    try {
        $output = & $Script *>&1
        foreach ($line in $output) {
            $text = $line.ToString()
            Send-UdpLog -Message "[$Level] $text"
            Write-Host $text
        }
        return $output
    } catch {
        Send-UdpLog -Message "[ERROR] $($_.Exception.Message)"
        throw
    }
}

function Init-UdpLogger {
    try {
        $script:UdpClient = New-Object System.Net.Sockets.UdpClient
        $script:UdpClient.Connect($UdpLogHost, $UdpLogPort)
    } catch {
        # silent — UDP logging is best-effort
    }
}

function Send-UdpLog {
    param([string]$Message)
    try {
        if (-not $script:UdpClient) { return }
        $line = "$($env:COMPUTERNAME) | $(Get-Date -Format 'HH:mm:ss') | $Message"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
        $script:UdpClient.Send($bytes, $bytes.Length) | Out-Null
    } catch {}
}

function Close-UdpLogger {
    try {
        if ($script:UdpClient) {
            $script:UdpClient.Close()
            $script:UdpClient = $null
        }
    } catch {}
}

function Get-SerialNumber {
    try { return (Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber }
    catch { return $null }
}

function Send-PipelineStatus {
    param(
        [string]$Stage,
        [string]$Status,
        [string]$Message,
        [string]$CurrentStep,
        [int]$CompletedSteps = 0,
        [int]$TotalSteps = 0,
        [hashtable]$Extra = @{}
    )

    $extraPayload = @{
        Pipeline = "install26"
    }
    foreach ($key in $Extra.Keys) {
        $extraPayload[$key] = $Extra[$key]
    }

    try {
        $body = @{
            PCName         = $env:COMPUTERNAME
            Serial         = Get-SerialNumber
            Stage          = $Stage
            Status         = $Status
            Message        = $Message
            CurrentStep    = $CurrentStep
            CompletedSteps = $CompletedSteps
            TotalSteps     = $TotalSteps
            Timestamp      = (Get-Date).ToString("o")
            Extra          = $extraPayload
        } | ConvertTo-Json -Depth 10 -Compress

        Invoke-RestMethod `
            -Uri $StatusApiUrl `
            -Method POST `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 5 `
            -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

function Invoke-PipelineScript {
    param (
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$EntryPoint
    )

    Log -Level INFO -Message "Fetching: $Url"

    try {
        $content = (Invoke-WebRequest $Url -UseBasicParsing -ErrorAction Stop).Content

        if ($content.Length -gt 0 -and [int][char]$content[0] -eq 0xFEFF) {
            $content = $content.Substring(1)
        }

        if ($content.StartsWith("ï»¿")) {
            $content = $content.Substring(3)
        }
    } catch {
        Log -Level ERROR -Message "Failed to download ${Url}: $_"
        throw
    }

    try {
        iex $content

        if ($EntryPoint -ne "") {
            Log -Level INFO -Message "Running entry point: $EntryPoint"
            & $EntryPoint
            Log -Level SUCCESS -Message "Finished entry point: $EntryPoint"
        }
    } catch {
        Log -Level ERROR -Message "Failed to run ${EntryPoint}: $_"
        throw
    }
}

Init-UdpLogger

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "     arjo-tools  |  Install26 Setup    " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

$steps = @(
    @{ Label = "Power Settings";  Stage = "power";   Url = "$repo/power.ps1";   EntryPoint = "Set-PowerSettings" },
    @{ Label = "Microsoft Teams"; Stage = "teams";   Url = "$repo/teams.ps1";   EntryPoint = "Install-MicrosoftTeams" },
    @{ Label = "PC Metrics";      Stage = "metrics"; Url = "$repo/metrics.ps1"; EntryPoint = "Send-PCInfo" },
    @{ Label = "Lenovo Drivers";  Stage = "lenovo";  Url = "$repo/drivers.ps1"; EntryPoint = "Start-LenovoUpdates" }
)

$total = $steps.Count
$current = 0

foreach ($step in $steps) {
    $current++

    Write-Host ""
    Write-Host "  [$current/$total] $($step.Label)" -ForegroundColor Cyan
    Write-Host ""

    Send-PipelineStatus `
        -Stage $step.Stage `
        -Status "running" `
        -Message "Running $($step.Label)" `
        -CurrentStep $step.Label `
        -CompletedSteps ($current - 1) `
        -TotalSteps $total

        try {
            Invoke-PipelineScript -Url $step.Url -EntryPoint $step.EntryPoint
            if ($step.Stage -ne "lenovo") {
                Send-PipelineStatus `
                    -Stage $step.Stage `
                    -Status "completed" `
                    -Message "Completed $($step.Label)" `
                    -CurrentStep $step.Label `
                    -CompletedSteps $current `
                    -TotalSteps $total
            } else {
                Log -Level INFO -Message "Lenovo status is handled by drivers.ps1. Skipping pipeline completion overwrite."
            }
        } catch {
        Send-PipelineStatus `
            -Stage $step.Stage `
            -Status "failed" `
            -Message "Failed $($step.Label): $($_.Exception.Message)" `
            -CurrentStep $step.Label `
            -CompletedSteps ($current - 1) `
            -TotalSteps $total `
            -Extra @{ Error = $_.Exception.Message }

        throw
    }
}

Log -Level SUCCESS -Message "Pipeline completed. Lenovo task may continue after reboot."

Close-UdpLogger
