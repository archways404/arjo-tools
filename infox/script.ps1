<#
Collect-Diag.ps1
• Windows version  | always
• Drivers.csv      | best-effort if not admin
• Logs (.evtx)     | only logs current user may read
The script tries to self-elevate once. If the user cancels UAC,
it continues in limited mode instead of dying.
#>

param(
    [int]    $DaysOfLogs = 7,
    [string] $OutDir     = "$([Environment]::GetFolderPath('Desktop'))\Diag-$($env:COMPUTERNAME)-$(Get-Date -f yyyyMMdd-HHmmss)"
)

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# ── self-elevate if possible ──
if (-not (Test-Admin)) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs `
            -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -DaysOfLogs $DaysOfLogs -OutDir `"$OutDir`""
        return
    } catch {
        Write-Warning "Continuing without elevation – certain data may be missing."
    }
}

# create output folder the user can write to
$null = New-Item -ItemType Directory -Force -Path $OutDir

######## 1. OS info (always works) ########
Get-CimInstance Win32_OperatingSystem |
  Select CSName, Caption, Version, BuildNumber, OSArchitecture, InstallDate |
  Export-Csv "$OutDir\OS_Version.csv" -NoType

######## 2. Driver list (may be partial) ########
try {
    Get-CimInstance Win32_PnPSignedDriver |
      Select DeviceName, DriverVersion, DriverProviderName, DriverDate, InfName |
      Export-Csv "$OutDir\Drivers.csv" -NoType
} catch {
    Write-Warning "Full driver inventory needs admin; falling back to Get-PnpDevice."
    Get-PnpDevice -PresentOnly |            # still ~ 80 % useful
      Select FriendlyName, Class, Manufacturer, DriverVersion |
      Export-Csv "$OutDir\Drivers.csv" -NoType
}

######## 3. Event logs the user can read ########
$logDir = Join-Path $OutDir 'Logs'; New-Item $logDir -ItemType Directory | Out-Null
$readable = @('Application','System')      # tweak as needed
foreach ($ln in $readable) {
    $dest = Join-Path $logDir "$ln.evtx"
    wevtutil epl "$ln" $dest /q:"*[System[TimeCreated[timediff(@SystemTime) <= $($DaysOfLogs*86400000)]]]" `
        2>$null             # suppress “access denied” if a log is locked down
}

######## 4. Zip the bundle ########
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = "$OutDir.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($OutDir, $zipPath)

Write-Host "Diagnostics saved to $zipPath"