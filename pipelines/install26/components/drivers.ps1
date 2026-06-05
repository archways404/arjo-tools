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
    [switch]$Resume
)

# ----------------------------------------------------------------------
# URLs
# ----------------------------------------------------------------------
$ScriptUrl        = "https://raw.githubusercontent.com/archways404/arjo-tools/master/components/lenovo-updates.ps1"
$StatusApiUrl     = "https://arjo-metrics.k14net.org/install-status"

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

function Log {
    param(
        [ValidateSet("INFO","SUCCESS","WARN","ERROR","HEADER")][string]$Level,
        [string]$Message
    )

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
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`" -Resume"

    $trigger = New-ScheduledTaskTrigger -AtStartup

    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Log -Level SUCCESS -Message "Resume task registered."
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

            Ensure-LocalScript

            Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`"" `
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
                -Stage "scan" `
                -Status "running" `
                -Message "Scanning for Lenovo updates" `
                -CurrentStep "Get-LSUpdate" `
                -CompletedSteps ($Round - 1) `
                -TotalSteps $MaxRounds

            $updates = @(Get-LSUpdate -Verbose)

            Log -Level INFO -Message "$($updates.Count) update(s) found."

            if ($updates.Count -eq 0) {
                Complete-Run
                return
            }

            Send-InstallStatus `
                -Stage "download" `
                -Status "running" `
                -Message "$($updates.Count) Lenovo update(s) found. Downloading packages." `
                -CurrentStep "Save-LSUpdate" `
                -CompletedSteps 0 `
                -TotalSteps $updates.Count `
                -Extra @{
                    UpdateCount = $updates.Count
                    Updates = @($updates | ForEach-Object { $_.Title })
                }

            $updates | Save-LSUpdate -Verbose

            Log -Level SUCCESS -Message "All updates downloaded."

            $i = 1

            foreach ($update in $updates) {
                Log -Level HEADER -Message "Installing [$i/$($updates.Count)]"
                Log -Level INFO -Message "$($update.Title)"

                Send-InstallStatus `
                    -Stage "install" `
                    -Status "running" `
                    -Message "Installing Lenovo update: $($update.Title)" `
                    -CurrentStep $update.Title `
                    -CompletedSteps ($i - 1) `
                    -TotalSteps $updates.Count `
                    -Extra @{
                        Round = $Round
                        UpdateTitle = $update.Title
                    }

                try {
                    Install-LSUpdate `
                        -Package $update `
                        -Verbose `
                        -SaveBIOSUpdateInfoToRegistry

                    Send-InstallStatus `
                        -Stage "install" `
                        -Status "running" `
                        -Message "Installed Lenovo update: $($update.Title)" `
                        -CurrentStep $update.Title `
                        -CompletedSteps $i `
                        -TotalSteps $updates.Count

                    Log -Level SUCCESS -Message "Installed: $($update.Title)"
                } catch {
                    Log -Level ERROR -Message "Failed installing $($update.Title): $($_.Exception.Message)"

                    Send-InstallStatus `
                        -Stage "install" `
                        -Status "failed" `
                        -Message "Failed installing Lenovo update: $($update.Title)" `
                        -CurrentStep $update.Title `
                        -CompletedSteps ($i - 1) `
                        -TotalSteps $updates.Count `
                        -Extra @{
                            Error = $_.Exception.Message
                            UpdateTitle = $update.Title
                        }
                }

                $i++
            }

            $needsReboot = Test-PendingReboot

            # Lenovo packages do not always set Windows reboot flags correctly.
            # For reliability, reboot after any batch where updates were found.
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
