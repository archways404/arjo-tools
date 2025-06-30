function Add-Printers {
    $printerList = @{
        "1" = "\\SEMA3-util-p01\SEMA3-FollowMe"
        "2" = "\\SEMA3-util-p01\SEMA3-Plot-PD"
        "3" = "\\SEMA3-util-p01\DKBAL-Print Room"
        "4" = "\\SEMA3-util-p01\NOOS2-NH8"
        "5" = "Custom"
    }

    Log -Level HEADER -Message "Available Printers"
    foreach ($key in $printerList.Keys) {
        Write-Host "$key. $($printerList[$key])" -ForegroundColor White
    }

    $choices = Read-Host "`nEnter the number(s) of printer(s) to add (comma-separated, e.g. 1,3,5)"
    $selected = $choices -split ',' | ForEach-Object { $_.Trim() }

    foreach ($option in $selected) {
        if ($printerList.ContainsKey($option)) {
            if ($printerList[$option] -eq "Custom") {
                $customPrinter = Read-Host "Enter full UNC path to printer (e.g. \\server\printer)"
                Try-AddPrinter $customPrinter
            } else {
                Try-AddPrinter $printerList[$option]
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