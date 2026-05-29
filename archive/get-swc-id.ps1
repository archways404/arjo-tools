param(
    [string]$PCName = "PCXXXXXXX"
)

$session = ""  # ASP.NET_SessionId
$userID  = "=" # UserID

$response = Invoke-RestMethod `
    -Uri "https://arjoswc.arjo.local/WebServices/WS_Computers.asmx/GetComputersFromSccmAndIntuneBySearchString" `
    -Method POST `
    -ContentType "application/json" `
    -Headers @{
        "X-Requested-With" = "XMLHttpRequest"
        "Cookie" = "ASP.NET_SessionId=$session; UserID=$userID; swcErrorLevel=1; timezone=GMT Standard Time"
    } `
    -Body "{`"context`": {`"Text`": `"$PCName`", `"NumberOfItems`": 0}}" `
    -SkipCertificateCheck

$response.d.Items | Select Text, Value
