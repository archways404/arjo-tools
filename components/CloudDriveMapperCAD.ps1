# ==============================================================================
# CloudDriveMapperCAD.ps1
# Purpose: Deploys the L: drive subst-mapper files (for AutoCAD/CDM V3 exception users).
#          - Creates C:\Scripts
#          - Downloads Map_L_Drive.ps1 into C:\Scripts
#          - Downloads CDM-L-DriveMapper.xml into C:\Scripts (with current user injected)
#          NOTE: Does NOT register or run the scheduled task — that's a separate manual
#                step (Task Scheduler → Import Task, or schtasks /Create /XML ...).
# Entry point: Install-CloudDriveMapperCAD
# ==============================================================================

function Install-CloudDriveMapperCAD {

    $scriptsFolder = "C:\Scripts"
    $psScriptUrl   = "https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/Map_L_Drive.ps1"
    $xmlUrl        = "https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/CDM-L-DriveMapper.xml"
    $psScriptPath  = Join-Path $scriptsFolder "Map_L_Drive.ps1"
    $xmlPath       = Join-Path $scriptsFolder "CDM-L-DriveMapper.xml"

    # --- Force TLS 1.2 (GitHub requires it; older .NET/PowerShell defaults can be TLS 1.0/1.1) ---
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Log -Level WARN -Message "Could not explicitly set TLS 1.2 (may already be enforced): $_"
    }

    # --- Helper: download a URL as text, with proxy fallback if direct request fails ---
    function Get-RemoteText {
        param([string]$Uri)

        try {
            # Attempt 1: direct request
            return (Invoke-WebRequest -Uri $Uri -UseBasicParsing -ErrorAction Stop).Content
        } catch {
            $firstError = $_
            Log -Level WARN -Message "Direct download failed for $Uri : $firstError"
            Log -Level INFO -Message "Retrying using system default proxy credentials..."

            try {
                # Attempt 2: explicit system proxy with current user's default credentials
                return (Invoke-WebRequest -Uri $Uri -UseBasicParsing -Proxy ([System.Net.WebRequest]::GetSystemWebProxy().GetProxy($Uri)) -ProxyUseDefaultCredentials -ErrorAction Stop).Content
            } catch {
                Log -Level ERROR -Message "Proxy retry also failed for $Uri : $_"
                throw "Unable to download $Uri (direct and proxy attempts both failed)."
            }
        }
    }

    # --- Step 1: Create C:\Scripts if it doesn't exist ---
    try {
        if (-not (Test-Path -LiteralPath $scriptsFolder)) {
            Log -Level INFO -Message "Creating folder: $scriptsFolder"
            New-Item -ItemType Directory -Path $scriptsFolder -Force -ErrorAction Stop | Out-Null
        } else {
            Log -Level INFO -Message "Folder already exists: $scriptsFolder"
        }
    } catch {
        Log -Level ERROR -Message "Failed to create $scriptsFolder : $_"
        Log -Level ERROR -Message "DEPLOYMENT FAILED — could not create scripts folder."
        return
    }

    # --- Step 2: Download Map_L_Drive.ps1 ---
    try {
        Log -Level INFO -Message "Downloading Map_L_Drive.ps1..."
        $psContent = Get-RemoteText -Uri $psScriptUrl

        if ($psContent.Length -gt 0 -and [int][char]$psContent[0] -eq 0xFEFF) {
            $psContent = $psContent.Substring(1)
        }
        if ($psContent.StartsWith("ï»¿")) {
            $psContent = $psContent.Substring(3)
        }

        Set-Content -LiteralPath $psScriptPath -Value $psContent -Encoding UTF8 -ErrorAction Stop
        Log -Level SUCCESS -Message "Saved script to $psScriptPath"
    } catch {
        Log -Level ERROR -Message "Failed to download/save Map_L_Drive.ps1: $_"
        Log -Level ERROR -Message "DEPLOYMENT FAILED — could not retrieve/save the mapper script."
        return
    }

    # --- Step 3: Download CDM-L-DriveMapper.xml ---
    try {
        Log -Level INFO -Message "Downloading CDM-L-DriveMapper.xml..."
        $xmlContent = Get-RemoteText -Uri $xmlUrl

        if ($xmlContent.Length -gt 0 -and [int][char]$xmlContent[0] -eq 0xFEFF) {
            $xmlContent = $xmlContent.Substring(1)
        }
        if ($xmlContent.StartsWith("ï»¿")) {
            $xmlContent = $xmlContent.Substring(3)
        }

        # Replace placeholder with the current logged-in user (DOMAIN\username)
        $currentUser = "$env:USERDOMAIN\$env:USERNAME"
        Log -Level INFO -Message "Injecting current user into task XML: $currentUser"
        $xmlContent = $xmlContent -replace "%%CURRENTUSER%%", [System.Security.SecurityElement]::Escape($currentUser)

        Set-Content -LiteralPath $xmlPath -Value $xmlContent -Encoding Unicode -ErrorAction Stop
        Log -Level SUCCESS -Message "Saved task definition to $xmlPath"
    } catch {
        Log -Level ERROR -Message "Failed to download/save CDM-L-DriveMapper.xml: $_"
        Log -Level ERROR -Message "DEPLOYMENT FAILED — could not retrieve/save the task XML."
        return
    }

    Log -Level SUCCESS -Message "DEPLOYMENT COMPLETE — files written to $scriptsFolder."
    Log -Level INFO -Message "To finish setup, import the task manually: Task Scheduler -> Action -> Import Task -> select $xmlPath"
    Log -Level INFO -Message "Or run: schtasks /Create /TN CDM-L-DriveMapper /XML `"$xmlPath`" /F"
}
