# ==============================================================================
# CloudDriveMapperL.ps1
# Purpose: Deploys Map_L_Drive.ps1 and CDM-L-DriveMapper.xml into C:\Scripts.
#          Files are created locally via Set-Content (not downloaded with
#          -OutFile) so they carry no Mark-of-the-Web / Zone.Identifier flag.
# ==============================================================================

function Install-CloudDriveMapperL {

    $ScriptsFolder = "C:\Scripts"
    $ScriptPath    = Join-Path $ScriptsFolder "Map_L_Drive.ps1"
    $XmlPath       = Join-Path $ScriptsFolder "CDM-L-DriveMapper.xml"

    $ScriptUrl = "https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/Map_L_Drive.ps1"
    $XmlUrl    = "https://raw.githubusercontent.com/archways404/arjo-tools/refs/heads/master/scripts/CloudDriveMapper/CDM-L-DriveMapper.xml"

    Log -Level INFO -Message "Creating folder: $ScriptsFolder"
    if (-not (Test-Path -LiteralPath $ScriptsFolder)) {
        New-Item -ItemType Directory -Path $ScriptsFolder -Force | Out-Null
    }

    # --- Fetch content as text, then write it ourselves (no -OutFile) ---
    try {
        Log -Level INFO -Message "Fetching Map_L_Drive.ps1 content..."
        $scriptContent = (Invoke-WebRequest -Uri $ScriptUrl -UseBasicParsing -ErrorAction Stop).Content
    } catch {
        Log -Level ERROR -Message "Failed to fetch Map_L_Drive.ps1: $_"
        return
    }

    try {
        Log -Level INFO -Message "Fetching CDM-L-DriveMapper.xml content..."
        $xmlContent = (Invoke-WebRequest -Uri $XmlUrl -UseBasicParsing -ErrorAction Stop).Content
    } catch {
        Log -Level ERROR -Message "Failed to fetch CDM-L-DriveMapper.xml: $_"
        return
    }

    # Strip BOM if present on either payload
    if ($scriptContent.Length -gt 0 -and [int][char]$scriptContent[0] -eq 0xFEFF) {
        $scriptContent = $scriptContent.Substring(1)
    }
    if ($xmlContent.Length -gt 0 -and [int][char]$xmlContent[0] -eq 0xFEFF) {
        $xmlContent = $xmlContent.Substring(1)
    }

    try {
        Log -Level INFO -Message "Writing $ScriptPath"
        Set-Content -LiteralPath $ScriptPath -Value $scriptContent -Encoding UTF8 -Force

        Log -Level INFO -Message "Writing $XmlPath"
        Set-Content -LiteralPath $XmlPath -Value $xmlContent -Encoding UTF8 -Force
    } catch {
        Log -Level ERROR -Message "Failed to write files to $($ScriptsFolder): $_"
        return
    }

    Log -Level SUCCESS -Message "CDM L-Drive Mapper files deployed to $ScriptsFolder."
}
