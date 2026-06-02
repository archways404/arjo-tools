# ==============================================================================
# Lenovo System Updates — LSUClient
# Best practices: download-before-install, transcript logging, admin elevation
# ==============================================================================

# Fallback logger in case this script is ever run standalone (outside the menu)
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param (
            [ValidateSet("INFO","SUCCESS","WARN","ERROR","HEADER")][string]$Level,
            [string]$Message
        )
        $map = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; HEADER="Magenta" }
        if ($Level -eq "HEADER") { Write-Host "`n==== $Message ====" -ForegroundColor $map[$Level]; return }
        $prefix = "[$(($Level).PadRight(7))]"
        Write-Host "$prefix $Message" -ForegroundColor $map[$Level]
    }
}

function Start-LenovoUpdates {

    # ------------------------------------------------------------------
    # Admin check — relaunch elevated if needed
    # ------------------------------------------------------------------
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Log -Level WARN -Message "Not running as Administrator. Relaunching elevated..."
        $scriptUrl = "https://raw.githubusercontent.com/archways404/arjo-tools/master/components/lenovo-updates.ps1"
        $cmd = "iex (Invoke-WebRequest '$scriptUrl' -UseBasicParsing).Content; Start-LenovoUpdates"
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs
        Log -Level INFO -Message "Elevated window launched. You can close this one."
        return
    }

    # ------------------------------------------------------------------
    # Start transcript
    # ------------------------------------------------------------------
    $logPath = "$env:TEMP\lsuclient_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Start-Transcript -LiteralPath $logPath
    Log -Level INFO -Message "Transcript: $logPath"

    # ------------------------------------------------------------------
    # Install LSUClient
    # ------------------------------------------------------------------
    Log -Level INFO -Message "Trusting PSGallery and installing LSUClient..."
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name LSUClient -Force
    Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted
    Log -Level SUCCESS -Message "LSUClient ready."

    # ------------------------------------------------------------------
    # Update loop — up to 5 rounds
    # Some updates unlock further updates after a reboot, hence the loop.
    # ------------------------------------------------------------------
    $MaxRounds = 5

    for ($Round = 1; $Round -le $MaxRounds; $Round++) {
        Log -Level HEADER -Message "Round $Round of $MaxRounds"

        $updates = Get-LSUpdate -Verbose
        Log -Level INFO -Message "$($updates.Count) update(s) found."

        if ($updates.Count -eq 0) {
            Log -Level SUCCESS -Message "Nothing left to install."
            break
        }

        # Download everything first — prevents NIC driver installs from
        # cutting off subsequent downloads mid-run.
        Log -Level INFO -Message "Downloading all packages before installing..."
        $updates | Save-LSUpdate
        Log -Level SUCCESS -Message "All packages downloaded."

        # Install one by one so progress is visible in the log
        $i = 1
        foreach ($update in $updates) {
            Log -Level INFO -Message "[$i/$($updates.Count)] $($update.Title)"
            Install-LSUpdate -Package $update -Verbose
            $i++
        }
    }

    # ------------------------------------------------------------------
       # Cleanup — remove LSUClient after use
       # ------------------------------------------------------------------
       Log -Level INFO -Message "Removing LSUClient..."
       Remove-Module -Name LSUClient -Force -ErrorAction SilentlyContinue
       Uninstall-Module -Name LSUClient -AllVersions -Force
       Log -Level SUCCESS -Message "LSUClient removed."

       # ------------------------------------------------------------------
       Stop-Transcript
       Log -Level SUCCESS -Message "Done. Log saved to: $logPath"
}

# Entry point
if ($MyInvocation.InvocationName -ne '.') {
    Start-LenovoUpdates
}
