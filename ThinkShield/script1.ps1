# ── CONFIG ──
$excelPath  = "$env:USERPROFILE\OneDrive - Arjo\RET-SYS1.xlsx"
$sheetName  = "Sheet1"
$systemName = $env:COMPUTERNAME
$greenRGB   = 5296274
$checkSecs  = 60
# ────────────

$xl = New-Object -ComObject Excel.Application
$xl.Visible,$xl.DisplayAlerts = $false,$false

try {
    $wb = $xl.Workbooks.Open($excelPath)
    $ws = $wb.Worksheets.Item($sheetName)

    # Find / append system name
    $last = $ws.Cells($ws.Rows.Count,1).End(-4162).Row
    if ($last -lt 2) { $last = 1 }
    $row = 2
    for (; $row -le $last; $row++) {
        if ($ws.Cells.Item($row,1).Value2 -eq $systemName) { break }
    }
    if ($row -gt $last) {
        $row = $last + 1
        $ws.Cells.Item($row,1).Value2 = $systemName
        Write-Host "Inserted $systemName in A$row"
    } else {
        Write-Host "$systemName already present on row $row"
    }

    # Wait for ≥50 % battery
    while ((Get-CimInstance Win32_Battery).EstimatedChargeRemaining -lt 50) {
        Start-Sleep $checkSecs
    }
    $ws.Cells.Item($row,1).Interior.Color = $greenRGB
    Write-Host "Battery ≥50 % — cell coloured green"

    # Save & close
    $wb.Save()
    $wb.Close(0)    # close without further prompts
    $xl.Quit()
}
finally {
    # FULL release in reverse order
    foreach ($o in @($ws,$wb,$xl)) {
        if ($null -ne $o) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) }
    }
    $ws=$wb=$xl=$null
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

# Wait until Excel and lock file are gone
while (Get-Process excel -ErrorAction SilentlyContinue) { Start-Sleep 1 }
$lock = Join-Path (Split-Path $excelPath -Parent) ("~$" + (Split-Path $excelPath -Leaf))
while (Test-Path $lock) { Start-Sleep 1 }

# Nudge OneDrive
(Get-Item $excelPath).LastWriteTime = Get-Date
Write-Host "Excel closed, lock cleared — OneDrive will sync now."