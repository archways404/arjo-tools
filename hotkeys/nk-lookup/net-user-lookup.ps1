param([string]$Query)

Import-Module ActiveDirectory

if (-not $Query) {
    $Query = Read-Host "Enter username or name"
}
$Query = $Query.Trim()

# Try SamAccountName first, then DisplayName
$user = $null
try { $user = Get-ADUser -Identity $Query -Properties * } catch {}
if (-not $user) {
    $results = Get-ADUser -Filter "DisplayName -like '*$Query*'" -Properties *
    if ($results.Count -eq 1) { $user = $results }
    elseif ($results.Count -gt 1) {
        Write-Host "Multiple matches:" -ForegroundColor Yellow
        $i = 1
        foreach ($r in $results) {
            Write-Host "  [$i] $($r.SamAccountName) - $($r.DisplayName)" -ForegroundColor Cyan
            $i++
        }
        $choice = Read-Host "Select number"
        $user = $results[[int]$choice - 1]
    }
}

if (-not $user) {
    Write-Host "No user found for: $Query" -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit
}

# Password expiry
$domainPolicy = Get-ADDefaultDomainPasswordPolicy
$maxAge       = $domainPolicy.MaxPasswordAge
$pwExpiry     = $null
if ($user.PasswordNeverExpires) {
    $pwExpiry = "Never"
} elseif ($user.PasswordLastSet -and $maxAge.TotalDays -gt 0) {
    $expiryDate = $user.PasswordLastSet + $maxAge
    $daysLeft   = [math]::Round(($expiryDate - (Get-Date)).TotalDays)
    $pwExpiry   = if ($daysLeft -lt 0) {
        "EXPIRED ($([math]::Abs($daysLeft)) days ago)"
    } else {
        "$($expiryDate.ToString('yyyy-MM-dd HH:mm:ss')) ($daysLeft days left)"
    }
}

# Get full group list
$groups = $user.MemberOf | ForEach-Object {
    (Get-ADGroup -Identity $_).Name
} | Sort-Object

Write-Host ""
Write-Host "==== User Lookup: $($user.SamAccountName) ====" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Username     : $($user.SamAccountName)"      -ForegroundColor Cyan
Write-Host "  Full Name    : $($user.DisplayName)"          -ForegroundColor Cyan
Write-Host "  Email        : $($user.EmailAddress)"         -ForegroundColor Cyan
Write-Host "  Account Active: $(if ($user.Enabled) { 'Yes' } else { 'NO - DISABLED' })" -ForegroundColor $(if ($user.Enabled) { 'Cyan' } else { 'Red' })
Write-Host "  Locked Out   : $(if ($user.LockedOut) { 'YES - LOCKED' } else { 'No' })" -ForegroundColor $(if ($user.LockedOut) { 'Red' } else { 'Cyan' })
Write-Host "  Account Expires: $(if ($user.AccountExpirationDate) { $user.AccountExpirationDate } else { 'Never' })" -ForegroundColor Cyan
Write-Host "  PW Last Set  : $($user.PasswordLastSet)"      -ForegroundColor Cyan
Write-Host "  PW Expires   : $pwExpiry"                     -ForegroundColor $(if ($pwExpiry -match 'EXPIRED') { 'Red' } else { 'Cyan' })
Write-Host "  PW Required  : $(if ($user.PasswordNotRequired) { 'No' } else { 'Yes' })" -ForegroundColor Cyan
Write-Host "  PW Changeable: $(if ($user.CannotChangePassword) { 'No' } else { 'Yes' })" -ForegroundColor Cyan
Write-Host "  Last Logon   : $($user.LastLogonDate)"        -ForegroundColor Cyan
Write-Host "  Logon Hours  : All"                           -ForegroundColor Cyan
Write-Host ""
Write-Host "  ---- Group Memberships ($($groups.Count)) ----" -ForegroundColor DarkGray
foreach ($g in $groups) {
    Write-Host "    $g" -ForegroundColor Cyan
}
Write-Host ""

Read-Host "Press Enter to close"
