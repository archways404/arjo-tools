function Set-PowerSettings {
  $lidActionValue = 0
  $activeScheme = (powercfg /GETACTIVESCHEME).Split()[3]
  $subButtons   = '4f971e89-eebd-4455-a8de-9e59040e7347'
  $lidAction    = '5ca83367-6e45-459f-a27b-476b1d01c936'

  powercfg /SETACVALUEINDEX $activeScheme $subButtons $lidAction $lidActionValue
  powercfg /SETDCVALUEINDEX $activeScheme $subButtons $lidAction $lidActionValue
  powercfg /CHANGE -standby-timeout-ac 0
  powercfg /CHANGE -monitor-timeout-ac 0
  powercfg /SETACTIVE $activeScheme

  Log -Level SUCCESS -Message "Power settings applied (lid close = Do Nothing, AC sleep/monitor = Never)"
}