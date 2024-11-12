[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$InventoryServer = 'localhost',

    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',

    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerDatabase = 'DBA',

    [Parameter(Mandatory=$true)]
    [String]$UserName,

    [Parameter(Mandatory=$false)]
    [String]$WebsiteHostName = 'ajaydwivedi.ddns.net',

    [Parameter(Mandatory=$false)]
    [String]$HostPortNo = 3000
)

cls

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Test connectivity to '$WebsiteHostName' on port $HostPortNo.."
try {
    Test-NetConnection $WebsiteHostName -Port $HostPortNo -InformationLevel Detailed -ErrorAction Stop -WarningVariable netConnectionWarning | Out-Null
    [bool]$isOk = $true
}
catch {
    $errMsg = $_
    [bool]$isOk = $false
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Test-NetConnection command failed with following error:-`n`n$errMsg`n"
}


if ( $netConnectionWarning -match 'failed' ) {
    [bool]$isOk = $false
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'WARNING:', "Connectivity test failed."
}


if( $isOk ) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Connectivity to '$WebsiteHostName' on port $HostPortNo is fine."
}
else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
    $conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName "Update-SQLMonitorIP.ps1" `
                                                        -TrustServerCertificate -EncryptConnection -ErrorAction Stop

    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch [$UserName] password from Credential Manager [$InventoryServer].[$CredentialManagerDatabase].."
    $getCredential = @"
    /* Fetch Credentials */
    declare @password varchar(256);
    exec dbo.usp_get_credential 
		    @server_ip = '*',
		    @user_name = '$UserName',
		    @password = @password output;
    select @password as [password];
"@
    [string]$userNamePassword = $conInventoryServer | Invoke-DbaQuery -Database $CredentialManagerDatabase -Query $getCredential | 
                                        Select-Object -ExpandProperty password -First 1

    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Find out public ip of system.."
    $ip = (Invoke-RestMethod 'http://ipinfo.io/json').ip

    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Ip => '$ip'"

    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Making below URI call..`n"
    $noipURL = “https://dynupdate.no-ip.com/dns?username=$UserName&password=$userNamePassword&hostname=$WebsiteHostName&ip=$ip"

    $noipURL

    try {
        $response = Invoke-WebRequest -Uri $noipURL

        # This will only execute if the Invoke-WebRequest is succesful.
        $statusCode = $response.StatusCode
        "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Dynamic DNS Update went successful with statuscode '$statusCode'."
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Dynamic DNS Update failed with statuscode '$statusCode'."
        $statusCode | Write-Error
    }
}
