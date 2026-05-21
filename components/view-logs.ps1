# ==============================================================================
# View LSUClient Logs
# ==============================================================================

if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log {
        param (
            [ValidateSet("INFO","SUCCESS","WARN","ERROR","HEADER")][string]$Level,
            [string]$Message
        )
        $map = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; HEADER="Magenta" }
        if ($Level -eq "HEADER") { Write-Host "`n==== $Message ====" -ForegroundColor $map[$Level]; return }
        $prefix = "[$(($Level).PadRight(7))]"
        Write-Host "$prefix $Message" -ForegroundColor $map[$Level]
    }
}

function Show-LenovoLogs {
    $logs = Get-ChildItem "$env:TEMP\lsuclient_*.log" | Sort-Object LastWriteTime -Descending

    if ($logs.Count -eq 0) {
        Log -Level WARN -Message "No LSUClient logs found in $env:TEMP"
        return
    }

    Write-Host ""
    Write-Host "  Found $($logs.Count) log file(s):" -ForegroundColor Cyan
    Write-Host ""

    for ($i = 0; $i -lt $logs.Count; $i++) {
        $num  = $i + 1
        $log  = $logs[$i]
        $size = "{0:N1} KB" -f ($log.Length / 1KB)
        Write-Host ("  [{0}] {1,-45} {2,10}   {3}" -f $num, $log.Name, $size, $log.LastWriteTime) -ForegroundColor White
    }

    Write-Host ""
    Write-Host "  [0] Back" -ForegroundColor DarkGray
    Write-Host ""

    $input = Read-Host "  Select a log to view"

    if ($input -notmatch '^\d+$') { Log -Level WARN -Message "Invalid input."; return }

    $choice = [int]$input
    if ($choice -eq 0) { return }

    if ($choice -ge 1 -and $choice -le $logs.Count) {
        $selected = $logs[$choice - 1]
        Log -Level HEADER -Message $selected.Name
        Write-Host ""
        Get-Content $selected.FullName | ForEach-Object { Write-Host $_ }
        Write-Host ""
        Log -Level INFO -Message "Full path: $($selected.FullName)"
    } else {
        Log -Level WARN -Message "Choice out of range."
    }
}
