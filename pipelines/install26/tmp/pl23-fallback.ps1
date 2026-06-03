# Fallback Log if running standalone
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param([string]$Level, [string]$Message)
        $colors = @{ "HEADER" = "Magenta"; "INFO" = "Cyan"; "SUCCESS" = "Green"; "WARN" = "Yellow"; "ERROR" = "Red" }
        $color = if ($colors.ContainsKey($Level)) { $colors[$Level] } else { "White" }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

function Install-PL23Driver {
    Log -Level HEADER -Message "Install Prolific PL23XX USB-to-Serial Driver"

    $src = "C:\install-2026\PL23\PL23XX-M_LogoDriver_Setup_4300_20240704.exe"

    # Check if already installed
    $existing = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like "*Prolific*" }
    if ($existing) {
        Log -Level INFO -Message "Prolific driver already installed, skipping."
        return
    }

    try {
        Log -Level INFO -Message "Unblocking file..."
        Unblock-File $src

        Log -Level INFO -Message "Installing driver silently..."
        Start-Process $src -ArgumentList "/S" -Wait

        Log -Level SUCCESS -Message "Prolific PL23XX driver installed successfully."
    } catch {
        Log -Level ERROR -Message "Failed to install PL23XX driver: $_"
    }
}

# Auto-run if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Install-PL23Driver
}
