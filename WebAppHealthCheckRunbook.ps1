Param(
    [object]$WebhookData
)
# The Webhook URL to be used for this runbook is https://s3events.azure-automation.net/webhooks?token=TSIJCVTL6sLSpqm3vn8uI0uZVar9mkUcNfMwc8GzcFM%3d
$CustomerIdentifier = "customerxwebstg"
$WebhookName    =   $WebhookData.WebhookName
$WebhookBody    =   $WebhookData.RequestBody

# Outputs information on the webhook name that called This
Write-Output "This runbook was started from webhook $WebhookName."
Write-Output "Writing the incoming request to console ...."
$WebhookData

#$Conn = Get-AutomationConnection -Name AzureRunAsConnection
#Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID `
#-ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

$WebhookBody = (ConvertFrom-Json -InputObject $WebhookBody)
#Write-Output "`nWEBHOOK BODY"
#Write-Output "============="
#Write-Output $WebhookBody

# Obtain the AlertContext     
$AlertContext = [object]$WebhookBody.context

$var1 = $AlertContext.subscriptionId
$var2 = $AlertContext.resourceGroupName
$var3 = $AlertContext.resourceName
$var4 = $AlertContext.timestamp

#creating the Body of the payload to send to the Common OMS Workspace
$json = @"
[{  "SubscriptionId": "$var1",
    "ResourceGroup": "$var2",
    "ResourceName": "$var3",
    "TimeStamp": "$var4"
}]
"@
Write-Output "Printing the Request context $json."
# The following code is used to add some envoloping braces to create a well formed JSON Document
#$customHeader = @{
#   CustomerName = $CustomerName
#   OmsWorkspaceUrl = $OmsWorkspaceUrl
#   EnviromentName = $EnviromentName
#}

#$Url = "http://localhost:11566/api/Heartbeat"
#$Url = "http://octopusagsf.southeastasia.cloudapp.azure.com/vmhealthagg/api/Heartbeat"
#Invoke-RestMethod -Method Post -Uri $url -Credential $Cred -Body $inputjson -ContentType "application/json" -Headers $customHeader

# This is the Unique identifier of the Common Workspace in OMS
$CustomerId = "[Enter the Common OMS Workspace ID]"  

# The access key to connect to the common OMS Workspace
$SharedKey = "[Enter the Access key required to invoke the Data Collector API on the common OMS Workspace]"

# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}


# Create the function to create and post the request
Function Post-OMSData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
    }
    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode
}

# Submit the data to the API endpoint
Post-OMSData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $CustomerIdentifier
