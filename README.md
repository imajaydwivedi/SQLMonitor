# SQLMonitor - SQLServer Monitoring & Alerting

If you are a developer, or DBA who manages Microsoft SQL Servers, it becomes important to understand current load vs usual load when SQL Server is slow. This repository contains scripts that will help you to setup baseline on individual SQL Server instances, and then visualize the collected data using Grafana through one Inventory server with Linked Server for individual SQL Server instances.

Navigation
- [SQLMonitor - SQLServer Monitoring \& Alerting](#sqlmonitor---sqlserver-monitoring--alerting)
  - [Why SQLMonitor?](#why-sqlmonitor)
    - [Features](#features)
  - [Live Dashboard - Basic Metrics](#live-dashboard---basic-metrics)
  - [Live Dashboard - Perfmon Counters - Quest Softwares](#live-dashboard---perfmon-counters---quest-softwares)
    - [Portal Credentials](#portal-credentials)
  - [How to Setup](#how-to-setup)
    - [Jobs for SQLMonitor](#jobs-for-sqlmonitor)
    - [Download SQLMonitor](#download-sqlmonitor)
    - [Execute Wrapper Script](#execute-wrapper-script)
      - [Below is sample code present in `Wrapper-Samples/Wrapper-InstallSQLMonitor.ps1`](#below-is-sample-code-present-in-wrapper-sampleswrapper-installsqlmonitorps1)
    - [Setup Grafana Dashboards](#setup-grafana-dashboards)
  - [Remove SQLMonitor](#remove-sqlmonitor)
      - [Below is sample code present in `Wrapper-Samples/Wrapper-RemoveSQLMonitor.ps1`](#below-is-sample-code-present-in-wrapper-sampleswrapper-removesqlmonitorps1)
  - [Support](#support)
  - [Related Links](#related-links)

## Why SQLMonitor?
SQLMonitor is designed as open-source tool to replace expensive enterprise monitoring or to simply fill the gap and monitor all environments such as DEV, TEST, QA/UAT & PROD.

[![YouTube Tutorial on SQLMonitor](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor/YouTube-Thumbnail-Live-All-Servers.png)](https://ajaydwivedi.com/youtube/sqlmonitor)<br>

### Features
- Simple & customizable as metric collection happens through SQL Agent jobs.
- Easy to debug since entire SQLMonitor tools is built of just few tables, stored procedures & sql agent jobs.
- Grafana based Central & Individual dashboards to analyze metrics
- Collection jobs using stored procedures with data loading utilizing very small sized perfmon/xevent files puts very minimal performance overhead.
- Highly optimized grafana dashboard queries using dynamically Parameterized tsql makes the data visualization to scale well even when dashboard users increase.
- Near to zero manual configuration required. Purging controlled through just one table/job.
- Depending on version of SQL Server, tables are automatically "Hourly" partitioned & Compressed. So index or other maintenance not even required.
- Utilizing Memory Optimized tables on central server for core stability metric storage gives it Unlimited scalability.
- Tools has capability to allow same or different sql instance as Data Target. Thus gives high flexibility & scalability.
- Works with all supported SQL Servers (with some limitations on 2008R2 like XEvent not available).
- Alert Engine built with Python & SQLServer with PagerDuty, Slack & Email target.

![](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor-AlertEngine/Sma-Slack-3-Images-Gif.gif) <br>


## Live Dashboard - Basic Metrics
You can visit [https://sqlmonitor.ajaydwivedi.com](https://sqlmonitor.ajaydwivedi.com/d/distributed_live_dashboard/monitoring-live-distributed?orgId=1&refresh=5s) for live dashboard for basic real time monitoring.<br><br>

![](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor/Live-Dashboards-All.gif) <br>


## Live Dashboard - Perfmon Counters - Quest Softwares
Visit [https://sqlmonitor.ajaydwivedi.com](https://sqlmonitor.ajaydwivedi.com/d/distributed_perfmon/monitoring-perfmon-counters-quest-softwares-distributed?orgId=1&refresh=5m) for live dashboard of all Perfmon counters suggested in [SQL Server Perfmon Counters of Interest - Quest Software](https://drive.google.com/file/d/1LB7Joo6055T1FfPcholXByazOX55e5b8/view?usp=sharing).<br><br>

![](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor/Quest-Dashboards-All.gif) <br>

### Portal Credentials
Database/Grafana Portal | User Name | Password
------------ | --------- | ---------
[https://sqlmonitor.ajaydwivedi.com/](https://sqlmonitor.ajaydwivedi.com/dashboards?tag=sqlmonitor) | guest | ajaydwivedi-guest
Sql Instance -> sqlmonitor.ajaydwivedi.com:1433 | grafana | grafana

## How to Setup
SQLMonitor supports both Central & Distributed topology. In preferred distributed topology, each SQL Server instance monitors itself. The required objects like tables, view, functions, procedures, scripts, jobs etc. are created on the monitored instance itself.

SQLMonitor utilizes PowerShell script to collect various metric from operating system including setting up Perfmon data collector, pushing the collected perfmon data to sql tables, collecting os processes running etc.

For collecting metrics available from inside SQL Server, it used standard tsql procedures.

All the objects are created in [`DBA`] databases. Only few stored procedures that should have capability to be executed from context of any databases are created in [master] database.

For both OS metrics & SQL metric, SQL Agent jobs are used as schedulers. Each job has its own schedule which may differ in frequency of data collection from every one minute to once a week.

![](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor/SQLMonitor-Distributed-Topology.png) <br>

### Jobs for SQLMonitor

Following are few of the SQLMonitor data collection jobs. Each of these jobs is set to `(dba) SQLMonitor` job category along with fixed naming convention of `(dba) *********`.

<details>

<summary> SQLAgent Jobs Created by SQLMonitor </summary>

| Job Name                          | Job Category     | Schedule         | Job Type   | Location               |
| ---------------------------------:|:----------------:|:----------------:|:----------:|:----------------------:|
| (dba) Check-InstanceAvailability  | (dba) SQLMonitor | Every 1 minute   | PowerShell | Inventory Server       |
| (dba) Get-AllServerInfo           | (dba) SQLMonitor | Every 1 minute   | TSQL       | Inventory Server       |
| (dba) Get-AllServerCollectedData  | (dba) SQLMonitor | Every 5 minute   | TSQL       | Inventory Server       |
| (dba) Update-SqlServerVersions    | (dba) SQLMonitor | Once a week      | PowerShell | Inventory Server       |
| (dba) Collect-PerfmonData         | (dba) SQLMonitor | Every 2 minute   | PowerShell | PowerShell Jobs Server |
| (dba) Check-SQLAgentJobs          | (dba) SQLMonitor | Every 5 minute   | TSQL       | Tsql Jobs Server       |
| (dba) Collect-AgHealthState       | (dba) SQLMonitor | Every 2 minute   | TSQL       | Tsql Jobs Server       |
| (dba) Collect-DiskSpace           | (dba) SQLMonitor | Every 30 minutes | PowerShell | PowerShell Jobs Server |
| (dba) Collect-FileIOStats         | (dba) SQLMonitor | Every 10 minute  | TSQL       | Tsql Jobs Server       |
| (dba) Collect-MemoryClerks        | (dba) SQLMonitor | Every 2 minute   | TSQL       | Tsql Jobs Server       |
| (dba) Collect-OSProcesses         | (dba) SQLMonitor | Every 2 minute   | PowerShell | PowerShell Jobs Server |
| (dba) Collect-PrivilegedInfo      | (dba) SQLMonitor | Every 10 minute  | TSQL       | Tsql Jobs Server       |
| (dba) Collect-WaitStats           | (dba) SQLMonitor | Every 10 minutes | TSQL       | Tsql Jobs Server       |
| (dba) Collect-XEvents             | (dba) SQLMonitor | Every minute     | TSQL       | Tsql Jobs Server       |
| (dba) Partitions-Maintenance      | (dba) SQLMonitor | Every Day        | TSQL       | Tsql Jobs Server       |
| (dba) Purge-Tables                | (dba) SQLMonitor | Every Day        | TSQL       | Tsql Jobs Server       |
| (dba) Remove-XEventFiles          | (dba) SQLMonitor | Every 4 hours    | PowerShell | PowerShell Jobs Server |
| (dba) Run-Blitz                   | (dba) SQLMonitor | Once a Week      | TSQL       | Tsql Jobs Server       |
| (dba) Run-BlitzIndex              | (dba) SQLMonitor | Every Day        | TSQL       | Tsql Jobs Server       |
| (dba) Run-BlitzIndex - Weekly     | (dba) SQLMonitor | Once a Week      | TSQL       | Tsql Jobs Server       |
| (dba) Run-LogSaver                | (dba) SQLMonitor | Every 5 minutes  | TSQL       | Tsql Jobs Server       |
| (dba) Run-TempDbSaver             | (dba) SQLMonitor | Every 5 minutes  | TSQL       | Tsql Jobs Server       |
| (dba) Run-WhoIsActive             | (dba) SQLMonitor | Every 2 minute   | TSQL       | Tsql Jobs Server       |

----

`PowerShell Jobs Server` can be same SQL Instance that is being baselined, or some other server in same Cluster network, or some some other server in same network, or even Inventory Server.

`Tsql Jobs Server` can be same SQL Instance that is being baselined, or some other server in same Cluster network, or some some other server in same network, or even Inventory Server.

</details>

### Download SQLMonitor
Download SQLMonitor repository on your central server from where you deploy your scripts on all other servers. Say, after closing SQLMonitor, our local repo directory is `D:\Ajay-Dwivedi\GitHub-Personal\SQLMonitor`.

If the local SQLMonitor repo folder already exists, simply pull the latest from master branch.

### Execute Wrapper Script
Create a directory named Private inside SQLMonitor, and copy the scripts of `SQLMonitor\Wrapper-Samples\` into `SQLMonitor\Private\` folder.
Open the script `D:\Ajay-Dwivedi\GitHub-Personal\SQLMonitor\Private\Wrapper-InstallSQLMonitor.ps1`. Replace the appropriate values for parameters, and execute the script.

#### Below is sample code present in `Wrapper-Samples/Wrapper-InstallSQLMonitor.ps1`

<details>
<summary>Wrapper-Samples/Wrapper-InstallSQLMonitor.ps1</summary>

```Wrapper-InstallSQLMonitor

#$DomainCredential = Get-Credential -UserName 'Lab\SQLServices' -Message 'AD Account'
#$saAdmin = Get-Credential -UserName 'sa' -Message 'sa'
#$localAdmin = Get-Credential -UserName 'Administrator' -Message 'Local Admin'

cls
Import-Module dbatools;
$params = @{
    SqlInstanceToBaseline = 'Workstation'
    DbaDatabase = 'DBA'
    #HostName = 'Workstation'
    #RetentionDays = 7
    DbaToolsFolderPath = 'D:\Github\dbatools' # Download using Save-Module command
    #FirstResponderKitZipFile = 'D:\Softwares\SQL-Server-First-Responder-Kit-20231010.zip' # Download from Releases section
    #DarlingDataZipFile = 'D:\Softwares\DarlingData-main.zip' # Download from Code dropdown    
    #OlaHallengrenSolutionZipFile = 'D:\Github\sql-server-maintenance-solution-master.zip' # Download from Code dropdown
    #RemoteSQLMonitorPath = 'C:\SQLMonitor'
    InventoryServer = 'SQLMonitor'
    InventoryDatabase = 'DBA'
    DbaGroupMailId = 'some_dba_mail_id@gmail.com'
    #SqlCredential = $personal
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
                "25__CreateJobRunBlitzIndex", "26__CreateJobRunBlitz", "27__CreateJobRunBlitzIndexWeekly",
                "28__CreateJobCollectMemoryClerks", "29__CreateJobCollectPrivilegedInfo", "30__CreateJobCollectAgHealthState",
                "31__CreateJobCheckSQLAgentJobs", "32__CreateJobUpdateSqlServerVersions", "33__CreateJobCheckInstanceAvailability",
                "34__CreateJobGetAllServerInfo", "35__CreateJobGetAllServerCollectedData", "36__WhoIsActivePartition",
                "37__BlitzIndexPartition", "38__BlitzPartition", "39__EnablePageCompression",
                "40__GrafanaLogin", "41__LinkedServerOnInventory", "42__LinkedServerForDataDestinationInstance",
                "43__AlterViewsForDataDestinationInstance")
    #>
    #OnlySteps = @( "2__AllDatabaseObjects", "29__CreateJobCollectAgHealthState" )
    #StartAtStep = '1__sp_WhoIsActive'
    #StopAtStep = '39__AlterViewsForDataDestinationInstance'
    #DropCreatePowerShellJobs = $true
    #DryRun = $false
    #SkipRDPSessionSteps = $true
    #SkipPowerShellJobs = $true
    #SkipTsqlJobs = $true
    #SkipMailProfileCheck = $true
    #skipCollationCheck = $true
    #SkipWindowsAdminAccessTest = $true
    #SkipDriveCheck = $true
    #SkipPingCheck = $true
    #SkipMultiServerviewsUpgrade = $false
    #ForceSetupOfTaskSchedulerJobs = $true
    #SqlInstanceAsDataDestination = 'Workstation'
    #SqlInstanceForPowershellJobs = 'Workstation'
    #SqlInstanceForTsqlJobs = 'Workstation'
    #ConfirmValidationOfMultiInstance = $true
    #ConfirmSetupOfTaskSchedulerJobs = $true
    #HasCustomizedTsqlJobs = $true
    #HasCustomizedPowerShellJobs = $true
    #OverrideCustomizedTsqlJobs = $false
    #OverrideCustomizedPowerShellJobs = $false
    #UpdateSQLAgentJobsThreshold = $false
    #XEventDirectory = 'D:\MSSQL15.MSSQLSERVER\XEvents\'
    #JobsExecutionWaitTimeoutMinutes = 15
}


#$preSQL = "EXEC dbo.usp_check_sql_agent_jobs @default_mail_recipient = 'sqlagentservice@gmail.com', @drop_recreate = 1"
#$postSQL = Get-Content "D:\GitHub-Personal\SQLMonitor\DDLs\Update-SQLAgentJobsThreshold.sql"
#D:\GitHub\SQLMonitor\SQLMonitor\Install-SQLMonitor.ps1 @Params #-Debug -PreQuery $preSQL -PostQuery $postSQL
D:\GitHub\SQLMonitor\SQLMonitor\Install-SQLMonitor.ps1 @Params

#Get-Help F:\GitHub\SQLMonitor\SQLMonitor\Install-SQLMonitor.ps1 -ShowWindow

<#
$dropWhoIsActive = @"
if object_id('dbo.WhoIsActive_Staging') is not null
	drop table dbo.WhoIsActive_Staging;

if object_id('dbo.WhoIsActive') is not null
	drop table dbo.WhoIsActive;
"@;
F:\GitHub\SQLMonitor\SQLMonitor\Install-SQLMonitor.ps1 @Params -PreQuery $dropWhoIsActive
#>

<#
# **************** Download other github repos/modules/files ***********************

# **__ SQLMonitor __**
Invoke-WebRequest https://github.com/imajaydwivedi/SQLMonitor/archive/refs/heads/dev.zip `
            -OutFile "$($env:USERPROFILE)\Downloads\sqlmonitor.zip"

# **__ dbatools & dbatools.library __**
Save-Module dbatools -Path "$($env:USERPROFILE)\Downloads\"

# **__ PoshRSJob on Inventory __**
Install-Module PoshRSJob -Scope AllUsers -Verbose
Save-Module PoshRSJob -Path "$($env:USERPROFILE)\Downloads\"

# **__ Darling Data __**
Invoke-WebRequest https://github.com/erikdarlingdata/DarlingData/archive/refs/heads/main.zip `
            -OutFile "$($env:USERPROFILE)\Downloads\DarlingData-main.zip"

# **__ Ola Hallengren Maintenance Solution __**
Invoke-WebRequest https://github.com/olahallengren/sql-server-maintenance-solution/archive/refs/heads/master.zip `
            -OutFile "$($env:USERPROFILE)\Downloads\sql-server-maintenance-solution-master.zip"

# **__ First Responder Kit from latest release __**
if ($true) {
    $repo = "BrentOzarULTD/SQL-Server-First-Responder-Kit"
    $tags = "https://api.github.com/repos/$repo/tags"

    $tagName = (Invoke-WebRequest $tags | ConvertFrom-Json)[0].name
    $releaseZip = "https://github.com/$repo/archive/refs/tags/$tagName.zip"

    Invoke-WebRequest $releaseZip `
            -OutFile "$($env:USERPROFILE)\Downloads\SQL-Server-First-Responder-Kit-$tagName.zip"
}

# **__ PoshRSJob - Download from Github __**
if ($true) {
    $repo = "proxb/PoshRSJob"
    $releases = "https://api.github.com/repos/$repo/releases"

    $tagName = (Invoke-WebRequest $releases | ConvertFrom-Json)[0].tag_name
    $releaseZip = "https://github.com/$repo/releases/download/$tagName/PoshRSJob.zip"

    Invoke-WebRequest $releaseZip `
            -OutFile "$($env:USERPROFILE)\Downloads\PoshRSJob.zip"
}

#>

<#
Get-DbaDbMailProfile -SqlInstance '192.168.56.31' -SqlCredential $personalCredential
Copy-DbaDbMail -Source '192.168.56.15' -Destination '192.168.56.31' -SourceSqlCredential $personalCredential -DestinationSqlCredential $personalCredential # Lab
New-DbaCredential -SqlInstance 'xy' -Identity $LabCredential.UserName -SecurePassword $LabCredential.Password -Force # -SqlCredential $SqlCredential -EnableException
New-DbaAgentProxy -SqlInstance 'xy' -Name $LabCredential.UserName -ProxyCredential $LabCredential.UserName -SubSystem PowerShell,CmdExec

Enable-PSRemoting -Force -SkipNetworkProfileCheck # remote machine
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value SQLMonitor.Lab.com -Concatenate -Force # remote machine
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy
Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1

# Incase 
#Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value * -Force # run on local machine
#Set-NetConnectionProfile -NetworkCategory Private # Execute this only if above command fails

Enter-PSSession -ComputerName '192.168.56.31' -Credential $localAdmin -Authentication Negotiate
Test-WSMan '192.168.56.31' -Credential $localAdmin -Authentication Negotiate

Get-ChildItem C:\SQLMonitor -Recurse -File | Unblock-File -Verbose
#>

<#
# Add SQLAgent Service Account to below local windows groups.
    # Computer Management > System Tools > Local Users and Groups > Groups
1) Administrators
2) Performance Log Users
3) Performance Monitor Users
#>

```
</details>

----

> [!IMPORTANT]
> To get a better understand of SQLMonitor installation, I would recommend to watch [YouTube Playlist](https://ajaydwivedi.com/youtube/sqlmonitor) [https://ajaydwivedi.com/youtube/sqlmonitor](https://ajaydwivedi.com/youtube/sqlmonitor).


### Setup Grafana Dashboards
Download Grafana which is open source visualization tool. Install & configure same.

Create a datasource on Grafana that connects to your Inventory Server. Say, we set it with name 'SQLMonitor'. Use `grafana` as login & password while setting up this data source. The `grafana` sql login is created on each server being baselined with `db_datareader` on `DBA` database.

At next step, import all the dashboard `*.json` files on path `D:\Ajay-Dwivedi\GitHub-Personal\SQLMonitor\Grafana-Dashboards` into `SQLServer` folder on grafana portal. While importing each JSON file, we need to explicitly choose `SQLMonitor` Data Source & Folder we created in above steps.

## Remove SQLMonitor
Similar to `Wrapper-InstallSQLMonitor`, we have `Wrapper-RemoveSQLMonitor` that can help us remove SQLMonitor for a particular baselined server.
Ensure that all scripts from folder `\SQLMonitor\Wrapper-Samples\` are copied into `\SQLMonitor\Private\` folder.

Open script `D:\Ajay-Dwivedi\GitHub-Personal\SQLMonitor\Private\Wrapper-RemoveSQLMonitor.ps1`. Replace the appropriate values for parameters, and execute the script.

#### Below is sample code present in `Wrapper-Samples/Wrapper-RemoveSQLMonitor.ps1`

<details>
<summary>Wrapper-Samples/Wrapper-RemoveSQLMonitor.ps1</summary>

```Wrapper-RemoveSQLMonitor

#$DomainCredential = Get-Credential -UserName 'Lab\SQLServices' -Message 'AD Account'
#$saAdmin = Get-Credential -UserName 'sa' -Message 'sa'
#$localAdmin = Get-Credential -UserName 'Administrator' -Message 'Local Admin'

cls
Import-Module dbatools;
$params = @{
    SqlInstanceToBaseline = 'Experiment'
    #DbaDatabase = 'DBA'
    #HostName = 'Experiment'
    InventoryServer = 'SQLMonitor'
    InventoryDatabase = 'DBA'
    #RemoteSQLMonitorPath = 'C:\SQLMonitor'
    #SqlCredential = $saAdmin
    #WindowsCredential = $localAdmin
    #SkipRDPSessionSteps = $true
    #SkipSteps = @("43__RemovePerfmonFilesFromDisk")    
    #StartAtStep = '30__DropLogin_Grafana'
    #StopAtStep = '11__RemoveJob_RunBlitzIndex'
    #SqlInstanceForTsqlJobs = 'Experiment\SQL2019'
    #SqlInstanceAsDataDestination = 'Experiment\SQL2019'
    #SqlInstanceForPowershellJobs = 'Experiment\SQL2019'
    SkipDropTable = $true
    #SkipRemoveJob = $true
    #SkipDropProc = $true
    #SkipDropView = $true
    #ConfirmValidationOfMultiInstance = $true
    #ActionType = "Update"
    #OnlySteps = @("16__RemoveJob_RunBlitz","70__DropTable_Blitz")
    #DryRun = $false
}

#$preSQL = "EXEC dbo.usp_check_sql_agent_jobs @default_mail_recipient = 'sqlagentservice@gmail.com', @drop_recreate = 1"
#$postSQL = Get-Content "D:\GitHub-Personal\SQLMonitor\DDLs\Update-SQLAgentJobsThreshold.sql"
#D:\GitHub\SQLMonitor\SQLMonitor\Remove-SQLMonitor.ps1 @Params #-Debug -PreQuery $preSQL -PostQuery $postSQL
D:\GitHub\SQLMonitor\SQLMonitor\Remove-SQLMonitor.ps1 @Params


#Get-DbaDbMailProfile -SqlInstance '192.168.56.31' -SqlCredential $personalCredential
#Copy-DbaDbMail -Source '192.168.56.15' -Destination '192.168.56.31' -SourceSqlCredential $personalCredential -DestinationSqlCredential $personalCredential # Lab
#New-DbaCredential -SqlInstance 'xy' -Identity $LabCredential.UserName -SecurePassword $LabCredential.Password -Force # -SqlCredential $SqlCredential -EnableException
#New-DbaAgentProxy -SqlInstance 'xy' -Name $LabCredential.UserName -ProxyCredential $LabCredential.UserName -SubSystem PowerShell,CmdExec
<#

Enable-PSRemoting -Force # run on remote machine
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value * -Force # run on local machine
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value 192.168.56.15 -Force
#Set-NetConnectionProfile -NetworkCategory Private # Execute this only if above command fails

Enter-PSSession -ComputerName '192.168.56.31' -Credential $localAdmin -Authentication Negotiate
Test-WSMan '192.168.56.31' -Credential $localAdmin -Authentication Negotiate

#>


```
</details>



## Support

For community support regarding this tool, kindly join [#sqlmonitor](https://ajaydwivedi.com/sqlmonitor/slack) channel on [sqlcommunity.slack.com](https://ajaydwivedi.com/join/slack) slack workspace.
For paid support, reach out to me directly on [#sqlmonitor](https://ajaydwivedi.com/go/slack) slack channel.

## Related Links
- Github Repo -> [https://ajaydwivedi.com/github/sqlmonitor](https://ajaydwivedi.com/github/sqlmonitor)
- Demo Site -> [https://ajaydwivedi.com/demo/sqlmonitor](https://ajaydwivedi.com/demo/sqlmonitor)
- Demo site Credentials -> [https://ajaydwivedi.com/go/sqlmonitor](https://ajaydwivedi.com/go/sqlmonitor)
- YouTube Playlist -> [https://ajaydwivedi.com/youtube/sqlmonitor](https://ajaydwivedi.com/youtube/sqlmonitor)
- Blogs -> [https://ajaydwivedi.com/category/sqlmonitor](https://ajaydwivedi.com/category/sqlmonitor)
- Community Help on **#sqlmonitor** channel -> [https://ajaydwivedi.com/sqlmonitor/slack](https://ajaydwivedi.com/sqlmonitor/slack)

-----------------------------

Thanks :smiley:. Subscribe for updates :thumbsup:
