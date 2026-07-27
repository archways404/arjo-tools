function Add-Printers {
    $printerNames = @{
        "1" = "\\SEMA3-util-p01\SEMA3-FollowMe"
        "2" = "\\SEMA3-util-p01\SEMA3-Plot-PD"
        "3" = "\\SEMA3-util-p01\DKBAL-Print Room"
        "4" = "\\SEMA3-util-p01\NOOS2-NH8"
        "5" = "Custom"
        "6" = "Open NLTIE printers in Explorer (SAL/REP/REC)"
    }

    Log -Level HEADER -Message "Available Printers"
    foreach ($key in ($printerNames.Keys | Sort-Object {[int]$_})) {
        $label = $printerNames[$key]
        if ($label -eq "Custom") {
            Write-Host "$key. Custom (manual input)" -ForegroundColor White
        } else {
            Write-Host "$key. $label" -ForegroundColor White
        }
    }

    $choices = Read-Host "`nEnter the number(s) of printer(s) to add (comma-separated, e.g. 1,3,5)"
    $selected = $choices -split ',' | ForEach-Object { $_.Trim() }

    foreach ($option in $selected) {
        if ($printerNames.ContainsKey($option)) {
            switch ($printerNames[$option]) {
                "Custom" {
                    $customPrinter = Read-Host "Enter full UNC path to printer (e.g. \\server\printer)"
                    Try-AddPrinter $customPrinter
                }
                "Open NLTIE printers in Explorer (SAL/REP/REC)" {
                    $nltiePrinters = @(
                        "\\NLTIE-PRN-P01\SAL-MPC3002",
                        "\\NLTIE-PRN-P01\REP-MPC6501",
                        "\\NLTIE-PRN-P01\REC-MPC3502"
                    )
                    foreach ($path in $nltiePrinters) {
                        Log -Level INFO -Message "Opening in Explorer: $path"
                        Start-Process explorer.exe -ArgumentList $path
                        Start-Sleep -Seconds 2
                    }
                }
                default {
                    Try-AddPrinter $printerNames[$option]
                }
            }
        } else {
            Log -Level WARN -Message "Invalid selection: $option"
        }
    }
}

function Try-AddPrinter {
    param([string]$PrinterShare)
    $queueName = $PrinterShare.Split('\')[-1]
    $alreadyInstalled = Get-Printer |
        Where-Object {
            $_.ShareName -eq $queueName -or
            $_.Name -like "*$queueName*"
        }
    if (-not $alreadyInstalled) {
        Add-Printer -ConnectionName $PrinterShare
        Log -Level SUCCESS -Message "Printer added: $PrinterShare"
    } else {
        Log -Level INFO -Message "Printer already installed: $PrinterShare"
    }
}
