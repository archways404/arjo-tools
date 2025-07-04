<#
Collect-Diag.ps1
• Self-elevates once; runs “lite” if declined.
• Writes a ZIP on the current user’s Desktop.
• Adds Users read perms so any account can open the ZIP.
#>

param(
    [int]$DaysOfLogs = 7,
    [string]$OutDir  = "$([Environment]::GetFolderPath('Desktop'))\Diag-$($env:COMPUTERNAME)-$(Get-Date -f yyyyMMdd-HHmmss)"
)

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
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

############ 1. OS info ############
Get-CimInstance Win32_OperatingSystem |
  Select CSName, Caption, Version, BuildNumber, OSArchitecture, InstallDate |
  Export-Csv "$OutDir\OS_Version.csv" -NoTypeInformation

############ 2. Driver list ############
try {
    Get-CimInstance Win32_PnPSignedDriver |
      Select DeviceName, DriverVersion, DriverProviderName, DriverDate, InfName |
      Export-Csv "$OutDir\Drivers.csv" -NoTypeInformation
} catch {
    Write-Warning "Full driver inventory needs admin; falling back to Get-PnpDevice"
    Get-PnpDevice -PresentOnly |
      Select FriendlyName, Class, Manufacturer, DriverVersion |
      Export-Csv "$OutDir\Drivers.csv" -NoTypeInformation
}

############ 3. Extra system facts ############

# 3a) Systeminfo
systeminfo /FO LIST > "$OutDir\SystemInfo.txt"

############ 3b) Installed applications ############
$apps = foreach ($hive in
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
{
    Get-ChildItem $hive |
        Get-ItemProperty |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
}

$apps |
    Where-Object { $_.DisplayName } |      # keep rows that have a name
    Sort-Object  DisplayName       |
    Export-Csv   "$OutDir\InstalledApps.csv" -NoTypeInformation

# 3c) Network
ipconfig /all > "$OutDir\Network.txt"
Get-NetAdapter | Format-List * >> "$OutDir\Network.txt"
Get-DnsClientServerAddress | Format-List * >> "$OutDir\Network.txt"

# 3d) Windows update history (last 30)
Get-WinEvent -FilterHashtable @{LogName='System';ID=19,20; StartTime=(Get-Date).AddDays(-30)} |
    Select TimeCreated, ProviderName, Id, Message |
    Export-Csv "$OutDir\WindowsUpdates.csv" -NoTypeInformation

############ 4. Event logs ############
$logs = @('Application','System','Setup','Microsoft-Windows-WMI-Activity/Operational')
foreach ($ln in $logs) {
    $dest = Join-Path $logDir ("$($ln.Replace('/','_')).evtx")
    wevtutil epl "$ln" $dest /q:"*[System[TimeCreated[timediff(@SystemTime) <= $($DaysOfLogs*86400000)]]]" 2>$null
}

############ 5. Zip & set ACL ############
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = "$OutDir.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($OutDir, $zipPath)

# make sure every local user can at least read the ZIP
icacls $zipPath /grant Users:R > $null

Write-Host "Diagnostics saved to $zipPath"