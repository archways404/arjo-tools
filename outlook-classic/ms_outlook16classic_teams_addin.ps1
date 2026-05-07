# ==============================================================================
# Fix-TeamsAddin.ps1
# Purpose : Re-enables the Microsoft Teams Meeting Add-in for Outlook (Classic)
#           when it has been marked as Inactive or crash-disabled by Outlook.
# Affects : HKCU registry only (current user, no admin rights required)
# Safe to re-run multiple times - all operations are idempotent
# ==============================================================================

# Trap CTRL+C so the user sees a clean cancellation message instead of an abrupt exit
$null = [Console]::TreatControlCAsInput = $false
trap {
    Write-Host ""
    Write-Host ""
    Write-Host "  Script cancelled by user (CTRL+C). No further changes will be made." -ForegroundColor Red
    Write-Host "  Outlook has NOT been restarted." -ForegroundColor Red
    Write-Host ""
    exit
}

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Teams Add-in Re-enabler for Outlook  " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Press CTRL+C at any time to cancel.  " -ForegroundColor DarkGray
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# ==============================================================================
# STEP 1 — Fix LoadBehavior registry value
# ------------------------------------------------------------------------------
# Outlook stores each COM add-in under HKCU:\...\Outlook\Addins\<ProgID>.
# The LoadBehavior DWORD controls whether the add-in loads at startup:
#   0 = Disconnected (disabled)
#   2 = Load on demand
#   3 = Load at startup and connect (this is what we want)
#   8 = Load once at next launch, then revert to on-demand
#
# When a user manually marks an add-in as Inactive via Outlook Options, or when
# Outlook decides to deactivate it, this value gets set to something other than 3.
# Setting it back to 3 is what moves it from "Inactive" back to "Active".
# ==============================================================================
Write-Host "[1/3] Checking Teams add-in registry key..." -ForegroundColor White

$addinPath = "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"

if (Test-Path $addinPath) {
    $currentLoad = (Get-ItemProperty -Path $addinPath).LoadBehavior
    Write-Host "      Registry key found." -ForegroundColor Gray
    Write-Host "      Current LoadBehavior value: $currentLoad" -ForegroundColor Gray

    if ($currentLoad -ne 3) {
        Set-ItemProperty -Path $addinPath -Name "LoadBehavior" -Value 3
        Write-Host "      LoadBehavior updated to 3 (load at startup)." -ForegroundColor Green
    } else {
        Write-Host "      LoadBehavior is already 3 - no change needed." -ForegroundColor Green
    }
} else {
    # This key should always exist if Teams is properly installed.
    # If it's missing, the Teams installer likely didn't run correctly for this user profile.
    Write-Host ""
    Write-Host "  WARNING: Teams add-in registry key not found at:" -ForegroundColor Yellow
    Write-Host "  $addinPath" -ForegroundColor Yellow
    Write-Host "  This usually means Teams needs to be repaired or reinstalled." -ForegroundColor Yellow
    Write-Host "  Continuing with resiliency cleanup anyway..." -ForegroundColor Yellow
    Write-Host ""
}

# ==============================================================================
# STEP 2 — Clear Outlook resiliency / crash-disabled data
# ------------------------------------------------------------------------------
# Outlook has a self-protection mechanism: if an add-in causes a crash or takes
# too long to load, Outlook automatically disables it and records it under the
# Resiliency key. This is separate from the LoadBehavior value above.
#
# DisabledItems  : Binary-encoded list of add-ins Outlook has force-disabled.
#                  Deleting this key clears all crash-disabled add-ins at once.
#
# DoNotDisableAddinList : Add-ins listed here are exempted from the auto-disable
#                         mechanism going forward. Adding Teams here prevents
#                         Outlook from disabling it again after future hiccups.
# ==============================================================================
Write-Host ""
Write-Host "[2/3] Clearing Outlook resiliency / crash-disabled data..." -ForegroundColor White

# --- Clear the DisabledItems list ---
$disabledItemsPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems"

if (Test-Path $disabledItemsPath) {
    Remove-Item $disabledItemsPath -Force -ErrorAction SilentlyContinue
    Write-Host "      Disabled items list found and cleared." -ForegroundColor Green
} else {
    Write-Host "      No disabled items list found (nothing to clear)." -ForegroundColor Gray
}

# --- Add Teams to the DoNotDisableAddinList ---
$doNotDisablePath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList"

# Create the parent key if it doesn't exist yet
if (-not (Test-Path $doNotDisablePath)) {
    New-Item -Path $doNotDisablePath -Force | Out-Null
    Write-Host "      DoNotDisableAddinList key created." -ForegroundColor Gray
}

# Only write if the value isn't already set correctly
$existingEntry = (Get-ItemProperty -Path $doNotDisablePath -ErrorAction SilentlyContinue)."TeamsAddin.FastConnect"
if ($existingEntry -eq 1) {
    Write-Host "      Teams is already on the never-auto-disable list." -ForegroundColor Gray
} else {
    Set-ItemProperty -Path $doNotDisablePath -Name "TeamsAddin.FastConnect" -Value 1 -Type DWord
    Write-Host "      Teams added to the never-auto-disable list." -ForegroundColor Green
}

# ==============================================================================
# STEP 3 — Restart Outlook
# ------------------------------------------------------------------------------
# Registry changes to add-in LoadBehavior and resiliency keys only take effect
# when Outlook is (re)started. We give the user 30 seconds to save their work
# and close Outlook themselves before we force-close it.
#
# The countdown loop also watches for the user closing Outlook manually mid-
# countdown so we don't have to wait the full 30 seconds in that case.
#
# CTRL+C at any point in this section will trigger the trap at the top of the
# script and exit cleanly without restarting Outlook.
# ==============================================================================
Write-Host ""
Write-Host "[3/3] Outlook needs to be restarted for the changes to take effect." -ForegroundColor White
Write-Host ""

$outlookProcess = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue

if ($outlookProcess) {
    Write-Host "  Outlook is currently open." -ForegroundColor Yellow
    Write-Host "  Please save your work and close it manually," -ForegroundColor Yellow
    Write-Host "  or it will be force-closed automatically in 30 seconds." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Press CTRL+C to cancel and leave Outlook open." -ForegroundColor DarkGray
    Write-Host ""

    $userClosedManually = $false

    for ($i = 30; $i -ge 1; $i--) {
        Write-Host "`r  Auto-closing in $i second(s)...   " -NoNewline -ForegroundColor Yellow

        # Check each second whether the user has already closed Outlook themselves
        if (-not (Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue)) {
            Write-Host ""
            Write-Host ""
            Write-Host "  Outlook was closed manually - continuing." -ForegroundColor Green
            $userClosedManually = $true
            break
        }

        Start-Sleep -Seconds 1
    }

    # If Outlook is still running after the countdown, force-close it
    if (-not $userClosedManually) {
        Write-Host ""
        Write-Host ""
        Write-Host "  Force-closing Outlook now..." -ForegroundColor Yellow
        Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue | Stop-Process -Force

        # Brief pause to ensure the process and its file locks are fully released
        Start-Sleep -Seconds 2
        Write-Host "  Outlook closed." -ForegroundColor Green
    }

} else {
    Write-Host "  Outlook is not currently running." -ForegroundColor Gray
}

# Launch Outlook fresh
Write-Host ""
Write-Host "  Starting Outlook..." -ForegroundColor White
Start-Process "C:\Program Files\Microsoft Office\root\Office16\outlook.exe"
Write-Host "  Outlook launched." -ForegroundColor Green

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Done! The Teams add-in should now    " -ForegroundColor Cyan
Write-Host "  appear as active when Outlook loads. " -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
