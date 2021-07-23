#!/usr/bin/env pwsh

######################################## OPTIONAL USER-CONFIG ########################################################
# You may optionally want to hardcode these values in the script before executing for ease of use. If you don't then 
# the script will prompt you for the input. 

# Your Name
$pcee_iac_name = Read-Host "Enter your Name"
# Your Department
$pcee_iac_department = Read-Host "Enter your Department"
# Your Prisma Cloud API URL. You can find your prisma cloud api url here: https://prisma.pan.dev/api/cloud/api-urls
$pcee_api_url = Read-Host "Enter your Prisma Cloud API Url"
# Optional Hardcode Assignment. There are security things you should keep in mind if doing this
$pcee_accesskey = Read-Host "Enter your Prisma Cloud Access Key" -AsSecureString
$pcee_secretkey = Read-Host "Enter your Prisma Cloud Secret Key" -AsSecureString
$pcee_iac_environment = Read-Host "Enter the Environment where you're intending to Deploy"

######################################## END-OF-NORMAL-USER-CONFIG #####################################################


# Checking user input to ensure it matches
if ( [string]::IsNullOrEmpty($pcee_api_url) )
{
 Write-Host "The Prisma API URL is required to continue. Please see link to find your api url https://prisma.pan.dev/api/cloud/api-urls"
 exit
}
if ( $pcee_api_url -notlike "https://api*.prismacloud.io" )
{
 Write-Host "The api url should be formatted like https://api<your_instance_number>.prismacloud.io"
 exit
}
if (($pcee_accesskey.length -gt 40) -or ($pcee_accesskey.length -lt 35))
{
 Write-Host "Check your access key entry becuse it doesn't appear to be the correct length"
 exit
}
# Debugging the secret key input
if (($pcee_secretkey.length -gt 31) -or ($pcee_secretkey.length -lt 27))
{
 Write-Host "Check your secret key entry becuse it doesn't appear to be the correct length"
 exit
}
# Options for IaC file types
[string[]]$pcee_iac_types = 'Terraform', 'CloudFormation Template', 'Kubernetes Manifest'

Write-Output "Please choose the IaC File Type in the Directory:"
1..$pcee_iac_types.Length | foreach-object { Write-Output "$($_): $($pcee_iac_types[$_-1])" }
[ValidateScript({$_ -ge 1 -and $_ -le $pcee_iac_types.Length})]
[int]$pcee_iac_type_number = Read-Host "Press the number to select a Type"

if($?){
    Write-Output "You chose: $pcee_iac_type_number"
}
if ( $pcee_iac_type_number -eq 1 ){
$pcee_template_type = "tf"
}
if ( $pcee_iac_type_number -eq 2 ){ 
$pcee_template_type = "cft"
}
if ( $pcee_iac_type_number -eq 3 ){ 
$pcee_template_type = "k8s"
}
# Debugging to ensure entry is made
if ( [string]::IsNullOrEmpty($pcee_template_type) ){
 Write-Host "Invalid Selection Type"
 exit
}
$pcee_scan_asset_dir = Read-Host "Enter the File Path to the Folder containing the IaC files"
# Lazy check to ensure it's not a file. Issue if you have . in your file directory names; not solving for that right now
if ( $pcee_scan_asset_dir -like ".*" ){
 Write-Host "Either you named your directories with a \'.\' in them or you selected a file. It should be a directory. If you named your directories with \'.\' in them move the files to a different folder"
 exit
}
if ( [string]::IsNullOrEmpty($pcee_scan_asset_dir) ){
 Write-Host "You must specify the directory path to the Iac Files. Example C:\Users\Path\To\Dir"
 exit
}
$pcee_timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }

Compress-Archive -Path $pcee_scan_asset_dir -DestinationPath ("C:\Windows\Temp\PCEE_IAC_TEMP" + $pcee_timestamp + ".zip")

$pcee_scan_asset = ("C:\Windows\Temp\PCEE_IAC_TEMP" + $pcee_timestamp + ".zip")
$pcee_asset_name = Split-Path $pcee_scan_asset_dir -Leaf  


# These variables are really only applicable to CI/CD workflow implementations. 

# Change if you'd like to adjust the risk tolerance for passing vs failing in the console. Otherwise, leave them be:
# The number of high, medium, and low (In that order) configuration severity policies it will take to fail the check. 
$pcee_failure_criteria = @(1,1,1)

# The operator between those policies
$pcee_failure_criteria_operator = "or"

# Notates where it came from no need to change
$pcee_asset_type = "IaC-API"
$pcee_auth_body = @{
    "username" = "$pcee_accesskey"
    "password" = "$pcee_secretkey"
}


$pcee_auth_body = $pcee_auth_body |ConvertTo-Json


Write-Host "Authenticating to Prisma Cloud"
$pcee_auth_login=Invoke-RestMethod -Uri $($pcee_api_url + "/login") -body $pcee_auth_body -Method POST -Headers @{"Content-Type"="application/json"}
if ($lastExitCode -eq "0") {
    Write-Host "Authenticated"
}

if ($lastExitCode -eq "1") {
    Write-Host "Issue with reaching the Prisma Cloud Console. PANW Engineers check to see if Global Protect is enabled."
    exit
}
$pcee_iac_payload = [ordered]@{
    data = [ordered]@{
        type="async-scan"; 
        attributes = [ordered]@{
           assetName = "$pcee_asset_name";
           assetType = "$pcee_asset_type";
           tags = [ordered]@{
              name = "$pcee_iac_name";
              environment = "$pcee_iac_environment";
              department = "$pcee_iac_department";
        }
           scanAttributes = [ordered]@{
              developer = "kyle_butler";
              script = "powershell_test";
        }
           failureCriteria = [ordered]@{
              high = $pcee_failure_criteria[0];
              medium = $pcee_failure_criteria[1];
              low = $pcee_failure_criteria[2];
              operator = "$pcee_failure_criteria_operator";
        }
     }
   }
}

$pcee_iac_payload = $pcee_iac_payload | ConvertTo-Json -Depth 99

$pcee_auth_token=$pcee_auth_login.token

$pcee_scan_headers=@{
    "x-redlock-auth"="$pcee_auth_token"
    "Content-Type"="application/vnd.api+json"
}

Write-Host "Retrieving Secure Private Presigned URL for upload"
$pcee_scan=Invoke-RestMethod `
    -Method POST -Uri $($pcee_api_url + '/iac/v2/scans') `
    -Headers $pcee_scan_headers `
    -Body $pcee_iac_payload
$pcee_scan_id=$pcee_scan.data.id
$pcee_scan_url=$pcee_scan.data.links.url
$pcee_temp_payload=[ordered]@{
    data = [ordered]@{
        id="$pcee_scan_id";
        attributes = [ordered]@{
           templateType = "$pcee_template_type";
    }   
  }
}

$pcee_temp_json=$pcee_temp_payload | ConvertTo-Json -Depth 99
Write-Host "Uploading the IaC Project Directory securely to a private unique URL"



# uploads the file
Invoke-RestMethod -Method PUT -Uri $pcee_scan_url -InFile $pcee_scan_asset
Write-Host "Starting scan"


# starts scan
Invoke-RestMethod `
    -Method POST `
    -Uri $($pcee_api_url + '/iac/v2/scans/' + $pcee_scan_id) `
    -Headers $pcee_scan_headers `
    -Body $pcee_temp_json


# Waiting for scan to complete
$pcee_scan_status=Invoke-RestMethod `
    -Method GET -Uri $($pcee_api_url + '/iac/v2/scans/' + $pcee_scan_id + '/status') `
    -Headers $pcee_scan_headers


$pcee_scan_check=$pcee_scan_status.data.attributes.status

function Get-IaC-Scan-Status {
 $pcee_scan_check=$pcee_scan_status.data.attributes.status
  if ( $pcee_scan_check -eq "processing" ){
    Write-Host "processing"
    Start-Sleep -Seconds 10
    $pcee_scan_status=Invoke-RestMethod `
        -Method GET -Uri $($pcee_api_url + '/iac/v2/scans/' + $pcee_scan_id + '/status') `
        -Headers $pcee_scan_headers
 $pcee_scan_check=$pcee_scan_status.data.attributes.status
 }
}

Get-IaC-Scan-Status 
Get-IaC-Scan-Status 
Get-IaC-Scan-Status 
Get-IaC-Scan-Status 
Get-IaC-Scan-Status 
Get-IaC-Scan-Status 
Get-IaC-Scan-Status 
Get-IaC-Scan-Status 
Get-IaC-Scan-Status 

# To be clear no temp.json file is created. However PassThru requires the flag. Thanks MS
$pcee_scan_results=Invoke-RestMethod `
    -Method GET `
    -Uri $($pcee_api_url + '/iac/v2/scans/' + $pcee_scan_id + '/results') `
    -Headers $pcee_scan_headers `
    -OutFile ./temp.json `
    -PassThru 
$pcee_high_severity=$pcee_scan_results.meta.matchedPoliciesSummary.high
$pcee_medium_severity=$pcee_scan_results.meta.matchedPoliciesSummary.medium
$pcee_low_severity=$pcee_scan_results.meta.matchedPoliciesSummary.low

# echo $pcee_scan_results > temp_data.txt


Write-Host ""
Write-Host ""
Write-Host "$pcee_high_severity # of high severity issues found"
Write-Host "$pcee_medium_severity # of medium severity issues found"
Write-Host "$pcee_low_severity # of low severity issues found"
Write-Host ""
Write-Host "You can see the results in your Prisma Cloud Console"
Write-Host "Sign in to your console and go to Inventory - DevOps"
Write-Host ""
# Since I'm not super interested in figuring out how to parse JSON with powershell this will have to do
# The last command will pull a report of all assets scanned in the last hour if the user indicates they want a "detailed report"

While($pcee_report_selection -ne "Y" ){
   $pcee_report_selection = read-host "Delete the temp.zip created? (Y/N)"
    Switch ($pcee_report_selection) 
        { 
            Y {
               Remove-Item `
                 -Path $pcee_scan_asset `
                 -Force             
              } 
            N {Write-Host "Exiting out of script"} 
        } 
    If ($pcee_report_selection -eq "N"){Return}
}


Write-Host "Thanks for checking your IaC Project Directory"
exit
