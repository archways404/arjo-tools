# ==============================================================================
# Local Admin Audit — AD Group Members
# ==============================================================================
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
        [Parameter(Mandatory)][string]$GroupName
    )
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Log -Level ERROR -Message "ActiveDirectory module not found. Install RSAT."
        return
    }
    Import-Module ActiveDirectory
    Log -Level INFO -Message "Fetching members of AD group: $GroupName"
    try {
        $groupMembers = Get-ADGroupMember -Identity $GroupName -Recursive |
            Where-Object { $_.objectClass -eq "user" }
    } catch {
        Log -Level ERROR -Message "Could not find group: $_"
        return
    }
    if ($groupMembers.Count -eq 0) {
        Log -Level WARN -Message "Group has no members."
        return
    }
    Log -Level INFO -Message "$($groupMembers.Count) user(s) found in group."
    $samAccounts = $groupMembers.SamAccountName
    Log -Level INFO -Message "Fetching domain computers..."
    $computers = Get-ADComputer -Filter * -SearchBase "OU=Computers,OU=SEMA3,OU=Sites,DC=ARJO,DC=LOCAL" |
        Select-Object -ExpandProperty Name
    Log -Level INFO -Message "$($computers.Count) computer(s) found."
    Log -Level HEADER -Message "Scanning machines"

    $scanned     = 0
    $unreachable = 0
    $matches     = @()
    $total = $computers.Count
    $i     = 0

    foreach ($computer in $computers) {
        $i++
        Log -Level INFO -Message "[$i/$total] $computer"

        if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
            $unreachable++
            Log -Level WARN -Message "$computer - offline (ping failed)"
            continue
        }

        try {
            $group = [ADSI]"WinNT://$computer/Administrators,group"
            $localAdmins = $group.Members() | ForEach-Object {
                $_.GetType().InvokeMember("Name", "GetProperty", $null, $_, $null)
            }
            $scanned++
            foreach ($sam in $samAccounts) {
                if ($localAdmins -contains $sam) {
                    Log -Level SUCCESS -Message "- - - - - -> $sam has local admin on: $computer"
                    $matches += [PSCustomObject]@{ User = $sam; Computer = $computer }
                }
            }
        } catch {
            $unreachable++
            Log -Level ERROR -Message "$computer - unreachable or access denied"
        }
    }

    Log -Level HEADER -Message "Scan Summary"
    Log -Level INFO -Message "Total computers : $($computers.Count)"
    Log -Level INFO -Message "Scanned         : $scanned"
    Log -Level ERROR -Message "Unreachable     : $unreachable"
    Log -Level INFO -Message "Coverage        : $([math]::Round(($scanned / $computers.Count) * 100, 1))%"

    if ($matches.Count -eq 0) {
        Log -Level SUCCESS -Message "No local admins found among group members."
    } else {
        Log -Level WARN -Message "$($matches.Count) match(es) found:"
        $matches | ForEach-Object {
            Log -Level WARN -Message "  $($_.User) -> $($_.Computer)"
        }
    }
}

function Show-GroupMenu {
    Write-Host ""
    Write-Host "==== Select AD Group ====" -ForegroundColor Magenta
    Write-Host "[1] SCG-SEMA3-SEMA3-Users"
    Write-Host "[2] Manual input"
    Write-Host ""

    do {
        $choice = Read-Host "Enter choice (1-2)"
    } while ($choice -notin @("1", "2"))

    switch ($choice) {
        "1" { return "SCG-SEMA3-SEMA3-Users" }
        "2" { return Read-Host "Enter AD group name" }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $group = Show-GroupMenu
    Get-LocalAdminGroupMembers -GroupName $group
}
