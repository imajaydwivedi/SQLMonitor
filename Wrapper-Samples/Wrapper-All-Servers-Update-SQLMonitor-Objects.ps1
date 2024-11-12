[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$InventoryServer = 'OfficeInventory',
    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [Bool]$StopJob = $true,
    [Parameter(Mandatory=$false)]
    [Bool]$StartJob = $true,
    [Parameter(Mandatory=$false)]
    [String]$AllServerLogin = 'sa'
)

<# Purpose:  Loop through all SQLMonitor servers, and drop/create objects #>

#$personal = Get-Credential -UserName 'adwivedi' -Message 'Personal'

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName "Wrapper-UpdateSQLMonitor-Objects.ps1" `
                                                    -TrustServerCertificate -EncryptConnection -ErrorAction Stop -SqlCredential $personal

if(-not [String]::IsNullOrEmpty($AllServerLogin)) 
{
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
}
else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'WARNING:', "No login provided for parameter [AllServerLogin]."
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'WARNING:', "Using windows authentication for SQL Connections."
}


# Get SQLMonitor servers
$sqlGetServers = @"
select id.sql_instance, id.[database], id.sql_instance_port, sql_instance_with_port = coalesce(id.sql_instance +','+ id.sql_instance_port, id.sql_instance)
from dbo.instance_details id
where id.is_enabled = 1
and id.is_available = 1
and id.is_alias = 0
"@

$servers = @()
$servers += $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlGetServers | Select-Object -Property sql_instance,sql_instance_port,sql_instance_with_port,database -Unique

$fileWithDDLs = 'D:\GitHub-Personal\SQLMonitor\DDLs\SCH-usp_avg_disk_wait_ms.sql'
$grafanaPermissionsFile = 'D:\GitHub-Personal\SQLMonitor\Work-Solve-SQLMonitor-Issues\grafana-login.sql'

$preSQL = @"
declare @_action_taken bit = 0;
declare @_sql_instance varchar(125);

set @_sql_instance = @sql_instance;

if OBJECT_ID('[dbo].[alert_categories]') is not null
begin
    if not exists (select 1/0 from [dbo].[alert_categories] where category like 'Fatal Error - %')
	begin
        drop table [dbo].[alert_categories];
		set @_action_taken = 1;
	end
end

select sql_instance = @_sql_instance, action_taken = @_action_taken;
"@


# Loop through servers list, and perform required action
[System.Collections.ArrayList]$queryResult = @()
[System.Collections.ArrayList]$successServers = @()
[System.Collections.ArrayList]$failedServers = @()

#$serversRemaining = $servers | ? {$_ -notin $successServers }
#$successServersFinal = $successServers

foreach($srvDtls in $servers)
{
    $srv = $srvDtls.sql_instance_with_port
    $sqlInstance = $srvDtls.sql_instance
    $sqlInstanceWithPort = $srvDtls.sql_instance_with_port
    $sqlInstancePort = $srvDtls.sql_instance_port  
    $database = $srvDtls.database
    $actionRequired4SqlInstance = $true

    "Working on [$sqlInstance].." | Write-Host -ForegroundColor Cyan
    try {
        $srvObj = Connect-DbaInstance -SqlInstance $sqlInstanceWithPort -Database $database -ClientName "Wrapper-DropCreateSQLMonitorObjects.ps1" `
                            -SqlCredential $allServerLoginCredential -TrustServerCertificate -EncryptConnection -ErrorAction Stop

        # Execute pre sql & save result in $queryResult
        #$srvObj | Invoke-DbaQuery -Query $preSQL -SqlParameter @{sql_instance = $sqlInstance} -EnableException | % { $queryResult.Add($_) | Out-Null}
        #$srvObj | Invoke-DbaQuery -Query $preSQLGrafanaPermissions -EnableException
        

        #$actionRequired4SqlInstance = $queryResult | ? {$_.sql_instance -eq $sqlInstance} | Select -ExpandProperty action_taken -First 1

        # Update threshold using file script
        #if ($actionRequired4SqlInstance) {
            $srvObj | Invoke-DbaQuery -File $fileWithDDLs -EnableException
            $srvObj | Invoke-DbaQuery -File $grafanaPermissionsFile -EnableException
        #}
                
        $successServers.Add([PSCustomObject]@{server = $sqlInstance; server_with_port = $sqlInstanceWithPort; action_taken = $actionRequired4SqlInstance}) | Out-Null
    }
    catch {
        $errMsg = $_.Exception.Message
        $failedServers.Add([PSCustomObject]@{server = $sqlInstance; server_with_port = $sqlInstanceWithPort; error = $errMsg}) | Out-Null
        "`n`tError: $errMsg" | Write-Host -ForegroundColor Red
    }
}

$successServers | ogv -Title "Successful"
$failedServers | ogv -Title "Failed"
$serversNotConsidered | ogv -Title "Not Considered Servers"

