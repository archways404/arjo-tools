# VXL2 Install Script
# PER USER ONLY

# Fallback Log if running standalone
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param([string]$Level, [string]$Message)
        $colors = @{ "HEADER" = "Magenta"; "INFO" = "Cyan"; "SUCCESS" = "Green"; "WARN" = "Yellow"; "ERROR" = "Red" }
        $color = if ($colors.ContainsKey($Level)) { $colors[$Level] } else { "White" }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

function Install-VXL2 {
    Log -Level HEADER -Message "Install VXL2"

    # Check if already installed
    if (Get-Process -Name "VXL2" -ErrorAction SilentlyContinue) {
        Log -Level INFO -Message "VXL2 is already running, skipping."
        return
    }

    # Add trusted site
    $zonePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\vincesoftware.org\vpm2"
    New-Item -Path $zonePath -Force | Out-Null
    Set-ItemProperty -Path $zonePath -Name "https" -Value 2 -Type DWord

    Log -Level INFO -Message "Launching VXL2 installer..."
    Start-Process "rundll32.exe" -ArgumentList "dfshim.dll,ShOpenVerbApplication https://vpm2.vincesoftware.org/VXLApplication/VXL2.application"

    # Wait for dialog to appear
    Start-Sleep -Seconds 5

    # Press left arrow then Enter to click Install
    $wshell = New-Object -ComObject wscript.shell
    $wshell.SendKeys("{LEFT}~")

    # Wait for VXL2 to launch (means install is done)
    Log -Level INFO -Message "Waiting for VXL2 to finish installing..."
    $timeout = 60
    $elapsed = 0
    while (-not (Get-Process -Name "VXL2" -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        if ($elapsed -ge $timeout) {
            Log -Level WARN -Message "VXL2 did not launch within timeout."
            break
        }
    }

    # Kill VXL2 after install
    $proc = Get-Process -Name "VXL2" -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Name "VXL2" -Force
        Log -Level SUCCESS -Message "VXL2 installed and closed successfully."
    }

    # Remove trusted site after
    Remove-Item -Path $zonePath -Force -ErrorAction SilentlyContinue
}

# Auto-run if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Install-VXL2
}
