function Install-SoftwareOnPCs {
    # Software map
    $softwareMap = [ordered]@{
        "1"  = @{ Label = "LogMeIn";     Package = "LogmeinLogmeinclient_4.1.16006_EN_01" }
        "2"  = @{ Label = "Adobe Acrobat"; Package = "AdobeAcrobatDC_21_SSP_EN_01_(x64)" }
        "3"  = @{ Label = "Teams";       Package = "MicrosoftTeams_25275.2601.4002.2815_EN_02_(x64)" }
        "4"  = @{ Label = "Office 365";  Package = "MicrosoftOffice365_MEC_(x64)_CDN" }
        "5"  = @{ Label = "Visio";       Package = "MicrosoftVisioStandard_2024_(x64)_CDN" }
        "6"  = @{ Label = "Power BI";    Package = "MicrosoftPowerBIDesktop_2.138.1452.0_EN_01_(x64)" }
        "7"  = @{ Label = "Office LTSC"; Package = "MicrosoftOffice2024StandardLTSC_(x64)_CDN" }
        "8"  = @{ Label = "SPPC3";       Package = "ArjoSPPC3_1.6.5280.27624_EN_01_(x86)" }
        "9"  = @{ Label = "PL23";        Package = "ProlificUSB-Serial-COM-Port_4.3.0.0_Driver_(x64)" }
        "10" = @{ Label = "TempLogger";  Package = "ErlenGmbHTemplogger2_2.60_DE_01_(x86)" }
    }

    $apiUrl = "https://example.com/install"

    # Get PC list
    $pcInput = Read-Host "Enter PC name(s) comma-separated (e.g. PC021044,PC021045)"
    $pcs = $pcInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    if ($pcs.Count -eq 0) {
        Log -Level WARN -Message "No PCs entered."
        return
    }

    # Show software menu
    Log -Level HEADER -Message "Select Software to Install"
    foreach ($key in $softwareMap.Keys) {
        Write-Host "  [$key] $($softwareMap[$key].Label)" -ForegroundColor White
    }

    Write-Host ""
    $selection = Read-Host "Enter number(s) comma-separated (e.g. 1,3,4)"
    $selected = $selection -split ',' | ForEach-Object { $_.Trim() }

    # Resolve selected packages
    $packages = @()
    foreach ($s in $selected) {
        if ($softwareMap.ContainsKey($s)) {
            $packages += $softwareMap[$s].Package
        } else {
            Log -Level WARN -Message "Invalid selection: $s — skipping"
        }
    }

    if ($packages.Count -eq 0) {
        Log -Level WARN -Message "No valid software selected."
        return
    }

    # Confirm
    Write-Host ""
    Log -Level INFO -Message "PCs: $($pcs -join ', ')"
    Log -Level INFO -Message "Software: $($packages -join ', ')"
    Write-Host ""
    $confirm = Read-Host "Confirm? (y/n)"
    if ($confirm -ne "y") {
        Log -Level WARN -Message "Cancelled."
        return
    }

    # Build payload
    $payload = @{
        pcs      = $pcs
        packages = $packages
    } | ConvertTo-Json

    # Send POST request
    try {
        Log -Level INFO -Message "Sending to API..."
        Invoke-RestMethod -Uri $apiUrl -Method POST -ContentType "application/json" -Body $payload -ErrorAction Stop
        Log -Level SUCCESS -Message "Request sent successfully."
    } catch {
        Log -Level ERROR -Message "Failed to send request: $_"
    }
}

# Fallback Log if running standalone
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param([string]$Level, [string]$Message)
        $colors = @{ "HEADER" = "Magenta"; "INFO" = "Cyan"; "SUCCESS" = "Green"; "WARN" = "Yellow"; "ERROR" = "Red" }
        $color = if ($colors.ContainsKey($Level)) { $colors[$Level] } else { "White" }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

# Auto-run if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Install-SoftwareOnPCs
}
