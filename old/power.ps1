# ------------------------------------------------------------
#  set-power.ps1  –  customise lid & AC-power behaviour
# ------------------------------------------------------------
# 0 = Do nothing | 1 = Sleep | 2 = Hibernate | 3 = Shut down
$lidActionValue = 0      # “Do nothing”

# Get GUID of the currently active power plan
$activeScheme = (powercfg /GETACTIVESCHEME).Split()[3]

# GUIDs for the “Buttons/Lid” subgroup and “Lid close action” setting
$subButtons   = '4f971e89-eebd-4455-a8de-9e59040e7347'
$lidAction    = '5ca83367-6e45-459f-a27b-476b1d01c936'

# --- 1. Lid closed  ➟  do nothing  (AC & battery) -----------------
powercfg /SETACVALUEINDEX $activeScheme $subButtons $lidAction $lidActionValue
powercfg /SETDCVALUEINDEX $activeScheme $subButtons $lidAction $lidActionValue

# --- 2. Disable sleep + screen-off when PLUGGED IN ----------------
#   0 minutes = never
powercfg /CHANGE -standby-timeout-ac 0      # system sleep
powercfg /CHANGE -monitor-timeout-ac  0      # display off

# If you also want to disable hibernate on AC:
# powercfg /SETACVALUEINDEX $activeScheme SUB_SLEEP HIBERNATEIDLE 0

# --- 3. Activate the modified scheme ------------------------------
powercfg /SETACTIVE $activeScheme

Write-Host "[SUCCESS] Lid-close is set to 'Do nothing', and AC sleep/monitor timeouts disabled."