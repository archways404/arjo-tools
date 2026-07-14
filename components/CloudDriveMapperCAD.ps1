# ==============================================================================
# CloudDriveMapperCAD.ps1
# Purpose: Deploys the L: drive subst-mapper (for AutoCAD/CDM V3 exception users).
#          - Creates C:\Scripts
#          - Downloads Map_L_Drive.ps1 into C:\Scripts
#          - Downloads CDM-L-DriveMapper.xml into C:\Scripts
#          - Registers the scheduled task from that XML (runs as current user, at logon)
#          - Runs the task immediately and reports success/fail
# Entry point: Install-CloudDriveMapperCAD
# ==============================================================================

function Install-CloudDriveMapperCAD {

    $scriptsFolder = "C:\Scripts"
    $psScriptUrl   = "https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/Map_L_Drive.ps1"
    $xmlUrl        = "https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/CDM-L-DriveMapper.xml"
    $psScriptPath  = Join-Path $scriptsFolder "Map_L_Drive.ps1"
    $xmlPath       = Join-Path $scriptsFolder "CDM-L-DriveMapper.xml"
    $taskName      = "CDM-L-DriveMapper"

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

    $overallSuccess = $true

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

    # --- Step 4: Register the scheduled task from the XML ---
    try {
        Log -Level INFO -Message "Registering scheduled task '$taskName'..."

        $existing = schtasks /Query /TN $taskName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Log -Level WARN -Message "Task '$taskName' already exists — removing before re-registering."
            schtasks /Delete /TN $taskName /F | Out-Null
        }

        schtasks /Create /TN $taskName /XML $xmlPath /F | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "schtasks /Create returned exit code $LASTEXITCODE"
        }
        Log -Level SUCCESS -Message "Scheduled task '$taskName' registered successfully."
    } catch {
        Log -Level ERROR -Message "Failed to register scheduled task: $_"
        Log -Level ERROR -Message "DEPLOYMENT FAILED — task registration unsuccessful."
        return
    }

    # --- Step 5: Run the task immediately and check the result ---
    try {
        Log -Level INFO -Message "Running task '$taskName' now..."
        schtasks /Run /TN $taskName | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "schtasks /Run returned exit code $LASTEXITCODE"
        }

        # Give the task a moment to actually execute before checking its result
        Start-Sleep -Seconds 5

        # Query the task's last run result (exit code shown as LastTaskResult, 0 = success)
        $taskInfo = schtasks /Query /TN $taskName /V /FO LIST | Out-String

        if ($taskInfo -match "Last Result:\s*(\d+)") {
            $lastResult = $matches[1]
            if ($lastResult -eq "0") {
                Log -Level SUCCESS -Message "Task ran successfully (Last Result: 0)."
                $overallSuccess = $true
            } else {
                Log -Level ERROR -Message "Task ran but reported a non-zero result code: $lastResult"
                Log -Level ERROR -Message "Check C:\Scripts\Logs\Map_L_Drive.log for details."
                $overallSuccess = $false
            }
        } else {
            Log -Level WARN -Message "Could not parse task result from schtasks output. Check manually via Task Scheduler."
            $overallSuccess = $false
        }
    } catch {
        Log -Level ERROR -Message "Failed to run/verify scheduled task: $_"
        $overallSuccess = $false
    }

    # --- Final summary ---
    if ($overallSuccess) {
        Log -Level SUCCESS -Message "DEPLOYMENT COMPLETE — files deployed, task registered and ran successfully."
    } else {
        Log -Level ERROR -Message "DEPLOYMENT COMPLETED WITH ERRORS — review messages above and the log file."
    }
}
