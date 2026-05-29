# ==============================================================================
# arjo-tools — Root Menu Script
# Usage  : iex (Invoke-WebRequest "https://raw.githubusercontent.com/.../main.ps1" -UseBasicParsing).Content
# Purpose: Interactive menu that fetches and runs component scripts on demand.
#          Scripts are loaded lazily — only downloaded when the user selects them.
# ==============================================================================

# ------------------------------------------------------------------------------
# Shared logging function — used throughout this script and passed to components
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
# Base URL for all component scripts in the repo
# ------------------------------------------------------------------------------
$repo = "https://raw.githubusercontent.com/archways404/arjo-tools/master"

# ------------------------------------------------------------------------------
# Menu definition — add new entries here as you add scripts to the repo.
# Each entry needs:
#   Label       : Display name shown in the menu
#   Description : One-line explanation shown next to the number
#   Url         : Full raw URL to the script (relative to $repo or absolute)
# ------------------------------------------------------------------------------
$menuItems = @(
    @{
        Label       = "Add Printers"
        Description = "Installs and configures network printers"
        Url         = "$repo/components/printers.ps1"
        EntryPoint  = "Add-Printers"   # Function to call after loading (leave empty for run-on-load scripts)
    },
    @{
        Label       = "Set Power Settings"
        Description = "Applies standard power profile settings"
        Url         = "$repo/components/power.ps1"
        EntryPoint  = "Set-PowerSettings"
    },
    @{
        Label       = "Fix Teams Add-in (Outlook Classic) - Disabled"
        Description = "Re-enables the Teams Meeting add-in when inactive or crash-disabled"
        Url         = "$repo/outlook-classic/ms_outlook16classic_teams_addin.ps1"
        EntryPoint  = ""   # This script runs immediately on load, no separate entry point needed
    },
    @{
        Label       = "Lenovo System Updates (IN BETA)"
        Description = "Scans and installs Lenovo driver and firmware updates (runs as admin)"
        Url         = "$repo/components/lenovo-updates.ps1"
        EntryPoint  = "Start-LenovoUpdates"
    },
    @{
        Label       = "View Lenovo Update Logs (IN BETA)"
        Description = "Lists and displays logs from previous update runs"
        Url         = "$repo/components/view-logs.ps1"
        EntryPoint  = "Show-LenovoLogs"
    },
    @{
        Label       = "View local admins (IN BETA)"
        Description = "Lists and displays local admins for a domain"
        Url         = "$repo/components/list-local-admin-for-site.ps1"
        EntryPoint  = "Show-GroupMenu"
    }
    @{
        Label       = "Nils & Kobby Net-User script"
        Description = "Look up AD user details and group memberships"
        Url         = "$repo/components/nk-net-user-lookup.ps1"
        EntryPoint  = "Start-UserLookup"
    },
    @{
        Label       = "Get PC Info"
        Description = "Displays local PC hardware and OS details"
        Url         = "$repo/components/get-pc-info.ps1"
        EntryPoint  = "Get-PCInfo"
    }
)

# ------------------------------------------------------------------------------
# Helper — fetch and execute a script by URL
# If the script exposes a named function (EntryPoint), call that after loading.
# If EntryPoint is empty, the script runs its own logic on load via iex.
# ------------------------------------------------------------------------------
function Invoke-RemoteScript {
    param (
        [string]$Url,
        [string]$EntryPoint
    )

    Log -Level INFO -Message "Fetching script from: $Url"

    try {
        $content = (Invoke-WebRequest $Url -UseBasicParsing -ErrorAction Stop).Content

        # Strip BOM — UTF-8 BOM is EF BB BF which becomes the unicode char FEFF
        if ($content.Length -gt 0 -and [int][char]$content[0] -eq 0xFEFF) {
            $content = $content.Substring(1)
        }
        # Also handle if it starts with literal "ï»¿" (mojibake BOM)
        if ($content.StartsWith("ï»¿")) {
            $content = $content.Substring(3)
        }
    } catch {
        Log -Level ERROR -Message "Failed to download script: $_"
        return
    }

    Log -Level INFO -Message "Running script..."

    try {
        iex $content

        # If the script defines a function rather than running inline, call it now
        if ($EntryPoint -ne "") {
            & $EntryPoint
        }
    } catch {
        Log -Level ERROR -Message "Script execution failed: $_"
        return
    }

    Log -Level SUCCESS -Message "Script completed."
}

# ------------------------------------------------------------------------------
# Main menu loop — keeps running until the user chooses to exit
# ------------------------------------------------------------------------------
while ($true) {
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "         arjo-tools  |  Main Menu      " -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""

    # Print each menu item with its number
    for ($i = 0; $i -lt $menuItems.Count; $i++) {
        $num  = $i + 1
        $item = $menuItems[$i]
        Write-Host ("  [{0}] {1,-38} {2}" -f $num, $item.Label, $item.Description) -ForegroundColor White
    }

    Write-Host ""
    Write-Host "  [0] Exit" -ForegroundColor DarkGray
    Write-Host ""

    $input = Read-Host "  Enter your choice"

    # Validate input is a number
    if ($input -notmatch '^\d+$') {
        Log -Level WARN -Message "Invalid input. Please enter a number."
        continue
    }

    $choice = [int]$input

    # Exit
    if ($choice -eq 0) {
        Write-Host ""
        Log -Level INFO -Message "Exiting. Goodbye!"
        Write-Host ""
        break
    }

    # Valid menu item
    if ($choice -ge 1 -and $choice -le $menuItems.Count) {
        $selected = $menuItems[$choice - 1]
        Write-Host ""
        Log -Level HEADER -Message $selected.Label
        Invoke-RemoteScript -Url $selected.Url -EntryPoint $selected.EntryPoint

        # Pause before redrawing the menu so the user can read the output
        Write-Host ""
        Write-Host "  Press any key to return to the menu..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Log -Level WARN -Message "Choice out of range. Please enter a number between 0 and $($menuItems.Count)."
    }
}
