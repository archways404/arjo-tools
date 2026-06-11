function Get-PCInfo {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $bb   = Get-CimInstance Win32_BaseBoard

    $mac = (Get-NetAdapter -Physical | Where-Object {
        $_.Status -eq "Up" -and
        $_.Name -notlike "Wi-Fi*" -and
        $_.Name -notlike "Bluetooth*" -and
        $_.Name -like "Ethernet*"
    } | Select-Object -First 1).MacAddress -replace '-', ':'

    $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    $sku = $cs.SystemSKUNumber -replace '^.*FM_', ''

    return [PSCustomObject]@{
        PCName       = $cs.Name
        Manufacturer = $cs.Manufacturer
        Model        = $sku
        ProductCode  = $bb.Product
        Serial       = $bios.SerialNumber
        MACAddresses = $mac
        OSCaption    = $os.Caption
        OSRelease    = $ver
        OSBuild      = $os.BuildNumber
    }
}

function Send-PCInfo {
    Log -Level HEADER -Message "Collecting and Sending PC Info"

    try {
        Log -Level INFO -Message "Gathering PC information..."
        $data = Get-PCInfo
        $json = $data | ConvertTo-Json

        Log -Level INFO -Message "Sending data to arjo-metrics..."
        Invoke-RestMethod `
            -Uri "https://arjo-metrics.k14net.org/pc-info" `
            -Method POST `
            -ContentType "application/json" `
            -Body $json `
            -ErrorAction Stop

        Log -Level SUCCESS -Message "PC info sent successfully."

        # Display what was sent
        Write-Host ""
        Write-Host "  Submitted data:" -ForegroundColor DarkGray
        $data.PSObject.Properties | ForEach-Object {
            $line = ("  {0,-15} {1}" -f $_.Name, $_.Value)
            Send-UdpLog -Message "[INFO] $line"
            Write-Host $line -ForegroundColor White
        }

    } catch {
        Log -Level ERROR -Message "Failed to send PC info: $_"
    }
}

# Auto-run if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    # Fallback Log if running standalone
    if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
        function Log {
            param([string]$Level, [string]$Message)
            $colors = @{ "HEADER" = "Magenta"; "INFO" = "Cyan"; "SUCCESS" = "Green"; "WARN" = "Yellow"; "ERROR" = "Red" }
            $color = if ($colors.ContainsKey($Level)) { $colors[$Level] } else { "White" }
            Write-Host "[$Level] $Message" -ForegroundColor $color
        }
    }
    Send-PCInfo
}
