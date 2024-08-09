<#
    Purpose: Run sql script on multiple servers, and process result
#>
#$personal = Get-Credential -UserName 'sa' -Message 'Credential Manager Server SQL Login'

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$InventoryServer = 'localhost',
    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerDatabase = 'DBA',
    [Parameter(Mandatory=$true)]
    [String]$AllServerLogin = 'sa',
    [Parameter(Mandatory=$false)]
    [String]$WorkFolder = "C:\SQLMonitor\Work-Attachments",
    [Parameter(Mandatory=$true)]
    [String[]]$Logins,
    [Parameter(Mandatory=$false)]
    [String[]]$Servers,
    [Parameter(Mandatory=$false)]
    [bool]$RemoveLogFile = $true,
    [Parameter(Mandatory=$false)]
    [String]$JobName = "(dba) Change-LoginPasswordAllServers"
)
$DateString = Get-Date -Format yyyyMMMdd_HHmm

$AppName = "Wrapper-ChangeLoginPasswordAllServers.ps1"
$outputFile ="$WorkFolder\$AppName-$DateString.txt"

Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

# Connect to Inventory Server, and get sa credential
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.." | Tee-Object $outputFile -Append
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName $AppName `
                                                    -TrustServerCertificate -EncryptConnection -SqlCredential $personal -ErrorAction Stop

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch [$AllServerLogin] password from Credential Manager [$InventoryServer].[$CredentialManagerDatabase].." | Tee-Object $outputFile -Append
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

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Create [$AllServerLogin] credential from fetched password.." | Tee-Object $outputFile -Append
[securestring]$secStringPassword = ConvertTo-SecureString $allServerLoginPassword -AsPlainText -Force
[pscredential]$allServerLoginCredential = New-Object System.Management.Automation.PSCredential $AllServerLogin, $secStringPassword


# Get SQLMonitor instance_details
$qrySQLMonitorInstanceDetails = @"
select distinct id.sql_instance, id.sql_instance_port, id.[database]
from dbo.instance_details id
where id.is_enabled = 1
and id.is_alias = 0
$(if([String]::IsNullOrEmpty($Servers)){'--'})and id.sql_instance in ($(($Servers | % {"'$_'"}) -join ','))
"@
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Get list of SQLInstances from dbo.instance_details.." | Tee-Object $outputFile -Append
$serversCollection_SQLMonitorInstanceDetails = @()
$serversCollection_SQLMonitorInstanceDetails += $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase `
                                                       -Query $qrySQLMonitorInstanceDetails -EnableException -ErrorAction Stop
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Below SQLInstances found in dbo.instance_details-" | Tee-Object $outputFile -Append
"`n($(($serversCollection_SQLMonitorInstanceDetails.sql_instance|%{"'$_'"}) -join ','))`n" | Tee-Object $outputFile -Append

# Get Passwords for logins from Credential Manager
$sqlGetLoginsPassword = @"
select	[user_name], 
		[password] = cast(DecryptByPassPhrase(cast(salt as varchar),password_hash ,1, server_ip) as varchar),
		remarks 
from dbo.credential_manager cm
where cm.server_ip = '*'
and cm.user_name in ($(($Logins | % {"'$_'"}) -join ','))
"@
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch passwords for logins ($(($Logins | % {"'$_'"}) -join ',')) from Credential Manager.." | `
                                Tee-Object $outputFile -Append
$loginsPassword = $conInventoryServer | Invoke-DbaQuery -Database $CredentialManagerDatabase -Query $sqlGetLoginsPassword `
                        -EnableException -ErrorAction Stop

$sqlAddErrorLogEntry = @"
insert dbo.sma_errorlog
(function_name, function_call_arguments, server, error, executor_program_name)
select @function_name, @function_call_arguments, @server, @error, @executor_program_name
"@

# Tsql script to execute
$changeLoginPassword = $true
if($changeLoginPassword)
{
    # Loop through servers list, and perform required action
    [System.Collections.ArrayList]$successServers = @()
    [System.Collections.ArrayList]$failedServers = @()
    [System.Collections.ArrayList]$queryResult = @()

    foreach($srvInst in $serversCollection_SQLMonitorInstanceDetails)
    {
        $srvName = $srvInst.sql_instance
        $srvPort = $srvInst.sql_instance_port
        $database = $srvInst.database

        $srv = $srvName
        if (-not [String]::IsNullOrEmpty($srvPort)) {
            $srv = "$srvName,$srvPort"
        }

        "Working on [$srv].." | Tee-Object $outputFile -Append | Write-Host -ForegroundColor Cyan
        try {
            $srvObj = Connect-DbaInstance -SqlInstance $srv -Database master -ClientName $AppName `
                               -SqlCredential $allServerLoginCredential -TrustServerCertificate -EncryptConnection -ErrorAction Stop
        }
        catch {
            $errMsg = $_.Exception.Message
            $failedServers.Add([PSCustomObject]@{server=$srvName; sql_port=$srvPort; server_with_port=$srv; login_name=$null; error = $errMsg}) | Out-Null
            "`n`tError: $errMsg" | Tee-Object $outputFile -Append | Write-Host -ForegroundColor Red

            $errorParams = @{
                function_name = $AppName
                function_call_arguments = 'Connect-DbaInstance'
                server = $srvName
                error = $errMsg
                executor_program_name = $JobName
            }
            $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlAddErrorLogEntry `
                        -EnableException -ErrorAction Stop -SqlParameter $errorParams

            continue
        }

        # loop through each login
        foreach($login in $Logins)
        {
            $newPassword = $null
            try {
                "`tWorking for login [$srv]..[$login].." | Tee-Object $outputFile -Append | Write-Host
                
                $newPassword = $loginsPassword | Where-Object {$_.user_name -eq $login} | Select-Object -ExpandProperty password
                $sqlResetLoginPassword = @"
use [master];

-- disable check policy
alter login [$login] with check_policy=off;
-- reset password
alter login [$login] with password=N'$newPassword';
-- enable check policy
alter login [$login] with check_policy=on;

SELECT 	[sql_instance] = @sql_instance, 
        [sql_instance_with_port] = @sql_instance_with_port, 
        [login_name] = sl.name, [login_sid] = sl.sid, sl.default_database_name,
		sl.is_policy_checked, sl.is_expiration_checked,
		[is_sysadmin] = IS_SRVROLEMEMBER ('sysadmin', sl.name),
		[password_last_set_time] = convert(datetime,LOGINPROPERTY([sl].name, 'PasswordLastSetTime'),120),
		[days_until_expiration] = CONVERT(int,LOGINPROPERTY([sl].name, 'DaysUntilExpiration'))
from master.sys.sql_logins sl
where name = '$login'
"@

                $srvObj | Invoke-DbaQuery -Database master -Query $sqlResetLoginPassword -EnableException `
                            -SqlParameter @{ sql_instance = $srvName; sql_instance_with_port = $srv } `
                            -As PSObject | % {$queryResult.Add($_)|Out-Null}
                #$srvObj | Invoke-DbaQuery -Database master -Query $sqlAccessQuery -SqlParameter @{ sql_instance = $srv } -EnableException -MessagesToOutput | Tee-Object $outputFile -Append
                  
                $successServers.Add($srv) | Out-Null
            }
            catch {
                $errMsg = $_.Exception.Message
                $failedServers.Add([PSCustomObject]@{server=$srvName; sql_port=$srvPort; server_with_port=$srv; login_name=$null; error = $errMsg}) | Out-Null
                "`n`tError: $errMsg" | Tee-Object $outputFile -Append | Write-Host -ForegroundColor Red

                $errorParams = @{
                    function_name = $AppName
                    function_call_arguments = "alter login [$login]"
                    server = $srvName
                    error = $errMsg
                    executor_program_name = $JobName
                }
                $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlAddErrorLogEntry `
                            -EnableException -ErrorAction Stop -SqlParameter $errorParams
            }
        }
    }

    if($RemoveLogFile) {
        Remove-Item $outputFile -Confirm:$false -Verbose
    }

    #$successServers | ogv
    $failedServers | ogv
    $queryResult | ogv

    if($queryResult.Count -gt 0) {
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Script Result -" | Tee-Object $outputFile -Append
        $queryResult | Format-Table -AutoSize | Out-String | Tee-Object $outputFile -Append
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
    }

    if($successServers.Count -gt 0) {
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Successful Servers -" | Tee-Object $outputFile -Append
        $successServers | Format-Table -AutoSize | Out-String | Tee-Object $outputFile -Append
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
    }

    if($failedServers.Count -gt 0) {        
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Failure occurred for following -" | Tee-Object $outputFile -Append
        $failedServers | Format-Table -AutoSize | Out-String | Tee-Object $outputFile -Append
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
    }
    else {
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "No failure occurred." | Tee-Object $outputFile -Append
        "--"*20 | Tee-Object $outputFile -Append | Write-Output
    }

    #$successServers | ? {$_ -notin $queryResult.sql_instance} | ogv -Title "Servers Missing Not in Results"
}

