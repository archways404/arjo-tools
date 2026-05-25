$startupFolder = [System.Environment]::GetFolderPath("Startup")
$rootDir       = $PSScriptRoot
$wsh           = New-Object -ComObject WScript.Shell

$ahkFiles = Get-ChildItem -Path $rootDir -Filter "*.ahk" -Recurse

if ($ahkFiles.Count -eq 0) {
    Write-Host "[WARN] No .ahk files found." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit
}

foreach ($ahk in $ahkFiles) {
    $shortcut                  = $wsh.CreateShortcut((Join-Path $startupFolder "$($ahk.BaseName).lnk"))
    $shortcut.TargetPath       = $ahk.FullName
    $shortcut.WorkingDirectory = $ahk.DirectoryName
    $shortcut.Save()
    Write-Host "[SUCCESS] Shortcut: $($ahk.BaseName)" -ForegroundColor Green
}

Write-Host ""
Write-Host "[INFO] $($ahkFiles.Count) shortcut(s) added to startup." -ForegroundColor Cyan
Read-Host "Press Enter to close"
