param(
    [string]$PCName = "PCXXXXXXX"
)

$session = ""
$userID  = ""
$cookies = "ASP.NET_SessionId=$session; UserID=$userID; swcErrorLevel=1; timezone=GMT Standard Time"
$headers = @{
    "X-Requested-With" = "XMLHttpRequest"
    "Cookie"           = $cookies
}

# Step 1: Get ResourceId
$search = Invoke-RestMethod `
    -Uri "https://arjoswc.arjo.local/WebServices/WS_Computers.asmx/GetComputersFromSccmAndIntuneBySearchString" `
    -Method POST `
    -ContentType "application/json" `
    -Headers $headers `
    -Body "{`"context`": {`"Text`": `"$PCName`", `"NumberOfItems`": 0}}" `
    -SkipCertificateCheck

$resourceId = $search.d.Items[0].Value
if (-not $resourceId) { Write-Error "PC not found"; exit }

# Step 2: Fetch info page and parse HTML
$html = Invoke-WebRequest `
    -Uri "https://arjoswc.arjo.local/Status/RadWindowComputersInformation.aspx?ResourceId=$resourceId" `
    -Headers @{ "Cookie" = $cookies } `
    -UseDefaultCredentials `
    -SkipCertificateCheck

# Step 3: Extract labelled fields
$fields = @(
    "LabelName", "LabelClientType", "LabelClientVersion", "LabelIpAddresses",
    "LabelMacAddresses", "LabelSystemOUName", "LabelClientCheckResult",
    "LabelAdSite", "LabelLastLogon", "LabelLogonUser", "LabelOperatingSystem",
    "LabelComputerManufatorAndModel", "LabelEndpointDeploymentState",
    "LabelSerialNumber", "LabelBIOSVersion", "LabelPendingReboot",
    "LabelPolicyRequest", "LabelHeartbeatDDR", "LabelHardwareScan",
    "LabelSoftwareScan", "LabelManagementPoint", "LabelStatusMessage",
    "LabelLastCommunication", "LabelPrimaryUsers"
)

$result = [ordered]@{}
foreach ($id in $fields) {
    if ($html.Content -match "id=`"$id`"[^>]*>([^<]+(?:<br\s*/>[^<]*)*)<") {
        $value = $Matches[1] -replace '<br\s*/?>', ', ' -replace '^\s+|\s+$', ''
        $result[$id -replace '^Label', ''] = $value
    }
}

$result | Format-Table -AutoSize
