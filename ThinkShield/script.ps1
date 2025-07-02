# ────────── CONFIG ──────────
$excelPath  = "$env:USERPROFILE\OneDrive - Arjo\RET-SYS.xlsx"
$sheetName  = "Sheet1"
$systemName = $env:COMPUTERNAME
$greenRGB   = 5296274                 # #92D050
$checkSecs  = 60                      # battery poll interval
# ────────────────────────────

# 1️⃣  Launch Excel head-less
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false

try {
    $wb = $xl.Workbooks.Open($excelPath)
    $ws = $wb.Worksheets.Item($sheetName)

    # 2️⃣  Locate last used row in col A
    $lastRow = $ws.Cells($ws.Rows.Count,1).End(-4162).Row
    if ($lastRow -lt 2) { $lastRow = 1 }

    # 3️⃣  Insert system name if missing
    $rowToUse = $null
    for ($r=2; $r -le $lastRow; $r++) {
        if ($ws.Cells.Item($r,1).Value2 -eq $systemName) { $rowToUse = $r; break }
    }
    if (-not $rowToUse) {
        $rowToUse = $lastRow + 1
        $ws.Cells.Item($rowToUse,1).Value2 = $systemName
        Write-Host "Inserted [$systemName] in A$rowToUse"
    } else {
        Write-Host "[$systemName] already in row $rowToUse"
    }

    # 4️⃣  Wait until battery ≥ 50 %
    while ($true) {
        $bat = Get-CimInstance Win32_Battery
        if ($bat.EstimatedChargeRemaining -ge 50) {
            Write-Host "Battery at $($bat.EstimatedChargeRemaining)% – colouring A$rowToUse green"
            $ws.Cells.Item($rowToUse,1).Interior.Color = $greenRGB
            break
        }
        Write-Host "Battery $($bat.EstimatedChargeRemaining)% – waiting…" -NoNewline; Start-Sleep $checkSecs
        Write-Host "`r`n"
    }

    # 5️⃣  Save & close
    $wb.Save()
    $wb.Close($true)
}
finally {
    # clean COM
    foreach ($o in @($ws,$wb,$xl)) { if ($o) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) } }
    Remove-Variable ws,wb,xl -ErrorAction SilentlyContinue
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

# 6️⃣  Nudge OneDrive
(Get-Item $excelPath).LastWriteTime = Get-Date
Start-Sleep 3
Write-Host "Done – OneDrive will sync; watch for blue arrows ➜ green check."