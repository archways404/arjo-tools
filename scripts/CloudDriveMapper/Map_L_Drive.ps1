# Map_L_Drive.ps1
# Waits for target R: path to become available, then creates a persistent subst-style mapping.
# Logs all actions to a log file for troubleshooting.

$TargetPath    = "R:\NLTIE - Customer Sales - Documenten"
$MapLetter     = "L:"
$MaxRetries    = 30
$RetryDelaySec = 10

# --- Logging setup ---
$LogFolder  = "C:\Scripts\Logs"
$LogFile    = Join-Path $LogFolder "Map_L_Drive.log"

if (-not (Test-Path -LiteralPath $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -LiteralPath $LogFile -Value $line
    Write-Output $line
}

# Optional: keep the log from growing forever (trim if over ~5MB)
try {
    if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 5MB)) {
        $archiveName = Join-Path $LogFolder ("Map_L_Drive_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Rename-Item -LiteralPath $LogFile -NewName $archiveName
    }
} catch {
    # non-fatal, just continue without rotation if this fails
}

Write-Log "=== Script started (User: $env:USERNAME, Computer: $env:COMPUTERNAME) ==="
Write-Log "Target path: '$TargetPath' | Map letter: $MapLetter"

$count = 0
$found = $false

while ($count -lt $MaxRetries) {
    if (Test-Path -LiteralPath $TargetPath) {
        $found = $true
        break
    }
    $count++
    Write-Log "Waiting for '$TargetPath' to become available... attempt $count/$MaxRetries" "WARN"
    Start-Sleep -Seconds $RetryDelaySec
}

if (-not $found) {
    Write-Log "Target path not accessible after $MaxRetries attempts. Exiting." "ERROR"
    Write-Log "=== Script finished with failure ==="
    exit 1
}

Write-Log "Target path confirmed accessible after $count attempt(s)."

# Remove any existing mapping for the drive letter first (ignore errors if none exists)
try {
    $removeOutput = & subst $MapLetter /d 2>&1
    Write-Log "Attempted to remove existing mapping for $MapLetter (output: $removeOutput)"
} catch {
    Write-Log "No existing mapping to remove for $MapLetter (or removal failed harmlessly): $_" "WARN"
}

# Create the subst mapping
$substOutput = & subst $MapLetter "$TargetPath" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Log "Successfully mapped $MapLetter to '$TargetPath'"
    Write-Log "=== Script finished successfully ==="
    exit 0
} else {
    Write-Log "Failed to map $MapLetter. subst output: $substOutput" "ERROR"
    Write-Log "=== Script finished with failure ==="
    exit 1
}
