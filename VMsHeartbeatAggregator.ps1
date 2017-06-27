Param(
    [Parameter (Mandatory=$true)]
    [String] $ResourceGroupName,
    [Parameter (Mandatory=$true)]
    [String] $WorkspaceName,
    [Parameter (Mandatory=$true)]
    [String] $CustomerName,     # e.g. CustomerX
    [Parameter (Mandatory=$true)]
    [String] $EnviromentName     # e.g. staging
)
$startdt = Get-Date
$Conn = Get-AutomationConnection -Name AzureRunAsConnection
Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID `
-ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

#Login-AzureRmAccount
#$ResourceGroupName = "omsrg"
#$WorkspaceName = "samploms"
#$results = Get-AzureRmOperationalInsightsSavedSearchResults -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -SavedSearchId "VMHealthCheck"
#$CustomerName = "customerx"
#$OmsWorkspaceUrl = "https://sampleoms.portal.mms.microsoft.com"
#$EnviromentName = "Staging"

# The following query aggregates the Heartbeat data per VM on a 10 minute duration span, within the last 1 hour
# Modify this query to suit. This is a dynamic query that is executed in the OMS Workspace
$results = Get-AzureRmOperationalInsightsSearchResults -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -Query "Type=Heartbeat  | measure count() by Computer, OSType interval 10Minute" -Top 100 -Start $startdt.AddHours(-1) -End $startdt

# The following code is used to add some envoloping braces to create a well formed JSON Document
$inputjson = "["
$counter = $results.value.count

for ($i=0; $i -lt $counter; $i++)
{
	if($i -eq 0)
	{
		$inputjson = $inputjson + $results.value[$i]
	}
	if($i -gt 0)
	{
		$inputjson =   $inputjson + "," + $results.value[$i]
	}
}
$inputjson = $inputjson + "]"
$inputjson
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

# Specify the name of the Dataset in the common OMS Workspace
$logType = "VMs"+ $CustomerName + $EnviromentName

$logType

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
Post-OMSData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($inputjson)) -logType $logType
