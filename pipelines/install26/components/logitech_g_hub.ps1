$url = "https://download01.logi.com/web/ftp/pub/techsupport/gaming/lghub_installer.exe"
$temp = "$env:TEMP\lghub_installer.exe"
Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing
Start-Process $temp -ArgumentList "--silent" -Wait
Remove-Item $temp -Force
