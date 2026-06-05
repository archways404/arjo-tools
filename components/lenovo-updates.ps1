# ==============================================================================
# Lenovo System Updates — LSUClient auto-resume after reboot
# ==============================================================================

param(
    [switch]$Resume
)

$ScriptUrl       = "https://raw.githubusercontent.com/archways404/arjo-tools/master/components/lenovo-updates.ps1"
$BaseDir         = "C:\ProgramData\ArjoTools"
$LocalScriptPath = Join-Path $BaseDir "lenovo-updates.ps1"
$LogDir          = Join-Path $BaseDir "Logs"
$TaskName        = "Arjo Lenovo Updates Resume"
$CompletedFile   = Join-Path $BaseDir "LenovoUpdatesCompleted.txt"

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

function Stop-Logging {
    try { Stop-Transcript | Out-Null } catch {}
}

function Test-IsSystem {
    return ([Security.Principal.WindowsIdentity]::GetCurrent().Name -eq "NT AUTHORITY\SYSTEM")
}

function Test-IsAdmin {
    if (Test-IsSystem) { return $true }

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

        if ($pending.PendingFileRenameOperations) { return $true }
    } catch {}

    return $false
}

function Ensure-Folders {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Ensure-LocalScript {
    Ensure-Folders

    Log -Level INFO -Message "Downloading latest script to: $LocalScriptPath"
    Invoke-WebRequest -Uri $ScriptUrl -OutFile $LocalScriptPath -UseBasicParsing -ErrorAction Stop
    Log -Level SUCCESS -Message "Local script updated."
}

function Register-ResumeTask {
    Log -Level INFO -Message "Registering startup resume task: $TaskName"

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
    } else {
        Log -Level INFO -Message "No scheduled task found to remove."
    }
}

function Ensure-LSUClient {
    Log -Level INFO -Message "Preparing PowerShell Gallery / NuGet / LSUClient..."

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
        Log -Level ERROR -Message "Failed to install LSUClient: $($_.Exception.Message)"
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

    if (-not (Test-IsAdmin)) {
        Log -Level WARN -Message "Not running elevated. Relaunching as admin..."

        Ensure-LocalScript

        Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`"" `
            -Verb RunAs

        Log -Level INFO -Message "Elevated window launched. Closing this unelevated run."
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

        try {
            $updates = @(Get-LSUpdate -Verbose)
        } catch {
            Log -Level ERROR -Message "Get-LSUpdate failed: $($_.Exception.Message)"
            Stop-Logging
            throw
        }

        Log -Level INFO -Message "$($updates.Count) update(s) found."

        if ($updates.Count -eq 0) {
            Complete-Run
            return
        }

        foreach ($u in $updates) {
            Log -Level INFO -Message "Update found: $($u.Title)"
        }

        try {
            Log -Level INFO -Message "Downloading all updates before installing..."
            $updates | Save-LSUpdate -Verbose
            Log -Level SUCCESS -Message "All updates downloaded."
        } catch {
            Log -Level ERROR -Message "Save-LSUpdate failed: $($_.Exception.Message)"
            Stop-Logging
            throw
        }

        $i = 1

        foreach ($update in $updates) {
            Log -Level HEADER -Message "Installing [$i/$($updates.Count)]"
            Log -Level INFO -Message "$($update.Title)"

            try {
                Install-LSUpdate `
                    -Package $update `
                    -Verbose `
                    -SaveBIOSUpdateInfoToRegistry

                Log -Level SUCCESS -Message "Installed: $($update.Title)"
            } catch {
                Log -Level ERROR -Message "Failed installing $($update.Title): $($_.Exception.Message)"
            }

            $i++
        }

        if (Test-PendingReboot) {
            Log -Level WARN -Message "Pending reboot detected. Rebooting in 30 seconds. Script will resume at startup."
            Stop-Logging
            Start-Sleep -Seconds 30
            Restart-Computer -Force
            return
        }

        Log -Level INFO -Message "No pending reboot detected after round $Round."
    }

    Log -Level WARN -Message "Max rounds reached. Re-checking update state."

    try {
        $remaining = @(Get-LSUpdate)
    } catch {
        Log -Level ERROR -Message "Final Get-LSUpdate failed: $($_.Exception.Message)"
        Stop-Logging
        throw
    }

    if ($remaining.Count -eq 0) {
        Complete-Run
        return
    }

    Log -Level WARN -Message "$($remaining.Count) update(s) still remain after max rounds."
    Log -Level WARN -Message "Scheduled task will remain so the script can retry after next startup."
    Stop-Logging
}

Start-LenovoUpdates
