param (
    [string]$Query
)

Import-Module ActiveDirectory
$Query = $Query.Trim()

$properties = @(
    "DisplayName", "SamAccountName", "EmailAddress", "Department", "Title",
    "Manager", "Enabled", "LastLogonDate", "PasswordExpired", "PasswordLastSet",
    "PasswordNeverExpires", "LockedOut", "BadLogonCount", "Office", "OfficePhone",
    "MobilePhone", "City", "Country"
)

$results = Get-ADUser -Filter "DisplayName -like '*$Query*'" -Properties $properties
if (-not $results) {
    $results = Get-ADUser -Filter "SamAccountName -like '*$Query*'" -Properties $properties
}

$lines = @()

if (-not $results) {
    $lines += "==== AD Lookup: $Query ===="
    $lines += ""
    $lines += "  No results found."
} else {
    $managerDNs = $results | Where-Object { $_.Manager } | Select-Object -ExpandProperty Manager -Unique
    $managerMap = @{}
    foreach ($dn in $managerDNs) {
        try {
            $m = Get-ADUser -Identity $dn -Properties DisplayName, SamAccountName
            $managerMap[$dn] = "$($m.DisplayName) $($m.SamAccountName)"
        } catch { $managerMap[$dn] = $dn }
    }

    $domainPolicy = Get-ADDefaultDomainPasswordPolicy
    $maxAge       = $domainPolicy.MaxPasswordAge

    $lines += "==== AD Lookup: $Query ===="
    $lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    foreach ($user in $results) {
        $manager  = if ($user.Manager) { $managerMap[$user.Manager] } else { $null }
        $pwExpiry = $null

        if ($user.PasswordNeverExpires) {
            $pwExpiry = "Never expires"
        } elseif ($user.PasswordLastSet -and $maxAge.TotalDays -gt 0) {
            $expiryDate = $user.PasswordLastSet + $maxAge
            $daysLeft   = [math]::Round(($expiryDate - (Get-Date)).TotalDays)
            $pwExpiry   = if ($daysLeft -lt 0) {
                "EXPIRED ($([math]::Abs($daysLeft)) days ago)"
            } else {
                "$($expiryDate.ToString('yyyy-MM-dd')) ($daysLeft days left)"
            }
        }

        $fields = [ordered]@{
            "Name"        = $user.DisplayName
            "Username"    = $user.SamAccountName
            "Email"       = $user.EmailAddress
            "Title"       = $user.Title
            "Department"  = $user.Department
            "Manager"     = $manager
            "Office"      = $user.Office
            "Phone"       = $user.OfficePhone
            "Mobile"      = $user.MobilePhone
            "City"        = $user.City
            "Country"     = $user.Country
        }

        $statusFields = [ordered]@{
            "Enabled"     = $user.Enabled
            "Locked Out"  = if ($user.LockedOut) { "YES - LOCKED" } else { $null }
            "Bad Logons"  = if ($user.BadLogonCount -gt 0) { $user.BadLogonCount } else { $null }
            "Last Logon"  = $user.LastLogonDate
            "PW Last Set" = $user.PasswordLastSet
            "PW Expired"  = if ($user.PasswordExpired) { "YES - EXPIRED" } else { $null }
            "PW Expiry"   = $pwExpiry
        }

        $lines += ""
        $lines += "----------------------------------------"
        foreach ($key in $fields.Keys) {
            $val = $fields[$key]
            if ($val -and $val.ToString().Trim() -ne "") {
                $lines += "  $($key.PadRight(12)): $val"
            }
        }
        $lines += ""
        foreach ($key in $statusFields.Keys) {
            $val = $statusFields[$key]
            if ($val -ne $null -and $val.ToString().Trim() -ne "") {
                $lines += "  $($key.PadRight(12)): $val"
            }
        }
        $lines += "----------------------------------------"
    }
}

$lines += ""
$lines += "Press Enter to close..."

foreach ($line in $lines) {
    if     ($line -match "^====")          { Write-Host $line -ForegroundColor Magenta  }
    elseif ($line -match "^Generated")     { Write-Host $line -ForegroundColor DarkGray }
    elseif ($line -match "^--")            { Write-Host $line -ForegroundColor DarkGray }
    elseif ($line -match "LOCKED|EXPIRED") { Write-Host $line -ForegroundColor Red      }
    else                                   { Write-Host $line -ForegroundColor Cyan      }
}

Read-Host
