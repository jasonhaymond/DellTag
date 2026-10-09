#requires -Version 5.1

<#
.SYNOPSIS
    Retrieves Dell warranty and entitlement information by Service Tag.

.DESCRIPTION
    Authenticates to the Dell TechDirect API with OAuth 2.0 and queries the
    Dell Asset Entitlements endpoint for a single Service Tag.

    The script can:
      - Display a summarized Dell asset and warranty result.
      - Return the unmodified API response with -Raw.
      - Export the summary to CSV with -Csv.
      - Export the summary and entitlement details to JSON with -Json.

    Required user environment variables:
      DELL_API_CLIENT_ID
      DELL_API_CLIENT_SECRET

    The normal output consists of two types of PowerShell objects:
      1. One summarized asset object.
      2. Zero or more entitlement objects.

    Important:
      This script queries warranty and entitlement data. It does not claim
      to return the complete original factory configuration or the original
      factory-installed operating system.

.PARAMETER ServiceTag
    The Dell Service Tag to look up. The value must contain 5 through 10
    letters or numbers.

.PARAMETER Raw
    Returns the unmodified PowerShell object received from the Dell API.
    The script does not format or export the response when this switch is used.

.PARAMETER Csv
    Exports the summarized asset result to a CSV file.

    If -ExportPath is omitted, the file is written to the current user's
    Desktop as Dell-SERVICETAG.csv. If the Desktop cannot be resolved, the
    current PowerShell directory is used.

.PARAMETER Json
    Exports the summarized asset result and all entitlement details to a
    JSON file.

    If -ExportPath is omitted, the file is written to the current user's
    Desktop as Dell-SERVICETAG.json. If the Desktop cannot be resolved, the
    current PowerShell directory is used.

.PARAMETER ExportPath
    Optional destination filename or path for -Csv or -Json.

    If the path does not include an extension, the appropriate .csv or .json
    extension is appended. Missing parent directories are created.

    This parameter requires either -Csv or -Json.

.EXAMPLE
    .\Get-DellAsset.ps1 ABC1234

    Looks up Service Tag ABC1234 and writes the asset summary followed by its
    warranty entitlement objects to the PowerShell pipeline.

.EXAMPLE
    .\Get-DellAsset.ps1 -ServiceTag ABC1234

    Performs the same standard lookup using the named parameter.

.EXAMPLE
    .\Get-DellAsset.ps1 ABC1234 -Raw

    Returns the unmodified Dell API response as a PowerShell object.

.EXAMPLE
    .\Get-DellAsset.ps1 ABC1234 -Raw | ConvertTo-Json -Depth 20

    Displays the raw Dell API response as formatted JSON without saving it.

.EXAMPLE
    .\Get-DellAsset.ps1 ABC1234 -Csv

    Exports the summarized asset result to Dell-ABC1234.csv on the Desktop.

.EXAMPLE
    .\Get-DellAsset.ps1 ABC1234 -Json

    Exports the asset summary and entitlement details to Dell-ABC1234.json
    on the Desktop.

.EXAMPLE
    .\Get-DellAsset.ps1 ABC1234 -Csv -ExportPath 'C:\Temp\Dell-ABC1234.csv'

    Exports the summarized asset result to the specified CSV file.

.EXAMPLE
    .\Get-DellAsset.ps1 ABC1234 -Json -ExportPath 'C:\Temp\Dell-ABC1234.json'

    Exports the asset summary and entitlement details to the specified JSON file.

.EXAMPLE
    Get-Help .\Get-DellAsset.ps1 -Full

    Displays the complete comment-based help contained in this script.

.INPUTS
    System.String

    ServiceTag accepts a string value. Pipeline input is not enabled in this
    version of the script.

.OUTPUTS
    System.Management.Automation.PSCustomObject

    Standard mode returns an asset summary object and entitlement objects.
    Raw mode returns the object supplied by the Dell API.

.NOTES
    File name: Get-DellAsset.ps1
    Minimum PowerShell version: Windows PowerShell 5.1

    Before using the script, define the credentials and restart PowerShell:

    [Environment]::SetEnvironmentVariable(
        'DELL_API_CLIENT_ID',
        'YOUR-CLIENT-ID',
        'User'
    )

    [Environment]::SetEnvironmentVariable(
        'DELL_API_CLIENT_SECRET',
        'YOUR-CLIENT-SECRET',
        'User'
    )

    Confirm that the new PowerShell session can see them without displaying
    their actual values:

    [bool]$env:DELL_API_CLIENT_ID
    [bool]$env:DELL_API_CLIENT_SECRET

    Do not store the client secret directly in this script or commit it to
    source control.

.LINK
    https://www.dell.com/support/home/en-us
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias('Tag', 'Serial', 'SerialNumber')]
    [ValidatePattern('^[A-Za-z0-9]{5,10}$')]
    [string]$ServiceTag,

    [switch]$Raw,
    [switch]$Csv,
    [switch]$Json,
    [string]$ExportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-DellDate {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$Value
    )

    process {
        if ($null -eq $Value) {
            return $null
        }

        $text = [string]$Value
        if ($text.Length -eq 0) {
            return $null
        }

        $parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse($text, [ref]$parsedDate)) {
            return $parsedDate
        }

        return $null
    }
}

function Get-DellAccessToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )

    $request = @{
        Method      = 'Post'
        Uri         = 'https://apigtwb2c.us.dell.com/auth/oauth/v2/token'
        ContentType = 'application/x-www-form-urlencoded'
        Body        = @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $ClientSecret
        }
    }

    try {
        $response = Invoke-RestMethod @request
    }
    catch {
        throw "Dell authentication failed: $($_.Exception.Message)"
    }

    if ($null -eq $response.access_token) {
        throw 'Dell authentication returned no access token.'
    }

    return [string]$response.access_token
}

function Get-DellExportPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $true)]
        [ValidateSet('csv', 'json')]
        [string]$Extension,

        [string]$RequestedPath
    )

    if ($RequestedPath) {
        $path = $RequestedPath
    }
    else {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not $desktop) {
            $desktop = $PWD.Path
        }

        $fileName = "Dell-$Tag.$Extension"
        $path = Join-Path -Path $desktop -ChildPath $fileName
    }

    $currentExtension = [System.IO.Path]::GetExtension($path)
    if (-not $currentExtension) {
        $path = "$path.$Extension"
    }

    $parent = Split-Path -Path $path -Parent
    if ($parent) {
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    return $path
}

if ($Raw -and ($Csv -or $Json)) {
    throw 'Do not combine -Raw with -Csv or -Json.'
}

if ($Csv -and $Json) {
    throw 'Choose either -Csv or -Json, not both.'
}

if ($ExportPath -and (-not $Csv) -and (-not $Json)) {
    throw '-ExportPath requires either -Csv or -Json.'
}

$clientId = $env:DELL_API_CLIENT_ID
$clientSecret = $env:DELL_API_CLIENT_SECRET

if (-not $clientId) {
    throw 'Environment variable DELL_API_CLIENT_ID is not set.'
}

if (-not $clientSecret) {
    throw 'Environment variable DELL_API_CLIENT_SECRET is not set.'
}

$ServiceTag = $ServiceTag.Trim().ToUpperInvariant()
$accessToken = Get-DellAccessToken -ClientId $clientId -ClientSecret $clientSecret
$encodedTag = [uri]::EscapeDataString($ServiceTag)

$headers = @{
    Authorization = "Bearer $accessToken"
    Accept        = 'application/json'
}

$warrantyUri = 'https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements?servicetags=' + $encodedTag

$warrantyRequest = @{
    Method  = 'Get'
    Uri     = $warrantyUri
    Headers = $headers
}

try {
    $apiResponse = Invoke-RestMethod @warrantyRequest
}
catch {
    throw "Dell warranty lookup failed: $($_.Exception.Message)"
}

if ($Raw) {
    Write-Output $apiResponse
    return
}

$assets = @($apiResponse)
$asset = $assets | Where-Object { $_.serviceTag -eq $ServiceTag } | Select-Object -First 1

if ($null -eq $asset) {
    $asset = $assets | Select-Object -First 1
}

if ($null -eq $asset) {
    throw "Dell returned no information for Service Tag $ServiceTag."
}

$entitlements = foreach ($entry in @($asset.entitlements)) {
    $startDate = ConvertTo-DellDate -Value $entry.startDate
    $endDate = ConvertTo-DellDate -Value $entry.endDate
    $status = 'Unknown'
    $daysRemaining = $null

    if ($null -ne $endDate) {
        $daysRemaining = [int](($endDate.Date - (Get-Date).Date).TotalDays)

        if ($daysRemaining -lt 0) {
            $status = 'Expired'
        }
        elseif ($daysRemaining -le 90) {
            $status = 'Expiring Soon'
        }
        else {
            $status = 'Active'
        }
    }

    [pscustomobject]@{
        ServiceLevelCode = $entry.serviceLevelCode
        ServiceLevel     = $entry.serviceLevelDescription
        EntitlementType  = $entry.entitlementType
        StartDate        = $startDate
        EndDate          = $endDate
        Status           = $status
        DaysRemaining    = $daysRemaining
    }
}

$entitlements = @($entitlements)
$latest = $entitlements | Where-Object { $null -ne $_.EndDate } | Sort-Object EndDate -Descending | Select-Object -First 1

$warrantyStatus = 'Unknown'
$warrantyExpiration = $null
$overallDaysRemaining = $null

if ($null -ne $latest) {
    $warrantyStatus = $latest.Status
    $warrantyExpiration = $latest.EndDate
    $overallDaysRemaining = $latest.DaysRemaining
}

$result = [pscustomobject]@{
    ServiceTag         = $asset.serviceTag
    Model              = $asset.productLineDescription
    ProductCode        = $asset.productCode
    ShipDate           = ConvertTo-DellDate -Value $asset.shipDate
    CountryCode        = $asset.countryCode
    WarrantyStatus     = $warrantyStatus
    WarrantyExpiration = $warrantyExpiration
    DaysRemaining      = $overallDaysRemaining
    EntitlementCount   = $entitlements.Count
    DellSupportURL     = 'https://www.dell.com/support/home/en-us/product-support/servicetag/' + $ServiceTag + '/overview'
}

if ($Csv) {
    $path = Get-DellExportPath -Tag $ServiceTag -Extension 'csv' -RequestedPath $ExportPath
    $result | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8 -Force
    Write-Host "CSV exported to: $path" -ForegroundColor Green
    return
}

if ($Json) {
    $path = Get-DellExportPath -Tag $ServiceTag -Extension 'json' -RequestedPath $ExportPath

    $jsonData = [pscustomobject]@{
        Asset        = $result
        Entitlements = $entitlements
    }

    $jsonText = $jsonData | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $path -Value $jsonText -Encoding UTF8 -Force
    Write-Host "JSON exported to: $path" -ForegroundColor Green
    return
}

Write-Output $result
Write-Output $entitlements
