# ==============================================================================
# Local Admin Audit — Continuous Monitor
# ==============================================================================
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Relaunching in PowerShell 7..." -ForegroundColor Yellow
    pwsh -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit
}

$VERBOSE      = $true                                                   # Set to $false to reduce output
$TARGET_GROUP = "SCG-SEMA3-SEMA3-Users"                                 # The AD Group to filter from
$TARGET_OU    = "OU=Computers,OU=SEMA3,OU=Sites,DC=ARJO,DC=LOCAL"       # Target OU

if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param (
            [ValidateSet("INFO","SUCCESS","WARN","ERROR","HEADER")][string]$Level,
            [string]$Message
        )
        $map = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; HEADER="Magenta" }
        if ($Level -eq "HEADER") { Write-Host "`n==== $Message ====" -ForegroundColor $map[$Level]; return }
        $prefix = "[$(($Level).PadRight(7))]"
        Write-Host "$prefix $Message" -ForegroundColor $map[$Level]
    }
}

function Get-LocalAdminGroupMembers {
    param (
        [Parameter(Mandatory)][string]$GroupName,
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][string]$CleanFile,
        [Parameter(Mandatory)][string]$CheckpointFile
    )

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Log -Level ERROR -Message "ActiveDirectory module not found. Install RSAT."
        return
    }
    Import-Module ActiveDirectory

    # ------------------------------------------------------------------
    # Fetch group members
    # ------------------------------------------------------------------
    Log -Level INFO -Message "Fetching members of AD group: $GroupName"
    try {
        $groupMembers = Get-ADGroupMember -Identity $GroupName -Recursive |
            Where-Object { $_.objectClass -eq "user" } |
            ForEach-Object { Get-ADUser -Identity $_.SamAccountName -Properties DisplayName, SamAccountName }
    } catch {
        Log -Level ERROR -Message "Could not find group: $_"
        return
    }

    if ($groupMembers.Count -eq 0) {
        Log -Level WARN -Message "Group has no members."
        return
    }

    $userLookup = @{}
    foreach ($u in $groupMembers) {
        $userLookup[$u.SamAccountName] = $u.DisplayName
    }
    $samAccounts = @($userLookup.Keys)
    Log -Level INFO -Message "$($samAccounts.Count) user(s) found in group."

    # ------------------------------------------------------------------
    # Fetch computers
    # ------------------------------------------------------------------
    Log -Level INFO -Message "Fetching domain computers..."
    $allComputers = Get-ADComputer -Filter * -SearchBase $TARGET_OU |
        Select-Object -ExpandProperty Name
    Log -Level INFO -Message "$($allComputers.Count) computer(s) found."

    # ------------------------------------------------------------------
    # Load checkpoint
    # ------------------------------------------------------------------
    $checkedClean = [System.Collections.Generic.HashSet[string]]::new()
    if (Test-Path $CheckpointFile) {
        Get-Content $CheckpointFile | ForEach-Object {
            $trimmed = $_.Trim()
            if ($trimmed -ne "") { $null = $checkedClean.Add($trimmed) }
        }
        Log -Level INFO -Message "Checkpoint loaded: $($checkedClean.Count) already-clean computer(s) skipped."
    }

    $pending = [System.Collections.Generic.List[string]](
        $allComputers | Where-Object { -not $checkedClean.Contains($_) }
    )
    Log -Level INFO -Message "$($pending.Count) computer(s) remaining after checkpoint."

    $mutex    = New-Object System.Threading.Mutex($false, "LocalAdminAuditMutex")
    $rotation = 0

    while ($true) {
        $rotation++
        $rotationTotal = $pending.Count
        Log -Level HEADER -Message "Rotation $rotation - $rotationTotal computer(s) to scan"

        $completed = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
        $logQueue  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

        $job = $pending | ForEach-Object -Parallel {
            $computer       = $_
            $userLookup     = $using:userLookup
            $samAccounts    = $using:samAccounts
            $OutputFile     = $using:OutputFile
            $CleanFile      = $using:CleanFile
            $CheckpointFile = $using:CheckpointFile
            $mutex          = $using:mutex
            $completed      = $using:completed
            $logQueue       = $using:logQueue
            $verbose        = $using:VERBOSE
            $total          = $using:rotationTotal

            $result = [PSCustomObject]@{
                Computer  = $computer
                Reachable = $false
                Matches   = @()
                Clean     = $false
                Error     = $null
            }

            if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
                $result.Error = "offline"
                $null = $completed.Add(1)
                $count = $completed.Count
                if ($verbose) { $logQueue.Enqueue("WARN|$computer - offline ($count/$total)") }
                $logQueue.Enqueue("PROGRESS|$count|$total")
                return $result
            }

            try {
                $group       = [ADSI]"WinNT://$computer/Administrators,group"
                $localAdmins = $group.Members() | ForEach-Object {
                    $_.GetType().InvokeMember("Name", "GetProperty", $null, $_, $null)
                }
                $result.Reachable = $true
                $foundMatch = $false

                foreach ($sam in $samAccounts) {
                    if ($localAdmins -contains $sam) {
                        $line = "$($userLookup[$sam]) $sam -> $computer"
                        $result.Matches += $line
                        $foundMatch = $true
                        $logQueue.Enqueue("SUCCESS|MATCH: $line")

                        $null = $mutex.WaitOne()
                        try {
                            $existing = @()
                            if (Test-Path $OutputFile) { $existing = Get-Content $OutputFile }
                            if ($existing -notcontains $line) {
                                Add-Content -Path $OutputFile -Value $line
                            }
                        } finally {
                            $mutex.ReleaseMutex()
                        }
                    }
                }

                if (-not $foundMatch) {
                    $result.Clean = $true
                    if ($verbose) { $logQueue.Enqueue("INFO|$computer - clean") }

                    $null = $mutex.WaitOne()
                    try {
                        $existingClean = @()
                        if (Test-Path $CleanFile) { $existingClean = Get-Content $CleanFile }
                        if ($existingClean -notcontains $computer) {
                            Add-Content -Path $CleanFile      -Value $computer
                            Add-Content -Path $CheckpointFile -Value $computer
                        }
                    } finally {
                        $mutex.ReleaseMutex()
                    }
                }
            } catch {
                $result.Error = $_.ToString()
                $logQueue.Enqueue("ERROR|$computer - $($_.ToString())")
            }

            $null = $completed.Add(1)
            $count = $completed.Count
            $logQueue.Enqueue("PROGRESS|$count|$total")
            return $result

        } -ThrottleLimit 20 -AsJob

        # ------------------------------------------------------------------
        # Drain log queue while job runs
        # ------------------------------------------------------------------
        while ($job.State -eq 'Running') {
            $msg = $null
            while ($logQueue.TryDequeue([ref]$msg)) {
                $parts = $msg -split '\|', 2
                switch ($parts[0]) {
                    'PROGRESS' {
                        $p      = $msg -split '\|'
                        $count  = [int]$p[1]
                        $total  = [int]$p[2]
                        $pct    = if ($total -gt 0) { [math]::Round(($count / $total) * 100) } else { 0 }
                        $filled = [math]::Round($pct / 2)
                        $empty  = 50 - $filled
                        $bar    = "#" * $filled + "-" * $empty
                        Write-Host "`r  [$bar] $pct% ($count/$total) scanning...   " -NoNewline -ForegroundColor Cyan
                    }
                    'SUCCESS' { Write-Host ""; Log -Level SUCCESS -Message $parts[1] }
                    'WARN'    { Write-Host ""; Log -Level WARN    -Message $parts[1] }
                    'ERROR'   { Write-Host ""; Log -Level ERROR   -Message $parts[1] }
                    'INFO'    { Write-Host ""; Log -Level INFO    -Message $parts[1] }
                }
                $msg = $null
            }
            Start-Sleep -Milliseconds 150
        }

        # Drain remaining messages after job finishes
        $msg = $null
        while ($logQueue.TryDequeue([ref]$msg)) {
            $parts = $msg -split '\|', 2
            switch ($parts[0]) {
                'PROGRESS' {
                    $p      = $msg -split '\|'
                    $count  = [int]$p[1]
                    $total  = [int]$p[2]
                    $pct    = if ($total -gt 0) { [math]::Round(($count / $total) * 100) } else { 0 }
                    $filled = [math]::Round($pct / 2)
                    $empty  = 50 - $filled
                    $bar    = "#" * $filled + "-" * $empty
                    Write-Host "`r  [$bar] $pct% ($count/$total) scanning...   " -NoNewline -ForegroundColor Cyan
                }
                'SUCCESS' { Write-Host ""; Log -Level SUCCESS -Message $parts[1] }
                'WARN'    { Write-Host ""; Log -Level WARN    -Message $parts[1] }
                'ERROR'   { Write-Host ""; Log -Level ERROR   -Message $parts[1] }
                'INFO'    { Write-Host ""; Log -Level INFO    -Message $parts[1] }
            }
            $msg = $null
        }

        Write-Host ""
        $results = $job | Receive-Job
        $job | Remove-Job
        Log -Level INFO -Message "Scan complete, processing $($results.Count) results..."

        # ------------------------------------------------------------------
        # Process results
        # ------------------------------------------------------------------
        $stillPending = [System.Collections.Generic.List[string]]::new()
        $scanned      = 0
        $unreachable  = 0
        $matchCount   = 0
        $cleanCount   = 0

        foreach ($r in $results) {
            if ($r.Reachable) {
                $scanned++
                if ($r.Clean)          { $cleanCount++ }
                $matchCount += $r.Matches.Count
            } else {
                $unreachable++
                $stillPending.Add($r.Computer)
            }
        }

        Write-Host ""
        Log -Level HEADER -Message "Rotation $rotation Summary"
        Log -Level INFO    -Message "Scanned      : $scanned"
        Log -Level SUCCESS -Message "Clean        : $cleanCount"
        Log -Level SUCCESS -Message "Matches      : $matchCount"
        Log -Level WARN    -Message "Unreachable  : $unreachable"
        Log -Level INFO    -Message "Still pending: $($stillPending.Count)"

        if ($stillPending.Count -eq 0) {
            Log -Level SUCCESS -Message "All computers scanned. Clearing checkpoint and resetting."
            Clear-Content -Path $CheckpointFile -ErrorAction SilentlyContinue
            $checkedClean.Clear()
            $pending = [System.Collections.Generic.List[string]]($allComputers)
        } else {
            $pending = $stillPending
        }

        Log -Level INFO -Message "Waiting 5 minutes before next rotation..."
        Start-Sleep -Seconds 300
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $outputFile     = Join-Path $PSScriptRoot "local-adm.txt"
    $cleanFile      = Join-Path $PSScriptRoot "local-adm-clean.txt"
    $checkpointFile = Join-Path $PSScriptRoot "local-adm-checkpoint.txt"
    Log -Level INFO -Message "Group           : $TARGET_GROUP"
    Log -Level INFO -Message "Matches file    : $outputFile"
    Log -Level INFO -Message "Clean file      : $cleanFile"
    Log -Level INFO -Message "Checkpoint file : $checkpointFile"
    Get-LocalAdminGroupMembers -GroupName $TARGET_GROUP -OutputFile $outputFile -CleanFile $cleanFile -CheckpointFile $checkpointFile
}
