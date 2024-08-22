[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$InventoryServer = 'SQLMonitor',
    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [Bool]$StopJob = $true,
    [Parameter(Mandatory=$false)]
    [Bool]$StartJob = $true,
    [Parameter(Mandatory=$false)]
    [String]$AllServerLogin = 'sa',
    [Parameter(Mandatory=$false)]
    [String]$ClientAppName = "Wrapper-UpdateSQLAgentJobsThreshold.ps1",
    [Parameter(Mandatory=$false)]
    $FileUpdateSQLAgentJobsThreshold = 'D:\GitHub\SQLMonitor\DDLs\Update-SQLAgentJobsThreshold.sql',
    [Parameter(Mandatory=$false)]
    [PSCredential]$PersonalCredential

)

<# Purpose:  Loop through all SQLMonitor servers, and update SQLAgentJobs thresholds #>

#$PersonalCredential = Get-Credential -UserName 'sa' -Message 'Personal'

if([String]::IsNullOrEmpty($FileUpdateSQLAgentJobsThreshold)) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "File path of tsql containing Update-SQLAgentJobsThreshold is requried."
    "Kindly fix above issue" | Write-Error -ErrorAction Stop
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName $ClientAppName `
                                                    -TrustServerCertificate -EncryptConnection -ErrorAction Stop -SqlCredential $PersonalCredential

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


# Find SQLAgent Jobs that need ATTENTION
$sqlGetJobsThatNeedAttention = @"
declare @_buffer_time_minutes int = 30;
declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = N'@_buffer_time_minutes int';
set quoted_identifier off;
set @_sql = "
select	/* [Tsql-Stop-Job] = 'exec msdb.dbo.sp_stop_job @job_name = '''+sj.JobName+'''' ,
		[Tsql-Start-Job] = 'exec msdb.dbo.sp_start_job @job_name = '''+sj.JobName+'''' , 
		*/
		[CollectionTimeUTC] = [UpdatedDateUTC],
		[sql_instance], sql_instance_with_port, [database], [JobName],
		[Job-Delay-Minutes] = case when sj.Last_Successful_ExecutionTime is null then 10080 else datediff(minute, sj.Last_Successful_ExecutionTime, dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@_buffer_time_minutes),getutcdate())) end,
		 [Last_RunTime], [Last_Run_Duration_Seconds], [Last_Run_Outcome], 
		 [Successfull_Execution_ClockTime_Threshold_Minutes], 
		 [Expected_Max_Duration_Minutes],
		 [Last_Successful_ExecutionTime], [Last_Successful_Execution_Hours], 
		 [Running_Since], [Running_StepName], [Running_Since_Min] 
from dbo.sql_agent_jobs_all_servers sj
cross apply (select top 1 sql_instance_with_port = coalesce(id.sql_instance +','+ id.sql_instance_port, id.sql_instance), [database]
             from dbo.instance_details id where id.sql_instance = sj.sql_instance and id.is_enabled = 1 and id.is_available = 1 and id.is_alias = 0) id
where 1=1
and sj.JobCategory = '(dba) SQLMonitor'
and sj.JobName like '(dba) %'
and sj.IsDisabled = 0
and (Successfull_Execution_ClockTime_Threshold_Minutes = -1
    or (	dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@_buffer_time_minutes),getutcdate()) > sj.Last_Successful_ExecutionTime
			or sj.Last_Successful_ExecutionTime is null
		)
    )
--order by Last_Run_Outcome
"
set quoted_identifier off;

exec sp_executesql @_sql, @_params, @_buffer_time_minutes = @_buffer_time_minutes;
"@

$agentJobs = @()
$agentJobs += $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlGetJobsThatNeedAttention

$servers = @()
$servers += $agentJobs | Where-Object {$_.Last_Run_Outcome -eq 'Succeeded'} | Select-Object -Property sql_instance,sql_instance_with_port,database -Unique

$serversNotConsidered = @()
$serversNotConsidered += $agentJobs | Where-Object {$_.Last_Run_Outcome -ne 'Succeeded'} | Select-Object -Property sql_instance,sql_instance_with_port,database -Unique

# Loop through servers list, and perform required action
[System.Collections.ArrayList]$successServers = @()
[System.Collections.ArrayList]$failedServers = @()
[System.Collections.ArrayList]$queryResult = @()

#$serversRemaining = $servers | ? {$_ -notin $successServers }
#$successServersFinal = $successServers

#$serversTest = @('192.168.1.15')

$sqlAddErrorLogEntry = @"
insert dbo.sma_errorlog
(function_name, function_call_arguments, server, error, executor_program_name)
select @function_name, @function_call_arguments, @server, @error, @executor_program_name
"@

foreach($srvDtls in $servers)
{
    $srv = $srvDtls.sql_instance_with_port
    $sqlInstance = $srvDtls.sql_instance
    $sqlInstanceWithPort = $srvDtls.sql_instance_with_port    
    $database = $srvDtls.database

    "Working on [$sqlInstance].." | Write-Host -ForegroundColor Cyan
    try {
        $srvObj = Connect-DbaInstance -SqlInstance $sqlInstanceWithPort -Database $database -ClientName $ClientAppName `
                            -SqlCredential $allServerLoginCredential -TrustServerCertificate -EncryptConnection -ErrorAction Stop

        # Update threshold using file script
        $srvObj | Invoke-DbaQuery -File $FileUpdateSQLAgentJobsThreshold -EnableException        
                
        $successServers.Add($sqlInstanceWithPort) | Out-Null
    }
    catch {
        $errMsg = $_.Exception.Message
        $failedServers.Add([PSCustomObject]@{server = $sqlInstance; error = $errMsg}) | Out-Null
        "`n`tError: $errMsg" | Write-Host -ForegroundColor Red

        $garbageText = 'Exception calling "EndInvoke" with "1" argument(s): '
        $sqlScriptFileName = (Get-Item $FileUpdateSQLAgentJobsThreshold).Name
        $errorParams = [ordered]@{
            function_name = $sqlScriptFileName
            function_call_arguments = 'Connect-DbaInstance & Invoke-DbaQuery'
            server = $srv
            error = $errMsg.Replace($garbageText,'')
            executor_program_name = $ClientAppName
        }
        "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Marking an entry in error log table dbo.sma_errorlog.." | Write-Output
        $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlAddErrorLogEntry `
                    -EnableException -ErrorAction Stop -SqlParameter $errorParams
    }
}

$successServers | ogv -Title "Successful"
$failedServers | ogv -Title "Failed"
$serversNotConsidered | ogv -Title "Not Considered Servers"

