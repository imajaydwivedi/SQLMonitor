<#
    Purpose: Install First Responder Kit on multiple servers
#>
#$personalCred = Get-Credential -UserName 'adwivedi' -Message 'Credential Manager Server SQL Login'

cls

# Parameters
$InventoryServer = 'OfficeInventory'
$InventoryDatabase = 'DBA'
$CredentialManagerDatabase = 'DBA'
$AllServerLogin = 'sa'
$FirstResponderKitZipFile = 'C:\Users\Ajay\Downloads\SQL-Server-First-Responder-Kit-20231010.zip' # Download from releases section

Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

# Connect to Inventory Server, and get sa credential
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName "Get-FailedLogins.ps1" `
                                                    -TrustServerCertificate -EncryptConnection -SqlCredential $personalCred -ErrorAction Stop

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch [$AllServerLogin] password from Credential Manager [$InventoryServer].[$CredentialManagerDatabase].."
$getCredential = @"
/* Fetch Credentials */
declare @password varchar(256);
exec dbo.usp_get_credential 
		@server_ip = '*',
		@user_name = @all_server_login,
		@password = @password output;
select @password as [password];
"@
[string]$allServerLoginPassword = $conInventoryServer | Invoke-DbaQuery -Database $CredentialManagerDatabase `
                            -Query $getCredential -SqlParameter @{all_server_login = $AllServerLogin} | 
                                    Select-Object -ExpandProperty password -First 1

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Create [$AllServerLogin] credential from fetched password.."
[securestring]$secStringPassword = ConvertTo-SecureString $allServerLoginPassword -AsPlainText -Force
[pscredential]$allServerLoginCredential = New-Object System.Management.Automation.PSCredential $AllServerLogin, $secStringPassword


# Get servers list
$sqlGetSQLMonitorServers = @"
select distinct id.sql_instance, id.sql_instance_port, id.[database]
from dbo.instance_details id
where id.is_enabled = 1
and id.is_available = 1
and id.is_alias = 0
"@
$serversFromInventory = @()
$serversFromInventory += $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlGetSQLMonitorServers -ErrorAction Stop
#$serversFromInventoryFiltered = $serversFromInventory | Where-Object {$_.sql_instance -in $failedServers.server}

# Loop through servers list, and perform required action
[System.Collections.ArrayList]$successServers = @()
[System.Collections.ArrayList]$failedServers = @()
[System.Collections.ArrayList]$queryResult = @()

foreach($sql_instance in $serversFromInventory)
{
    $srv = $sql_instance.sql_instance
    $dba_database = $sql_instance.database

    "Working on [$srv].." | Write-Host -ForegroundColor Cyan
    try {
        $srvObj = Connect-DbaInstance -SqlInstance $srv -Database master -ClientName "DBA-Ajay-Dwivedi-Wrapper-InstallDbaFirstResponderKit.ps1" `
                                                    -SqlCredential $allServerLoginCredential -TrustServerCertificate -EncryptConnection -ErrorAction Stop

        # Deploy First Responder Kit
        $srvObj | Install-DbaFirstResponderKit -LocalFile $FirstResponderKitZipFile -EnableException -Verbose:$false -Debug:$false | Format-Table -AutoSize

        # When no data resultset is expected
            #$srvObj | Invoke-DbaQuery -Database master -Query $sqlAlterAudit -EnableException
        
        # When resultset is expected
        <#
        $srvObj | Invoke-DbaQuery -Database master -Query $sqlGetMultiplePropertiesl -EnableException `
                    -SqlParameter @{ sql_instance = $srv } `
                    -As PSObject | % {$queryResult.Add($_)|Out-Null}
        #>      
        $successServers.Add($srv) | Out-Null
    }
    catch {
        $errMsg = $_.Exception.Message
        $failedServers.Add([PSCustomObject]@{server = $srv; error = $errMsg}) | Out-Null
        "`n`tError: $errMsg" | Write-Host -ForegroundColor Red
    }
}

#$successServers | ogv
$failedServers | ogv
#$queryResult | ogv

#$excelPath = "$($env:USERPROFILE)\Downloads\SomeTask-2023Dec04.xlsx"
#$queryResult | Export-Excel -Path $excelPath -WorksheetName 'Orphan-Users'

#$successServers | ? {$_ -notin $queryResult.sql_instance} | ogv -Title "Servers Missing Not in Results"


<#
# **__ First Responder Kit from latest release __**
if ($true) {
    $repo = "BrentOzarULTD/SQL-Server-First-Responder-Kit"
    $tags = "https://api.github.com/repos/$repo/tags"

    $tagName = (Invoke-WebRequest $tags | ConvertFrom-Json)[0].name
    $releaseZip = "https://github.com/$repo/archive/refs/tags/$tagName.zip"
    $outFile = "$($env:USERPROFILE)\Downloads\SQL-Server-First-Responder-Kit-$tagName.zip"

    Invoke-WebRequest $releaseZip `
            -OutFile $outFile

    "File downloaded: '$outFile'" | Write-Host -ForegroundColor Green
}
#>