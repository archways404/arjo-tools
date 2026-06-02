function Install-MicrosoftTeams {
    Log -Level HEADER -Message "Install Microsoft Teams"

    # Check if Teams is already installed
    $teamsInstalled = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
    if ($teamsInstalled) {
        Log -Level INFO -Message "Microsoft Teams is already installed."
        return
    }

    # Check if winget is available
    $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue

    if ($wingetAvailable) {
        Log -Level INFO -Message "Installing Microsoft Teams via winget..."
        try {
            winget install --id "XP8BT8DW290MPQ" --source msstore --accept-package-agreements --accept-source-agreements --silent
            Log -Level SUCCESS -Message "Microsoft Teams installed successfully."
        } catch {
            Log -Level ERROR -Message "winget install failed: $_"
        }
    } else {
        Log -Level WARN -Message "winget not available — falling back to bootstrapper download..."

        $bootstrapperUrl = "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"
        $tempPath = "$env:TEMP\TeamsBootstrapper.exe"

        try {
            Log -Level INFO -Message "Downloading Teams bootstrapper..."
            Invoke-WebRequest -Uri $bootstrapperUrl -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
            Log -Level INFO -Message "Running Teams bootstrapper silently..."
            Start-Process -FilePath $tempPath -ArgumentList "-p" -Wait -NoNewWindow
            Log -Level SUCCESS -Message "Microsoft Teams installed successfully via bootstrapper."
        } catch {
            Log -Level ERROR -Message "Bootstrapper install failed: $_"
        } finally {
            # Clean up temp file
            if (Test-Path $tempPath) {
                Remove-Item $tempPath -Force
                Log -Level INFO -Message "Cleaned up temporary installer."
            }
        }
    }
}

# Auto-run if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Install-MicrosoftTeams
}
