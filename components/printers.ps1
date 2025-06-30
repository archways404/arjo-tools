function Add-Printers {
    $printerPrefix = "\\SEMA3-util-p01\"

    $printerNames = @{
        "1" = "SEMA3-FollowMe"
        "2" = "SEMA3-Plot-PD"
        "3" = "DKBAL-Print Room"
        "4" = "NOOS2-NH8"
        "5" = "Custom"
    }

    Log -Level HEADER -Message "Available Printers"
    foreach ($key in ($printerNames.Keys | Sort-Object {[int]$_})) {
        $label = $printerNames[$key]
        if ($label -ne "Custom") {
            Write-Host "$key. $label" -ForegroundColor White
        } else {
            Write-Host "$key. Custom (manual input)" -ForegroundColor White
        }
    }

    $choices = Read-Host "`nEnter the number(s) of printer(s) to add (comma-separated, e.g. 1,3,5)"
    $selected = $choices -split ',' | ForEach-Object { $_.Trim() }

    foreach ($option in $selected) {
        if ($printerNames.ContainsKey($option)) {
            if ($printerNames[$option] -eq "Custom") {
                $customPrinter = Read-Host "Enter full UNC path to printer (e.g. \\server\printer)"
                Try-AddPrinter $customPrinter
            } else {
                $fullShare = "$printerPrefix$($printerNames[$option])"
                Try-AddPrinter $fullShare
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