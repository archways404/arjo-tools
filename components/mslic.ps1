# Fallback Log function if not running inside arjo-tools
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param(
            [string]$Level,
            [string]$Message
        )
        $colors = @{
            "HEADER"  = "Magenta"
            "INFO"    = "Cyan"
            "SUCCESS" = "Green"
            "WARN"    = "Yellow"
            "ERROR"   = "Red"
        }
        $color = if ($colors.ContainsKey($Level)) { $colors[$Level] } else { "White" }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

function Get-UserLicense {
    # Check and install Microsoft.Graph module if missing
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Log -Level WARN -Message "Microsoft.Graph module not found."
        $install = Read-Host "Install Microsoft.Graph module now? (y/n)"
        if ($install -eq "y") {
            Log -Level INFO -Message "Installing Microsoft.Graph module..."
            try {
                Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
                Log -Level SUCCESS -Message "Microsoft.Graph installed successfully."
            } catch {
                Log -Level ERROR -Message "Failed to install Microsoft.Graph: $_"
                return
            }
        } else {
            Log -Level WARN -Message "Microsoft.Graph is required. Aborting."
            return
        }
    }

    if (-not (Get-Module -Name Microsoft.Graph.Users)) {
        Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
    }

    $userInput = Read-Host "Enter username, email or UPN"

    if ($userInput -notlike "*@*") {
        $userInput = "$userInput@arjo.com"
    }

    $licenseMap = @{
        "ENTERPRISEPACK"          = "Office 365 E3"
        "ENTERPRISEPREMIUM"       = "Office 365 E5"
        "SPE_E3"                  = "Microsoft 365 E3"
        "SPE_E5"                  = "Microsoft 365 E5"
        "EXCHANGESTANDARD"        = "Exchange Online Plan 1"
        "EXCHANGEENTERPRISE"      = "Exchange Online Plan 2"
        "INTUNE_A"                = "Microsoft Intune"
        "AAD_PREMIUM"             = "Azure AD Premium P1"
        "AAD_PREMIUM_P2"          = "Azure AD Premium P2"
        "FLOW_FREE"               = "Power Automate Free"
        "POWER_BI_STANDARD"       = "Power BI Free"
        "POWER_BI_PRO"            = "Power BI Pro"
        "PROJECTPREMIUM"          = "Project Plan 5"
        "VISIOCLIENT"             = "Visio Plan 2"
        "MCOSTANDARD"             = "Skype for Business Plan 2"
        "TEAMS_EXPLORATORY"       = "Microsoft Teams Exploratory"
        "Microsoft_Teams_Audio_Conferencing_select_dial_out" = "Teams Audio Conferencing"
    }

    $mecSkus = @(
        "ENTERPRISEPACK",
        "ENTERPRISEPREMIUM",
        "SPE_E3",
        "SPE_E5"
    )

    Log -Level HEADER -Message "License Info: $userInput"

    try {
        try {
            $context = Get-MgContext
            if (-not $context) {
                Log -Level INFO -Message "Connecting to Microsoft Graph..."
                Connect-MgGraph -Scopes "User.Read.All" -NoWelcome
            }
        } catch {
            Log -Level INFO -Message "Connecting to Microsoft Graph..."
            Connect-MgGraph -Scopes "User.Read.All" -NoWelcome
        }

        $licenses = Get-MgUserLicenseDetail -UserId $userInput -ErrorAction Stop

        if (-not $licenses) {
            Log -Level WARN -Message "No licenses found for $userInput"
            return
        }

        $hasMecLicense = $false

        foreach ($lic in $licenses) {
            $sku = $lic.SkuPartNumber
            $friendly = if ($licenseMap.ContainsKey($sku)) { $licenseMap[$sku] } else { $sku }
            Write-Host "  - $friendly" -ForegroundColor Cyan
            if ($mecSkus -contains $sku) {
                $hasMecLicense = $true
            }
        }

        Write-Host ""

        if ($hasMecLicense) {
            Log -Level SUCCESS -Message "Office Recommendation: Install MicrosoftOffice365_MEC_(x64)_CDN"
            Write-Host "  Reason: User has a subscription license that includes Microsoft 365 Apps." -ForegroundColor Gray
        } else {
            Log -Level INFO -Message "Office Recommendation: Install MicrosoftOffice2024StandardLTSC_(x64)_CDN"
            Write-Host "  Reason: No subscription license found that includes Microsoft 365 Apps." -ForegroundColor Gray
        }

    } catch {
        Log -Level ERROR -Message "Failed to retrieve licenses: $_"
    }
}

# Auto-run if executed directly (not loaded via iex)
if ($MyInvocation.InvocationName -ne '.') {
    Get-UserLicense
}
