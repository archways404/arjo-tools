<#
Collect-Diag.ps1
• Self-elevates once; runs “lite” if declined.
• Writes a ZIP on the current user’s Desktop.
• Adds Users read perms so any account can open the ZIP.
• Outputs JSON for structured data.
#>

param(
    [int]$DaysOfLogs = 7,
    [string]$OutDir  = "$([Environment]::GetFolderPath('Desktop'))\Diag-$($env:COMPUTERNAME)-$(Get-Date -f yyyyMMdd-HHmmss)"
)

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# ── attempt self-elevation ──
if (-not (Test-Admin)) {
    try {
        Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -DaysOfLogs $DaysOfLogs -OutDir `"$OutDir`""
        return
    } catch {
        Write-Warning "Running without admin rights – some items may be missing."
    }
}

# ── create working folder ──
$null = New-Item -ItemType Directory -Force -Path $OutDir
$logDir = Join-Path $OutDir 'Logs'; New-Item $logDir -ItemType Directory | Out-Null

######### 1. OS info #########
Get-CimInstance Win32_OperatingSystem |
    Select-Object CSName, Caption, Version, BuildNumber, OSArchitecture, InstallDate |
    ConvertTo-Json -Depth 3 |
    Set-Content "$OutDir\OS_Version.json"

######### 2. Driver list #########
try {
    Get-CimInstance Win32_PnPSignedDriver |
        Select-Object DeviceName, DriverVersion, DriverProviderName, DriverDate, InfName |
        ConvertTo-Json -Depth 3 |
        Set-Content "$OutDir\Drivers.json"
} catch {
    Write-Warning "Full driver inventory needs admin; falling back to Get-PnpDevice."
    Get-PnpDevice -PresentOnly |
        Select-Object FriendlyName, Class, Manufacturer, DriverVersion |
        ConvertTo-Json -Depth 3 |
        Set-Content "$OutDir\Drivers.json"
}

######### 3. Extra system facts #########

# 3a) Systeminfo
systeminfo /FO LIST > "$OutDir\SystemInfo.txt"

# 3b) Installed applications
$apps = foreach ($hive in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
    Get-ChildItem $hive -ErrorAction SilentlyContinue |
        Get-ItemProperty |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
}

$apps |
    Where-Object { $_.DisplayName } |
    Sort-Object DisplayName |
    ConvertTo-Json -Depth 3 |
    Set-Content "$OutDir\InstalledApps.json"

# 3c) Network
ipconfig /all > "$OutDir\Network.txt"
Get-NetAdapter | Format-List * >> "$OutDir\Network.txt"
Get-DnsClientServerAddress | Format-List * >> "$OutDir\Network.txt"

# 3d) Windows update history (last 30 days)
Get-WinEvent -FilterHashtable @{LogName='System';ID=19,20; StartTime=(Get-Date).AddDays(-30)} |
    Select-Object TimeCreated, ProviderName, Id, Message |
    ConvertTo-Json -Depth 3 |
    Set-Content "$OutDir\WindowsUpdates.json"

######### 4. Event logs #########
$logs = @('Application','System','Setup','Microsoft-Windows-WMI-Activity/Operational')
foreach ($ln in $logs) {
    $dest = Join-Path $logDir ("$($ln.Replace('/','_')).evtx")
    wevtutil epl "$ln" $dest /q:"*[System[TimeCreated[timediff(@SystemTime) <= $($DaysOfLogs*86400000)]]]" 2>$null
}

######### 5. Zip & set ACL #########
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = "$OutDir.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($OutDir, $zipPath)

icacls $zipPath /grant Users:R > $null

Write-Host "Diagnostics saved to $zipPath"