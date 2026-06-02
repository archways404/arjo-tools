# ==============================================================================
# arjo-tools — Install26 Pipeline
# Usage  : iex (Invoke-WebRequest "https://raw.githubusercontent.com/archways404/arjo-tools/master/pipelines/install26/setup.ps1" -UseBasicParsing).Content
# Purpose: Automated setup pipeline — runs all install26 components sequentially.
# ==============================================================================

# ------------------------------------------------------------------------------
# Shared logging function
# ------------------------------------------------------------------------------
function Log {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "HEADER")]
        [string]$Level,
        [Parameter(Mandatory)]
        [string]$Message
    )
    switch ($Level) {
        "INFO"    { $color = "Cyan";    $prefix = "[INFO]    " }
        "SUCCESS" { $color = "Green";   $prefix = "[SUCCESS] " }
        "WARN"    { $color = "Yellow";  $prefix = "[WARN]    " }
        "ERROR"   { $color = "Red";     $prefix = "[ERROR]   " }
        "HEADER"  { $color = "Magenta"; Write-Host "`n==== $Message ====" -ForegroundColor $color; return }
    }
    Write-Host "$prefix$Message" -ForegroundColor $color
}

# ------------------------------------------------------------------------------
# Base URL for pipeline components
# ------------------------------------------------------------------------------
$repo = "https://raw.githubusercontent.com/archways404/arjo-tools/master/pipelines/install26/components"

# ------------------------------------------------------------------------------
# Helper — fetch, load and invoke a component script
# ------------------------------------------------------------------------------
function Invoke-PipelineScript {
    param (
        [string]$Url,
        [string]$EntryPoint
    )

    Log -Level INFO -Message "Fetching: $Url"

    try {
        $content = (Invoke-WebRequest $Url -UseBasicParsing -ErrorAction Stop).Content

        # Strip BOM
        if ($content.Length -gt 0 -and [int][char]$content[0] -eq 0xFEFF) {
            $content = $content.Substring(1)
        }
        if ($content.StartsWith("ï»¿")) {
            $content = $content.Substring(3)
        }
    } catch {
        Log -Level ERROR -Message "Failed to download ${Url}: $_"
        return
    }

    try {
        iex $content
        if ($EntryPoint -ne "") {
            & $EntryPoint
        }
    } catch {
        Log -Level ERROR -Message "Failed to run ${EntryPoint}: $_"
    }
}

# ------------------------------------------------------------------------------
# Pipeline banner
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "     arjo-tools  |  Install26 Setup    " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Log -Level INFO -Message "Starting automated setup pipeline..."
Write-Host ""

# ------------------------------------------------------------------------------
# Pipeline steps — runs sequentially top to bottom
# ------------------------------------------------------------------------------
$steps = @(
    @{ Label = "Power Settings";     Url = "$repo/power.ps1";   EntryPoint = "Set-PowerSettings" },
    @{ Label = "Microsoft Teams";    Url = "$repo/teams.ps1";   EntryPoint = "Install-MicrosoftTeams" },
    @{ Label = "Lenovo Drivers";     Url = "$repo/drivers.ps1"; EntryPoint = "Start-LenovoUpdates" },
    @{ Label = "PC Metrics";         Url = "$repo/metrics.ps1"; EntryPoint = "Send-PCInfo" }
)

$total   = $steps.Count
$current = 0

foreach ($step in $steps) {
    $current++
    Write-Host ""
    Write-Host "  [$current/$total] $($step.Label)" -ForegroundColor Cyan
    Write-Host ""
    Invoke-PipelineScript -Url $step.Url -EntryPoint $step.EntryPoint
}

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "=======================================" -ForegroundColor Green
Write-Host "        Install26 Pipeline Complete     " -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green
Write-Host ""
Log -Level SUCCESS -Message "All steps completed. Machine is ready."
Write-Host ""
