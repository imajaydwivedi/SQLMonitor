[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$DbaDatabase = 'DBA',

    [Parameter(Mandatory=$false)]
    [String]$InventoryServer = 'SQLMonitor',

    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',

    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerDatabase = 'DBA',

    [Parameter(Mandatory=$false)]
    [String]$SqlAdminLoginName = 'sa',

    [Parameter(Mandatory=$false)]
    [PSCredential]$SqlCredential
)

cls
$startTime = Get-Date
$ErrorActionPreference = "Stop"
$ClientName = "Disable-ExpiredLogins"

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'START:', "Start of script [$ClientName]." | Write-Host -ForegroundColor Yellow

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName $ClientName `
                                                    -SqlCredential $SqlCredential -TrustServerCertificate -ErrorAction Stop

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Invoke-DbaQuery] Get list of sql_instance + logins to disable.."
$sqlExpiredLogins = @"
declare @warning_threshold_days int;
declare @critical_threshold_days int;
declare @sql nvarchar(max)
declare @params nvarchar(max)
declare @sql_instance varchar(125)
declare @login_name varchar(125);

set @warning_threshold_days = 20;
set @critical_threshold_days = 10;
set @sql_instance = null
set @login_name = null

select  [collection_time] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), collection_time), 
        [sql_instance], [login_name], [is_sysadmin], [is_app_login],
        [password_last_set_time] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), password_last_set_time), 
        [password_expiration], [is_expired], [is_locked], [days_until_expiration], 
        [login_owner_group_email], [server_owner_email], [app_team_emails], [application_owner_emails]
from dbo.all_server_login_expiry_info_dashboard lei
where 1=1
and lei.days_until_expiration <= @warning_threshold_days
and left(lower(login_name),6) <> 'bidba.'
and is_expired = 1;
"@
$resultExpiredLogins = @()
$resultExpiredLogins += Invoke-DbaQuery -SqlInstance $conInventoryServer -Query $sqlExpiredLogins

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch [$SqlAdminLoginName] password from Credential Manager [$InventoryServer].[$CredentialManagerDatabase].."
$getCredential = @"
/* Fetch Credentials */
declare @password varchar(256);
exec dbo.usp_get_credential
		@user_name = @all_server_login,
		@password = @password output;
select @password as [password];
"@
[string]$SqlAdminLoginPassword = $conInventoryServer | Invoke-DbaQuery -Database $CredentialManagerDatabase `
                            -Query $getCredential -SqlParameter @{all_server_login = $SqlAdminLoginName} | 
                                    Select-Object -ExpandProperty password -First 1

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Create [$SqlAdminLoginName] credential from fetched password.."
[securestring]$secStringPassword = ConvertTo-SecureString $SqlAdminLoginPassword -AsPlainText -Force
[pscredential]$SqlAdminLoginCredential = New-Object System.Management.Automation.PSCredential $SqlAdminLoginName, $secStringPassword


# Get unique list of servers
$sqlInstances = @()
$sqlInstances += $resultExpiredLogins | Select-Object -ExpandProperty sql_instance -Unique

# Query to disable logins
$sqlDisableLogin = @"
declare @_sql nvarchar(max);
declare @_login_name nvarchar(255);

set @_login_name = @login_name;

set @_sql = N'alter login '+quotename(@_login_name)+' disable;';
print @_sql;
--print 'execute sql now..'
exec (@_sql);
"@

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Loop through all SQLServer Instances to disable logins.."
[System.Collections.ArrayList]$failedList = @()
foreach($sql_instance in $sqlInstances) 
{
    "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Working on sql_instance [$sql_instance].."

    "  $(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for '$sql_instance'.."
    $conSqlInstanceToDisableLogins = Connect-DbaInstance -SqlInstance $sql_instance -Database master -ClientName $ClientName `
                                                -SqlCredential $SqlAdminLoginCredential -TrustServerCertificate -ErrorAction Stop
    
    # Extract all logins for sql_instance
    $loginsForServer = @()
    $loginsForServer += $resultExpiredLogins | Where-Object {$_.sql_instance -eq $sql_instance}

    # Loop through logins, and disable them
    foreach($row in $loginsForServer)
    {
        $login_name = $row.login_name

        "    $(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Invoke-DbaQuery] Disable login [$login_name] on '$sql_instance'.."
        try {
            [string]$qryResult = $conSqlInstanceToDisableLogins | Invoke-DbaQuery -Query $sqlDisableLogin -MessagesToOutput -EnableException `
                                        -SqlParameter @{login_name = $login_name} 
        }
        catch {
            $failedList.Add([PSCustomObject]@{sql_instance = $sql_instance; login_name = $login_name;}) | Out-Null
        }
    }
}

if($failedList.Count -eq 0) {
    "`n`nNo failures.`n`n" | Write-Host -ForegroundColor Green
}
else {
    "`n`nList of failed sql_instance+login..`n`n" | Write-Host -ForegroundColor Red
    $failedList | Format-Table -AutoSize
}

