function Log {
  param (
    [Parameter(Mandatory)]
    [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "HEADER")]
    [string]$Level,

    [Parameter(Mandatory)]
    [string]$Message
  )

  switch ($Level) {
    "INFO"    { $color = "Cyan";     $prefix = "[INFO]    " }
    "SUCCESS" { $color = "Green";    $prefix = "[SUCCESS] " }
    "WARN"    { $color = "Yellow";   $prefix = "[WARN]    " }
    "ERROR"   { $color = "Red";      $prefix = "[ERROR]   " }
    "HEADER"  { $color = "Magenta";  $prefix = "`n==== $Message ===="; Write-Host $prefix -ForegroundColor $color; return }
  }

  Write-Host "$prefix$Message" -ForegroundColor $color
}

# --- Load other scripts remotely
$repo = "https://raw.githubusercontent.com/archways404/arjo-tools/master/components"

try {
  iex (Invoke-WebRequest "$repo/printers.ps1" -UseBasicParsing).Content
  iex (Invoke-WebRequest "$repo/power.ps1" -UseBasicParsing).Content
} catch {
  Log -Level ERROR -Message "Failed to download one or more required scripts."
  exit 1
}

Log -Level HEADER -Message "System Setup"

Add-Printers
Set-PowerSettings

Log -Level SUCCESS -Message "All tasks completed successfully"