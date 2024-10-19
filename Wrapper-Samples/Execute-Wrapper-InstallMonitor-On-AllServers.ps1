#$DomainCredential = Get-Credential -UserName 'Lab\SQLServices' -Message 'AD Account'
#$saAdmin = Get-Credential -UserName 'sa' -Message 'sa'
#$localAdmin = Get-Credential -UserName 'Administrator' -Message 'Local Admin'

cls
$InventoryServer = 'localhost' 
$InventoryDatabase = 'DBA'
$CredentialManagerDatabase = 'DBA'
$AllServerLogin = 'sa'

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName "Execute-Wrapper-InstallMonitor-On-AllServers.ps1" `
                                                    -TrustServerCertificate -ErrorAction Stop -SqlCredential $personal
<#
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
#>

$sqlGetAllServers = @"
;with t_servers as (
	select *
			,row_id = ROW_NUMBER()over(partition by sql_instance, [database] order by created_date_utc)
	from dbo.instance_details id
    where 1=1
    and id.is_enabled = 1
    and id.is_alias = 0
    and convert(date,id.sqlmonitor_version) < '2024-04-26'
)
select sql_instance = coalesce(sql_instance+','+sql_instance_port,sql_instance), 
		[database], [host_name]
from t_servers
where row_id = 1
"@

$allServersList = Invoke-DbaQuery -SqlInstance $conInventoryServer -Database $InventoryDatabase -Query $sqlGetAllServers;
#$allServersList = $allServersList | Where-Object {$_.sql_instance -in $failedServers}

# Execute SQL files & SQL Query
[System.Collections.ArrayList]$failedServers = @()
$successServers = @()
$allServersListFiltered = @()
$allServersListFiltered += $allServersList | ? {$_.sql_instance -notin @($env:COMPUTERNAME)} | Select-Object sql_instance, database, host_name -Unique
#$allServersListFiltered += $allServersList | ? {$_.sql_instance -in $failedServers2}
#$allServersListFiltered += $allServersList | ? {$_.sql_instance -in @('10.10.10.10')} | Select-Object sql_instance, database, host_name -Unique
#$allServersListFiltered += $allServersList | Select-Object sql_instance, database, host_name -Unique

#$failedServersList = $failedServers
#$allServersListFiltered += $allServersList | ? {$_.sql_instance -in $failedServersList} | Select-Object sql_instance, database, host_name -Unique

#$preSQL = "drop table [dbo].[server_privileged_info]"
#$postSQL = "EXEC dbo.usp_check_sql_agent_jobs @default_mail_recipient = 'sqlagentservice@gmail.com', @drop_recreate = 1"
#$postSQL = Get-Content "D:\GitHub\SQLMonitor\DDLs\Update-SQLAgentJobsThreshold.sql" | Out-String

foreach($srv in $allServersListFiltered)
{
    $sqlInstance = $srv.sql_instance
    if($sqlInstance -eq $env:COMPUTERNAME) { continue; }
    $database = $srv.database
    $hostName = $srv.host_name
    "Working on [$sqlInstance]" | Write-Host -ForegroundColor Cyan

    try {
        $params = @{
            SqlInstanceToBaseline = $sqlInstance
            DbaDatabase = $database
            HostName = $hostName
            #RetentionDays = 7
            DbaToolsFolderPath = 'D:\Softwares\dbatools' # Download from Releases section
            FirstResponderKitZipFile = 'D:\Softwares\SQL-Server-First-Responder-Kit-20230613.zip' # Download from Releases section
            DarlingDataZipFile = 'D:\Softwares\DarlingData-main.zip' # Download from Code dropdown    
            OlaHallengrenSolutionZipFile = 'D:\Softwares\sql-server-maintenance-solution-master.zip' # Download from Code dropdown
            #RemoteSQLMonitorPath = 'C:\SQLMonitor'
            InventoryServer = $InventoryServer
            InventoryDatabase = $InventoryDatabase
            DbaGroupMailId = 'sqlagentservice@gmail.com'
            SqlCredential = $allServerLoginCredential
            #WindowsCredential = $DomainCredential
            <#
            SkipSteps = @( "1__sp_WhoIsActive", "2__AllDatabaseObjects", "3__XEventSession",
                "4__FirstResponderKitObjects", "5__DarlingDataObjects", "6__OlaHallengrenSolutionObjects",
                "7__sp_WhatIsRunning", "8__usp_GetAllServerInfo", "9__CopyDbaToolsModule2Host",
                "10__CopyPerfmonFolder2Host", "11__SetupPerfmonDataCollector", "12__CreateCredentialProxy",
                "13__CreateJobCollectDiskSpace", "14__CreateJobCollectOSProcesses", "15__CreateJobCollectPerfmonData",
                "16__CreateJobCollectWaitStats", "17__CreateJobCollectXEvents", "18__CreateJobCollectFileIOStats",
                "19__CreateJobPartitionsMaintenance", "20__CreateJobPurgeTables", "21__CreateJobRemoveXEventFiles",
                "22__CreateJobRunLogSaver", "23__CreateJobRunTempDbSaver", "24__CreateJobRunWhoIsActive",
                "25__CreateJobRunBlitz", "25__CreateJobRunBlitzIndex", "27__CreateJobRunBlitzIndexWeekly",
                "28__CreateJobCollectMemoryClerks", "29__CreateJobCollectPrivilegedInfo", "30__CreateJobCollectAgHealthState",
                "31__CreateJobCheckSQLAgentJobs", "32__CreateJobCaptureAlertMessages", "33__CreateSQLAgentAlerts",
                "34__CreateJobUpdateSqlServerVersions", "35__CreateJobCheckInstanceAvailability", "36__CreateJobGetAllServerStableInfo",
                "37__CreateJobGetAllServerVolatileInfo", "38__CreateJobGetAllServerCollectionLatencyInfo", "39__CreateJobGetAllServerSqlAgentJobs",
                "40__CreateJobGetAllServerDiskSpace", "41__CreateJobGetAllServerLogSpaceConsumers", "42__CreateJobGetAllServerTempdbSpaceUsage",
                "43__CreateJobGetAllServerAgHealthState", "44__CreateJobGetAllServerServices", "45__CreateJobGetAllServerBackups",
                "46__CreateJobGetAllServerDashboardMail", "47__CreateJobStopStuckSQLMonitorJobs", "48__CreateJobCollectLoginExpirationInfo",
                "49__CreateJobPopulateInventoryTables", "50__CreateJobSendLoginExpiryEmails", "51__WhoIsActivePartition",
                "52__BlitzIndexPartition", "53__BlitzPartition", "54__EnablePageCompression",
                "55__GrafanaLogin", "56__LinkedServerOnInventory", "57__LinkedServerForDataDestinationInstance",
                "58__AlterViewsForDataDestinationInstance")
            #>
            OnlySteps = @( "2__AllDatabaseObjects","32__CreateJobCaptureAlertMessages","33__CreateSQLAgentAlerts" )
            #StartAtStep = '21__CreateJobRemoveXEventFiles'
            #StopAtStep = '32__AlterViewsForDataDestinationInstance'
            #DropCreatePowerShellJobs = $true
            #DryRun = $false
            SkipRDPSessionSteps = $true
            SkipPowerShellJobs = $true
            #SkipTsqlJobs = $true
            SkipMailProfileCheck = $true
            skipCollationCheck = $true
            SkipWindowsAdminAccessTest = $true
            SkipDriveCheck = $true
            SkipPingCheck = $true
            #ForceSetupOfTaskSchedulerJobs = $true
            #SqlInstanceAsDataDestination = 'Workstation'
            #SqlInstanceForPowershellJobs = 'Workstation'
            #SqlInstanceForTsqlJobs = 'Workstation'
            #ConfirmValidationOfMultiInstance = $true
            #ConfirmSetupOfTaskSchedulerJobs = $true
            #ConfirmSetupOfTaskSchedulerJobs = $true
            #HasCustomizedTsqlJobs = $true
            #HasCustomizedPowerShellJobs = $true
            #OverrideCustomizedTsqlJobs = $true
            #OverrideCustomizedPowerShellJobs = $false
            #UpdateSQLAgentJobsThreshold = $false
            ReturnInlineErrorMessage = $true
        }
        #$preSQL = "drop table [dbo].[server_privileged_info]"
        #$postSQL = Get-Content "D:\GitHub-Personal\SQLMonitor\DDLs\Update-SQLAgentJobsThreshold.sql" | Out-String
        #$postSQL = "exec usp_LogSaver @drop_create_table = 1, @email_recipients = 'sqlagentservice.com'"
        D:\Github\SQLMonitor\SQLMonitor\Install-SQLMonitor.ps1 @Params #-PostQuery $postSQL
        
        $successServers += $sqlInstance
    }
    catch {
        $errMessage = $_
        #$failedServers += $sqlInstance
        $failedServers.Add([PSCustomObject]@{sql_instance = $sqlInstance; error_message = $errMessage}) | Out-Null
        #$failedServers
        $errMessage.Exception | Write-Host -ForegroundColor Red
        "`n"
    }
}


$failedServers | ogv -Title "Failed"
$successServers | ogv -Title "Successful"