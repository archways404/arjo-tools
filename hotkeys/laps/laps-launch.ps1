param([string]$PCName)

# Load .env from same directory as script
$envFile = Join-Path $PSScriptRoot ".env"
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.+)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
    }
}

$user = [System.Environment]::GetEnvironmentVariable("LAPS_USER")
$pw   = ConvertTo-SecureString ([System.Environment]::GetEnvironmentVariable("LAPS_PASSWORD")) -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($user, $pw)

Start-Process -FilePath "C:\Program Files\Microsoft LAPS UI Legacy\AdmPwd.UI.exe" -Credential $cred -WorkingDirectory "C:\Program Files\Microsoft LAPS UI Legacy"
