# ==============================================================================
# Lenovo System Updates — LSUClient auto-resume after reboot + install status API
#
# What this script does:
# - Runs Lenovo updates using LSUClient
# - Downloads packages before installing
# - Registers a startup scheduled task so it can continue after reboot
# - Runs as SYSTEM after reboot, no login required
# - Reports progress to install-status API
# - Queues status messages locally if network/API is unavailable
# - Prevents duplicate instances with a global mutex lock
# - Reboots after each install batch, then resumes
# - Removes scheduled task when no updates remain
# ==============================================================================

param(
    [switch]$Resume,
    [switch]$AutoRun
)

# ----------------------------------------------------------------------
# URLs & Ports
# ----------------------------------------------------------------------
$ScriptUrl        = "https://raw.githubusercontent.com/archways404/arjo-tools/master/pipelines/install26/components/drivers.ps1"
$StatusApiUrl     = "https://arjo-metrics.k14net.org/install-status"
$UdpLogHost = "arjo-metrics.k14net.org"
$UdpLogPort = 9999
$script:UdpClient = $null

# ----------------------------------------------------------------------
# Local paths
# ----------------------------------------------------------------------
$BaseDir          = "C:\ProgramData\ArjoTools"
$LocalScriptPath  = Join-Path $BaseDir "lenovo-updates.ps1"
$LogDir           = Join-Path $BaseDir "Logs"
$TaskName         = "Arjo Lenovo Updates Resume"
$CompletedFile    = Join-Path $BaseDir "LenovoUpdatesCompleted.txt"
$StatusQueueFile  = Join-Path $BaseDir "install-status-queue.jsonl"

# ----------------------------------------------------------------------
# Single-instance lock
# Prevents two elevated windows / scheduled task instances from running together.
# ----------------------------------------------------------------------
$MutexName        = "Global\ArjoLenovoUpdatesMutex"
$script:Mutex     = $null
$script:LogFile   = $null

function Ensure-Folders {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Send-UdpLines {
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines,
        [string]$Level = "INFO"
    )
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        Send-UdpLog -Message "[$Level] $line"
    }
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Script,
        [string]$Level = "INFO"
    )

    $items = New-Object System.Collections.Generic.List[object]

    try {
        & $Script 4>&1 | ForEach-Object {
            $items.Add($_)

            if ($_ -is [System.Management.Automation.VerboseRecord]) {
                $text = $_.Message
            } else {
                $text = $_.ToString()
            }

            Send-UdpLog -Message "[$Level] $text"
            Write-Host $text
        }

        return @($items)
    } catch {
        Send-UdpLog -Message "[ERROR] $($_.Exception.Message)"
        throw
    }
}

function Log {
    param(
        [ValidateSet("INFO","SUCCESS","WARN","ERROR","HEADER")][string]$Level,
        [string]$Message
    )

    Send-UdpLog -Message "[$Level] $Message"

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -ErrorAction SilentlyContinue
    }

    $map = @{
        INFO    = "Cyan"
        SUCCESS = "Green"
        WARN    = "Yellow"
        ERROR   = "Red"
        HEADER  = "Magenta"
    }

    if ($Level -eq "HEADER") {
        Write-Host "`n==== $Message ====" -ForegroundColor $map[$Level]
    } else {
        Write-Host $line -ForegroundColor $map[$Level]
    }
}

function Init-UdpLogger {
    try {
        $script:UdpClient = New-Object System.Net.Sockets.UdpClient
        $script:UdpClient.Connect($UdpLogHost, $UdpLogPort)
    } catch {
        # silent — UDP logging is best-effort
    }
}

function Send-UdpLog {
    param([string]$Message)
    try {
        if (-not $script:UdpClient) { return }
        $line = "$($env:COMPUTERNAME) | $(Get-Date -Format 'HH:mm:ss') | $Message"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
        $script:UdpClient.Send($bytes, $bytes.Length) | Out-Null
    } catch {}
}

function Close-UdpLogger {
    try {
        if ($script:UdpClient) {
            $script:UdpClient.Close()
            $script:UdpClient = $null
        }
    } catch {}
}

function Wait-ForNetwork {
    param(
        [int]$TimeoutSeconds = 300,
        [int]$RetrySeconds = 10
    )

    Log -Level INFO -Message "Waiting for network/API availability..."

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if (Test-StatusApiAvailable) {
            Log -Level SUCCESS -Message "Network/API is available."
            return $true
        }

        Log -Level WARN -Message "Network/API not ready yet. Retrying in $RetrySeconds seconds..."
        Start-Sleep -Seconds $RetrySeconds
    }

    Log -Level WARN -Message "Network/API did not become available within $TimeoutSeconds seconds. Continuing anyway."
    return $false
}

function Get-SerialNumber {
    try {
        return (Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber
    } catch {
        return $null
    }
}

function Test-StatusApiAvailable {
    try {
        Invoke-WebRequest `
            -Uri $StatusApiUrl `
            -Method GET `
            -UseBasicParsing `
            -TimeoutSec 5 `
            -ErrorAction Stop | Out-Null

        return $true
    } catch {
        return $false
    }
}

function Add-StatusToQueue {
    param([string]$JsonBody)

    try {
        Ensure-Folders
        Add-Content -LiteralPath $StatusQueueFile -Value $JsonBody -ErrorAction SilentlyContinue
    } catch {}
}

function Flush-StatusQueue {
    if (-not (Test-Path $StatusQueueFile)) {
        return
    }

    if (-not (Test-StatusApiAvailable)) {
        return
    }

    try {
        $queued = Get-Content -LiteralPath $StatusQueueFile -ErrorAction Stop

        if (-not $queued -or $queued.Count -eq 0) {
            Remove-Item -LiteralPath $StatusQueueFile -Force -ErrorAction SilentlyContinue
            return
        }

        $remaining = New-Object System.Collections.Generic.List[string]

        foreach ($line in $queued) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                Invoke-RestMethod `
                    -Uri $StatusApiUrl `
                    -Method POST `
                    -Body $line `
                    -ContentType "application/json" `
                    -TimeoutSec 10 `
                    -ErrorAction Stop | Out-Null
            } catch {
                $remaining.Add($line)
            }
        }

        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $StatusQueueFile -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $StatusQueueFile -Value $remaining -Force
        }
    } catch {}
}

function Send-InstallStatus {
    param(
        [string]$Stage,
        [string]$Status,
        [string]$Message,
        [string]$CurrentStep = $null,
        [int]$CompletedSteps = 0,
        [int]$TotalSteps = 0,
        [hashtable]$Extra = @{}
    )

    $body = @{
        PCName         = $env:COMPUTERNAME
        Serial         = Get-SerialNumber
        Stage          = $Stage
        Status         = $Status
        Message        = $Message
        CurrentStep    = $CurrentStep
        CompletedSteps = $CompletedSteps
        TotalSteps     = $TotalSteps
        Resume         = [bool]$Resume
        UserContext    = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        LogFile        = $script:LogFile
        Timestamp      = (Get-Date).ToString("o")
        Extra          = $Extra
    } | ConvertTo-Json -Depth 10 -Compress

    # Try to send old queued messages before sending the new one.
    Flush-StatusQueue

    try {
        Invoke-RestMethod `
            -Uri $StatusApiUrl `
            -Method POST `
            -Body $body `
            -ContentType "application/json" `
            -TimeoutSec 10 `
            -ErrorAction Stop | Out-Null
    } catch {
        Add-StatusToQueue -JsonBody $body
        Log -Level WARN -Message "Failed sending install status. Queued locally: $($_.Exception.Message)"
    }
}

function Start-SingleInstanceLock {
    try {
        $createdNew = $false
        $script:Mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$createdNew)

        if (-not $createdNew) {
            Log -Level WARN -Message "Another Lenovo update instance is already running. Exiting duplicate instance."
            Stop-Logging
            exit 0
        }

        Log -Level SUCCESS -Message "Single-instance lock acquired."
    } catch {
        Log -Level WARN -Message "Could not create mutex lock: $($_.Exception.Message)"
    }
}

function Stop-SingleInstanceLock {
    try {
        if ($script:Mutex) {
            $script:Mutex.ReleaseMutex()
            $script:Mutex.Dispose()
            $script:Mutex = $null
        }
    } catch {}
}

function Stop-Logging {
    Close-UdpLogger
    Stop-SingleInstanceLock
    try { Stop-Transcript | Out-Null } catch {}
}

function Test-IsSystem {
    return ([Security.Principal.WindowsIdentity]::GetCurrent().Name -eq "NT AUTHORITY\SYSTEM")
}

function Test-IsAdmin {
    if (Test-IsSystem) {
        return $true
    }

    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Test-PendingReboot {
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return $true }

    try {
        $pending = Get-ItemProperty `
            -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
            -Name PendingFileRenameOperations `
            -ErrorAction SilentlyContinue

        if ($pending.PendingFileRenameOperations) {
            return $true
        }
    } catch {}

    return $false
}

function Ensure-LocalScript {
    Ensure-Folders

    Log -Level INFO -Message "Downloading latest script to: $LocalScriptPath"

    Send-InstallStatus `
        -Stage "bootstrap" `
        -Status "running" `
        -Message "Downloading latest Lenovo update script" `
        -CurrentStep "Ensure-LocalScript"

    Invoke-WebRequest -Uri $ScriptUrl -OutFile $LocalScriptPath -UseBasicParsing -ErrorAction Stop

    Log -Level SUCCESS -Message "Local script updated."
}

function Register-ResumeTask {
    Log -Level INFO -Message "Registering startup resume task: $TaskName"

    Send-InstallStatus `
        -Stage "scheduled-task" `
        -Status "running" `
        -Message "Registering resume task" `
        -CurrentStep "Register-ResumeTask"

    $action = New-ScheduledTaskAction `
        -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`" -Resume -AutoRun"

    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = [System.Xml.XmlConvert]::ToString((New-TimeSpan -Minutes 2))

    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -MultipleInstances IgnoreNew `
            -RestartCount 5 `
            -RestartInterval (New-TimeSpan -Minutes 5) `
            -ExecutionTimeLimit (New-TimeSpan -Hours 3)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    $createdTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Log -Level SUCCESS -Message "Resume task registered. State: $($createdTask.State)"

}

function Remove-ResumeTask {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if ($task) {
        Log -Level INFO -Message "Removing scheduled task: $TaskName"
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Log -Level SUCCESS -Message "Scheduled task removed."
    }
}

function Ensure-LSUClient {
    Log -Level INFO -Message "Preparing PowerShell Gallery / NuGet / LSUClient..."

    Send-InstallStatus `
        -Stage "lsuclient" `
        -Status "running" `
        -Message "Preparing LSUClient module" `
        -CurrentStep "Ensure-LSUClient"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction Stop | Out-Null
        Log -Level SUCCESS -Message "NuGet provider ready."
    } catch {
        Log -Level WARN -Message "NuGet provider install/check failed: $($_.Exception.Message)"
    }

    try {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction Stop
        $oldPolicy = $repo.InstallationPolicy

        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        Install-Module -Name LSUClient -Force -Scope AllUsers -AllowClobber -ErrorAction Stop

        Set-PSRepository -Name PSGallery -InstallationPolicy $oldPolicy -ErrorAction SilentlyContinue
        Log -Level SUCCESS -Message "LSUClient ready."
    } catch {
        Send-InstallStatus `
            -Stage "lsuclient" `
            -Status "failed" `
            -Message "Failed to install LSUClient" `
            -CurrentStep "Ensure-LSUClient" `
            -Extra @{ Error = $_.Exception.Message }

        throw
    }
}

function Complete-Run {
    Log -Level SUCCESS -Message "No Lenovo updates remaining."

    $content = @"
Completed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME
UserContext: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)
LogFile: $script:LogFile
"@

    Set-Content -LiteralPath $CompletedFile -Value $content -Force

    Remove-ResumeTask

    Send-InstallStatus `
        -Stage "lenovo-updates" `
        -Status "completed" `
        -Message "No Lenovo updates remaining. Finished completely." `
        -CurrentStep "Complete-Run"

    Log -Level SUCCESS -Message "Completion marker written to: $CompletedFile"
    Log -Level SUCCESS -Message "Finished completely."
    Stop-Logging
}

function Start-LenovoUpdates {
    Ensure-Folders

    Init-UdpLogger

    $script:LogFile = Join-Path $LogDir "lsuclient_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    try {
        Start-Transcript -LiteralPath $script:LogFile -Append | Out-Null
    } catch {}

    Log -Level HEADER -Message "Lenovo updates started"
    Log -Level INFO -Message "Resume mode: $Resume"
    Log -Level INFO -Message "Log file: $script:LogFile"
    Log -Level INFO -Message "Computer: $env:COMPUTERNAME"
    Log -Level INFO -Message "User context: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

    # Important: acquire the lock before sending startup status.
    # This avoids duplicate elevated windows both reporting "running".
    Start-SingleInstanceLock

    # After reboot, network/services may not be ready yet.

    # Wait here before trying to report status or scan Lenovo updates.

    Wait-ForNetwork -TimeoutSeconds 300 -RetrySeconds 10 | Out-Null

    Send-InstallStatus `
        -Stage "startup" `
        -Status "running" `
        -Message "Lenovo update script started" `
        -CurrentStep "Start-LenovoUpdates"

    Flush-StatusQueue

    try {
    if (-not (Test-IsAdmin)) {
        Log -Level WARN -Message "Not running elevated. Relaunching as admin..."
        Send-InstallStatus `
          -Stage "elevation" `
          -Status "running" `
          -Message "Relaunching script as administrator" `
          -CurrentStep "Elevation"

$bootstrapCommand = @"
`$ScriptUrl = '$ScriptUrl'
`$BaseDir = 'C:\ProgramData\ArjoTools'
`$LocalScriptPath = Join-Path `$BaseDir 'lenovo-updates.ps1'
New-Item -ItemType Directory -Path `$BaseDir -Force | Out-Null
Invoke-WebRequest -Uri `$ScriptUrl -OutFile `$LocalScriptPath -UseBasicParsing -ErrorAction Stop
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File `$LocalScriptPath -AutoRun
"@
    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($bootstrapCommand)
    )
    Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand" `
        -Verb RunAs
    Stop-Logging
    return
}

        Remove-Item -LiteralPath $CompletedFile -Force -ErrorAction SilentlyContinue

        Ensure-LocalScript
        Register-ResumeTask
        Ensure-LSUClient

        $MaxRounds = 5

        for ($Round = 1; $Round -le $MaxRounds; $Round++) {
            Log -Level HEADER -Message "Round $Round of $MaxRounds"

            Send-InstallStatus `
                -Stage "lenovo-scan" `
                -Status "running" `
                -Message "Scanning for Lenovo updates" `
                -CurrentStep "Get-LSUpdate" `
                -CompletedSteps ($Round - 1) `
                -TotalSteps $MaxRounds `
                -Extra @{
                    Round = $Round
                }
                $rawOutput = Invoke-LoggedCommand {
                    Get-LSUpdate -Verbose
                } "INFO"
                $updates = @(
                    $rawOutput | Where-Object {
                        $_ -isnot [System.Management.Automation.VerboseRecord]
                    }
                )
                Log -Level INFO -Message "$($updates.Count) update(s) found."

            if ($updates.Count -eq 0) {
                Complete-Run
                return
            }

            Send-InstallStatus `
                -Stage "lenovo-download" `
                -Status "running" `
                -Message "$($updates.Count) Lenovo update(s) found. Starting downloads." `
                -CurrentStep "Save-LSUpdate" `
                -CompletedSteps 0 `
                -TotalSteps $updates.Count `
                -Extra @{
                    Round = $Round
                    UpdateCount = $updates.Count
                    Updates = @($updates | ForEach-Object { $_.Title })
                }

            $d = 1

            foreach ($update in $updates) {
                Send-InstallStatus `
                    -Stage "lenovo-download" `
                    -Status "running" `
                    -Message "Downloading Lenovo update $d of $($updates.Count): $($update.Title)" `
                    -CurrentStep $update.Title `
                    -CompletedSteps ($d - 1) `
                    -TotalSteps $updates.Count `
                    -Extra @{
                        Round = $Round
                        UpdateTitle = $update.Title
                        DownloadIndex = $d
                    }

                try {
                  Invoke-LoggedCommand { $update | Save-LSUpdate -Verbose } "INFO" | Out-Null

                    Send-InstallStatus `
                        -Stage "lenovo-download" `
                        -Status "running" `
                        -Message "Downloaded Lenovo update $d of $($updates.Count): $($update.Title)" `
                        -CurrentStep $update.Title `
                        -CompletedSteps $d `
                        -TotalSteps $updates.Count `
                        -Extra @{
                            Round = $Round
                            UpdateTitle = $update.Title
                            DownloadIndex = $d
                        }
                } catch {
                    Log -Level ERROR -Message "Failed downloading $($update.Title): $($_.Exception.Message)"

                    Send-InstallStatus `
                        -Stage "lenovo-download" `
                        -Status "failed" `
                        -Message "Failed downloading Lenovo update $d of $($updates.Count): $($update.Title)" `
                        -CurrentStep $update.Title `
                        -CompletedSteps ($d - 1) `
                        -TotalSteps $updates.Count `
                        -Extra @{
                            Round = $Round
                            UpdateTitle = $update.Title
                            Error = $_.Exception.Message
                        }
                }

                $d++
            }

            Log -Level SUCCESS -Message "Download phase completed."

            $i = 1

            foreach ($update in $updates) {
                Log -Level HEADER -Message "Installing [$i/$($updates.Count)]"
                Log -Level INFO -Message "$($update.Title)"

                Send-InstallStatus `
                    -Stage "lenovo-install" `
                    -Status "running" `
                    -Message "Installing Lenovo update $i of $($updates.Count): $($update.Title)" `
                    -CurrentStep $update.Title `
                    -CompletedSteps ($i - 1) `
                    -TotalSteps $updates.Count `
                    -Extra @{
                        Round = $Round
                        UpdateTitle = $update.Title
                        InstallIndex = $i
                    }

                try {
                  Invoke-LoggedCommand {
                      Install-LSUpdate `
                            -Package $update `
                            -Verbose `
                            -SaveBIOSUpdateInfoToRegistry
                  } "INFO" | Out-Null

                    Send-InstallStatus `
                        -Stage "lenovo-install" `
                        -Status "running" `
                        -Message "Installed Lenovo update $i of $($updates.Count): $($update.Title)" `
                        -CurrentStep $update.Title `
                        -CompletedSteps $i `
                        -TotalSteps $updates.Count `
                        -Extra @{
                            Round = $Round
                            UpdateTitle = $update.Title
                            InstallIndex = $i
                        }

                    Log -Level SUCCESS -Message "Installed: $($update.Title)"
                } catch {
                    Log -Level ERROR -Message "Failed installing $($update.Title): $($_.Exception.Message)"

                    Send-InstallStatus `
                        -Stage "lenovo-install" `
                        -Status "failed" `
                        -Message "Failed installing Lenovo update $i of $($updates.Count): $($update.Title)" `
                        -CurrentStep $update.Title `
                        -CompletedSteps ($i - 1) `
                        -TotalSteps $updates.Count `
                        -Extra @{
                            Round = $Round
                            Error = $_.Exception.Message
                            UpdateTitle = $update.Title
                            InstallIndex = $i
                        }
                }

                $i++
            }

            $needsReboot = Test-PendingReboot

            if ($updates.Count -gt 0 -or $needsReboot) {
                Log -Level WARN -Message "Updates were installed or reboot is pending. Rebooting in 30 seconds. Script will resume at startup."

                Send-InstallStatus `
                    -Stage "reboot" `
                    -Status "rebooting" `
                    -Message "Updates were installed or reboot is pending. Rebooting in 30 seconds." `
                    -CurrentStep "Restart-Computer" `
                    -Extra @{
                        UpdatesInstalledThisRound = $updates.Count
                        PendingRebootDetected = $needsReboot
                        Round = $Round
                    }

                Stop-Logging
                Start-Sleep -Seconds 30
                Restart-Computer -Force
                return
            }

            Log -Level INFO -Message "No pending reboot detected after round $Round."
        }

        Log -Level WARN -Message "Max rounds reached. Re-checking update state."

        $remaining = @(Get-LSUpdate)

        if ($remaining.Count -eq 0) {
            Complete-Run
            return
        }

        Send-InstallStatus `
            -Stage "lenovo-updates" `
            -Status "warning" `
            -Message "$($remaining.Count) update(s) still remain after max rounds. Task will retry after next startup." `
            -CurrentStep "MaxRoundsReached" `
            -Extra @{
                RemainingCount = $remaining.Count
                RemainingUpdates = @($remaining | ForEach-Object { $_.Title })
            }

        Stop-Logging
    } catch {
        Log -Level ERROR -Message "Fatal script error: $($_.Exception.Message)"

        Send-InstallStatus `
            -Stage "fatal" `
            -Status "failed" `
            -Message "Fatal Lenovo update script error" `
            -CurrentStep "Start-LenovoUpdates" `
            -Extra @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            }

        Stop-Logging
        throw
    }
}

if ($AutoRun) {
    Start-LenovoUpdates
}
