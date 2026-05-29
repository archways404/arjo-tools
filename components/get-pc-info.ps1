function Get-ServerIP {
    # Look up your PC by its hostname
    $hostname = "PC025293"
    $ip = (Resolve-DnsName $hostname -ErrorAction SilentlyContinue).IPAddress |
          Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
          Select-Object -First 1
    if (-not $ip) { throw "Could not resolve IP for $hostname" }
    return $ip
}

function Get-PCInfo {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $bb   = Get-CimInstance Win32_BaseBoard
    #$macs = Get-NetAdapter | Select Name, @{N='MAC';E={$_.MacAddress -replace '-',':'}}
    # Get first connected physical ethernet adapter (excludes Wi-Fi, Bluetooth, virtual)
    $mac = (Get-NetAdapter -Physical | Where-Object {
        $_.Status -eq "Up" -and
        $_.Name -notlike "Wi-Fi*" -and
        $_.Name -notlike "Bluetooth*" -and
        $_.Name -like "Ethernet*"
    } | Select-Object -First 1).MacAddress -replace '-', ':'
    $ver  = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    $sku  = $cs.SystemSKUNumber -replace '^.*FM_', ''

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

$serverIP = Get-ServerIP
$data = Get-PCInfo
$json = $data | ConvertTo-Json

Invoke-RestMethod `
    -Uri "http://${serverIP}:3000/pc-info" `
    -Method POST `
    -ContentType "application/json" `
    -Body $json
