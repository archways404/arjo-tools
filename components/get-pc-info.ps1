function Get-PCInfo {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $bb   = Get-CimInstance Win32_BaseBoard
    $macs = Get-NetAdapter | Select Name, @{N='MAC';E={$_.MacAddress -replace '-',':'}}
    $ver  = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    $sku  = $cs.SystemSKUNumber -replace '^.*FM_', ''

    [PSCustomObject]@{
        PCName       = $cs.Name
        Manufacturer = $cs.Manufacturer
        Model        = $sku
        ProductCode  = $bb.Product
        Serial       = $bios.SerialNumber
        MACAddresses = ($macs | ForEach-Object { "$($_.Name): $($_.MAC)" }) -join ' | '
        OSCaption    = $os.Caption
        OSRelease    = $ver
        OSBuild      = $os.BuildNumber
    } | Format-List
}

Get-PCInfo
