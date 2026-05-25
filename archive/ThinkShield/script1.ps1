# ── CONFIG ──
$excelPath  = "$env:USERPROFILE\OneDrive - Arjo\RET-SYS.xlsx"
$sheetName  = "Sheet1"
$systemName = $env:COMPUTERNAME
$greenRGB   = 5296274
$checkSecs  = 60
# ────────────

# Capture existing Excel PIDs before launching Excel
$preExcel = (Get-Process excel -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

# Launch Excel
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false

try {
  $wb = $xl.Workbooks.Open($excelPath)
  $ws = $wb.Worksheets.Item($sheetName)

  # Find last used row
  $last = $ws.Cells($ws.Rows.Count,2).End(-4162).Row
  if ($last -lt 2) { $last = 1 }

  # Find or insert computer name in column B
  $row = 2
  for (; $row -le $last; $row++) {
      if ($ws.Cells.Item($row,2).Value2 -eq $systemName) { break }
  }
  if ($row -gt $last) {
      $row = $last + 1
      $ws.Cells.Item($row,2).Value2 = $systemName
      Write-Host "Inserted $systemName at B$row"
  } else {
      Write-Host "$systemName already exists at B$row"
  }

  # Wait for battery ≥ 50 %
  while ((Get-CimInstance Win32_Battery).EstimatedChargeRemaining -lt 50) {
      Start-Sleep $checkSecs
  }

  # Color the B cell green
  $ws.Cells.Item($row,2).Interior.Color = $greenRGB
  Write-Host "Battery ≥50% – cell B$row coloured green"

  $wb.Save()
  $wb.Close(0)
  $xl.Quit()
}
finally {
    foreach ($o in @($ws,$wb,$xl)) {
        if ($o) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) }
    }
    $ws=$wb=$xl=$null
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

# Wait for our Excel instance to fully exit
do {
    $nowExcel = (Get-Process excel -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $ourExcel = $nowExcel | Where-Object { $_ -notin $preExcel }
    Start-Sleep 1
} while ($ourExcel)

# Wait for lock file (optional but fast)
$lock = Join-Path (Split-Path $excelPath -Parent) ("~$" + (Split-Path $excelPath -Leaf))
while (Test-Path $lock) { Start-Sleep 1 }

# Nudge OneDrive
(Get-Item $excelPath).LastWriteTime = Get-Date
Start-Sleep 3
Write-Host "Done – OneDrive syncing."