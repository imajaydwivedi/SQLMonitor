# Install Steps

`Install-SQLMonitor.ps1` runs up to 59 named steps in order. This page explains what each step does so you can `-SkipSteps`, `-StartAtStep`, `-StopAtStep`, or `-OnlySteps` with confidence.

!!! note "Authoritative source"
    The canonical step list is the `ValidateSet` on `-OnlySteps` in [`Install-SQLMonitor.ps1`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/SQLMonitor/Install-SQLMonitor.ps1). This page mirrors that list.

## Phase 1 &mdash; Core database objects (steps 1&ndash;8)

| # | Step | What it does |
|---|---|---|
| 1 | `1__sp_WhoIsActive` | Installs Adam Machanic's `sp_WhoIsActive` into `DBA`. |
| 2 | `2__AllDatabaseObjects` | Runs `DDLs/SCH-Create-All-Objects.sql` &mdash; tables, views, procs, the CLR assembly and all core `dbo.*` objects. The heaviest step. |
| 3 | `3__XEventSession` | Creates the `XEventMetrics` Extended Event session targeting a file under `RemoteSQLMonitorPath`. |
| 4 | `4__FirstResponderKitObjects` | Expands `FirstResponderKitZipFile` and runs its Install-All-Scripts into `DBA`. |
| 5 | `5__DarlingDataObjects` | Expands `DarlingDataZipFile` and installs `sp_HumanEvents`, `sp_PressureDetector`, etc. into `DBA`. |
| 6 | `6__OlaHallengrenSolutionObjects` | Installs the Ola Hallengren maintenance solution into `DBA`. |
| 7 | `7__sp_WhatIsRunning` | Installs the `dbo.sp_WhatIsRunning` wrapper proc. |
| 8 | `8__usp_GetAllServerInfo` | Installs `dbo.usp_GetAllServerInfo` and its family of helpers. |

## Phase 2 &mdash; Host-side setup (steps 9&ndash;12)

| # | Step | What it does |
|---|---|---|
| 9 | `9__CopyDbaToolsModule2Host` | Copies the `dbatools` module from the deployer to the monitored host so jobs can `Import-Module` it locally. |
| 10 | `10__CopyPerfmonFolder2Host` | Copies `SQLMonitor/*.ps1` collectors to `C:\SQLMonitor\` (or `RemoteSQLMonitorPath`). |
| 11 | `11__SetupPerfmonDataCollector` | Creates a Perfmon `logman` Data Collector Set that writes `.blg` files every 10 seconds. |
| 12 | `12__CreateCredentialProxy` | Creates the SQL credential and SQL Agent proxy that wrap `WindowsCredential`, used by all PowerShell and CmdExec subsystem job steps. |

## Phase 3 &mdash; Per-instance collection jobs (steps 13&ndash;31)

| # | Step | Creates job |
|---|---|---|
| 13 | `13__CreateJobCollectDiskSpace` | `(dba) Collect-DiskSpace` |
| 14 | `14__CreateJobCollectPerfmonData` | `(dba) Collect-PerfmonData` |
| 15 | `15__CreateJobCollectWaitStats` | `(dba) Collect-WaitStats` |
| 16 | `16__CreateJobCollectXEvents` | `(dba) Collect-XEvents` |
| 17 | `17__CreateJobCollectFileIOStats` | `(dba) Collect-FileIOStats` |
| 18 | `18__CreateJobPartitionsMaintenance` | `(dba) Partitions-Maintenance` |
| 19 | `19__CreateJobPurgeTables` | `(dba) Purge-Tables` |
| 20 | `20__CreateJobRemoveXEventFiles` | `(dba) Remove-XEventFiles` |
| 21 | `21__CreateJobRunLogSaver` | `(dba) Run-LogSaver` |
| 22 | `22__CreateJobRunTempDbSaver` | `(dba) Run-TempDbSaver` |
| 23 | `23__CreateJobRunWhoIsActive` | `(dba) Run-WhoIsActive` |
| 24 | `24__CreateJobRunBlitz` | `(dba) Run-Blitz` |
| 24 | `24__CreateJobRunBlitzIndex` | `(dba) Run-BlitzIndex` |
| 26 | `26__CreateJobRunBlitzIndexWeekly` | `(dba) Run-BlitzIndexWeekly` |
| 27 | `27__CreateJobCollectMemoryClerks` | `(dba) Collect-MemoryClerks` |
| 28 | `28__CreateJobCollectPrivilegedInfo` | `(dba) Collect-PrivilegedInfo` |
| 29 | `29__CreateJobCollectAgHealthState` | `(dba) Collect-AgHealthState` |
| 30 | `30__CreateJobCheckSQLAgentJobs` | `(dba) Check-SQLAgentJobs` |
| 31 | `31__CreateJobCaptureAlertMessages` | `(dba) Capture-AlertMessages` |

## Phase 4 &mdash; SQL Agent alerts & availability (step 32&ndash;34)

| # | Step | What it does |
|---|---|---|
| 32 | `32__CreateSQLAgentAlerts` | Creates SQL Agent alerts for severities 17&ndash;25 and specific error numbers (deadlocks, &hellip;), routed to `(dba) Capture-AlertMessages`. |
| 33 | `33__CreateJobUpdateSqlServerVersions` | `(dba) Update-SqlServerVersions` &mdash; keeps `dbo.sql_server_versions` fresh with CU metadata. |
| 34 | `34__CreateJobCheckInstanceAvailability` | `(dba) Check-InstanceAvailability` &mdash; pings every instance in `dbo.sma_sql_instance` from the inventory server. |

## Phase 5 &mdash; Inventory aggregation jobs (steps 35&ndash;51)

These steps run on the **inventory** server. Skipped when `-SkipInventorySteps $true` or when `InstanceScopeFeaturesOnly $true`.

| # | Step | Creates job |
|---|---|---|
| 35 | `35__CreateJobGetAllServerStableInfo` | `(dba) Get-AllServerStableInfo` |
| 36 | `36__CreateJobGetAllServerVolatileInfo` | `(dba) Get-AllServerVolatileInfo` |
| 37 | `37__CreateJobGetAllServerCollectionLatencyInfo` | `(dba) Get-AllServerCollectionLatencyInfo` |
| 38 | `38__CreateJobGetAllServerSqlAgentJobs` | `(dba) Get-AllServerSqlAgentJobs` |
| 39 | `39__CreateJobGetAllServerDiskSpace` | `(dba) Get-AllServerDiskSpace` |
| 40 | `40__CreateJobGetAllServerLogSpaceConsumers` | `(dba) Get-AllServerLogSpaceConsumers` |
| 41 | `41__CreateJobGetAllServerTempdbSpaceUsage` | `(dba) Get-AllServerTempdbSpaceUsage` |
| 42 | `42__CreateJobGetAllServerAgHealthState` | `(dba) Get-AllServerAgHealthState` |
| 43 | `43__CreateJobGetAllServerServices` | `(dba) Get-AllServerServices` |
| 44 | `44__CreateJobGetAllServerBackups` | `(dba) Get-AllServerBackups` |
| 45 | `45__CreateJobGetAllServerAlertHistory` | `(dba) Get-AllServerAlertHistory` |
| 46 | `46__CreateJobGetAllServerDashboardMail` | `(dba) Get-AllServerDashboardMail` |
| 47 | `47__CreateJobStopStuckSQLMonitorJobs` | `(dba) Stop-StuckSQLMonitorJobs` |
| 48 | `48__CreateJobCollectLoginExpirationInfo` | `(dba) Collect-LoginExpirationInfo` |
| 49 | `49__CreateJobPopulateInventoryTables` | `(dba) Populate Inventory Tables` |
| 50 | `50__CreateJobSendLoginExpiryEmails` | `(dba) Send login expiry eMails` |
| 51 | `51__CreateJobComputeAllServerVolatileInfoHistoryHourly` | `(dba) Compute-AllServerVolatileInfoHistoryHourly` |

## Phase 6 &mdash; Partitioning & compression (steps 52&ndash;55)

| # | Step | What it does |
|---|---|---|
| 52 | `52__WhoIsActivePartition` | Applies hourly partition function / scheme to `dbo.WhoIsActive`. |
| 53 | `53__BlitzIndexPartition` | Partitions the `dbo.blitz_index*` tables. |
| 54 | `54__BlitzPartition` | Partitions the `dbo.blitz*` tables (non-index variants). |
| 55 | `55__EnablePageCompression` | Runs `dbo.usp_enable_page_compression` to compress eligible tables (skipped if `SkipPageCompression=$true`). |

## Phase 7 &mdash; Cross-instance wiring (steps 56&ndash;59)

| # | Step | What it does |
|---|---|---|
| 56 | `56__GrafanaLogin` | Creates the `grafana` login with a SID that matches across the fleet; grants `db_datareader` on `DBA`. |
| 57 | `57__LinkedServerOnInventory` | Creates the linked server *from* inventory *to* the monitored instance (used by `Get-AllServer*` jobs). |
| 58 | `58__LinkedServerForDataDestinationInstance` | Creates the linked server *from* the monitored instance *to* `SqlInstanceAsDataDestination` (only when they differ). |
| 59 | `59__AlterViewsForDataDestinationInstance` | Re-creates `vw_*` / `all_server_*` views on the monitored instance so they transparently read from the data-destination instance via the linked server. |

## Reading the logs

Each step logs one or more `[Start-Step]` and `[End-Step]` lines plus a duration. Re-runs with `-StartAtStep` skip everything before the named step **but still run pre-flight validations** (credential, PSRemoting, collation, &hellip;) &mdash; this is why resuming at step 40 still takes ~30 seconds to get to actual work.

## Partial re-runs: common recipes

```powershell
# Just refresh the collection procs and jobs
-OnlySteps '2__AllDatabaseObjects', '15__CreateJobCollectWaitStats', '17__CreateJobCollectFileIOStats'

# Add Perfmon after an MI-flavored install
-OnlySteps '10__CopyPerfmonFolder2Host', '11__SetupPerfmonDataCollector', '14__CreateJobCollectPerfmonData'

# Re-sync the grafana login SID only
-OnlySteps '56__GrafanaLogin' -DropCreatedLogin $true
```
