$PrinterShare = "\\SEMA3-util-p01\SEMA3-FollowMe"

if (-not (Get-Printer | Where-Object ShareName -eq $PrinterShare)) {
    Add-Printer -ConnectionName $PrinterShare
    Write-Host "[SUCCESS] Printer added: $PrinterShare"
} else {
    Write-Host "[INFO] Printer already installed."
}