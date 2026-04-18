# Jobs & Collectors

Every SQL instance under SQLMonitor &mdash; including the inventory server &mdash; runs a set of SQL Agent jobs in the **`(dba) SQLMonitor`** category. They are the entire data-collection plane: they poll the OS, DMVs, WMI, XEvents and Perfmon, and persist everything into the `DBA` database for Grafana and the alert engine to consume.

## What you get out of the box

- **46 named jobs** installed in the `(dba) SQLMonitor` category
- Grouped by purpose below (Collection, Aggregation, Ops/Health, Maintenance, Diagnostics)
- Every job is defined by a single `DDLs/SCH-Job-[*].sql` script &mdash; the installer simply runs them
- Schedules range from **every 10 seconds** (alert polling) to **weekly** (Blitz reports)
- Most jobs run as **CmdExec** under the `sqlmonitor` proxy &mdash; they shell out to `sqlcmd` so long-running T-SQL cannot pin the job worker thread

## The per-instance vs. inventory split

| Where it runs | What it does |
|---|---|
| **Every monitored instance** | The `Collect-*` family &mdash; polls local DMVs/OS into tables on that instance's local `DBA` database (per-instance tables like `dbo.wait_stats`, `dbo.file_io_stats`, `dbo.xevent_metrics`). |
| **Inventory server only** | The `Get-AllServer*` family &mdash; pulls from every linked server into the inventory's `dbo.*_all_servers` tables. This is what the Grafana dashboards read from. |
| **Inventory server only** | The `Run-Blitz*`, `Partitions-Maintenance`, `Purge-Tables`, dashboard-mail &mdash; fleet-wide diagnostics & housekeeping. |

See [Architecture &rarr; Data Flow](architecture/data-flow.md) for the pull path.

## Anatomy of a collector job

Every `(dba) Collect-*` and `(dba) Get-AllServer*` job follows the same shape (by design &mdash; makes `Install-SQLMonitor.ps1` idempotent):

```sql
-- DDLs/SCH-Job-[(dba) Collect-WaitStats].sql (excerpt)
EXEC msdb.dbo.sp_add_job @job_name = N'(dba) Collect-WaitStats',
    @category_name = N'(dba) SQLMonitor',
    @owner_login_name = N'sa',
    @description = N'Collect cumulative wait stats on server into dbo.wait_stats.';

EXEC msdb.dbo.sp_add_jobstep @step_name = N'Collect Data',
    @subsystem = N'CmdExec',
    @proxy_name = N'sqlmonitor',   -- standard SQLMonitor proxy
    @command = N'sqlcmd -S $(ESCAPE_SQUOTE(SRVR)) -d DBA -E -Q "EXEC dbo.usp_collect_wait_stats"';

EXEC msdb.dbo.sp_add_jobschedule @freq_type = 4,      -- daily
    @freq_subday_type = 4, @freq_subday_interval = 10;  -- every 10 minutes
```

That means:

1. The **business logic lives in the stored procedure** (`dbo.usp_collect_wait_stats`), not in the job. Jobs are deliberately thin wrappers &mdash; you can re-run the underlying proc from SSMS whenever you like.
2. The **SQL Agent proxy `sqlmonitor`** is used instead of the SQL Agent service account. The proxy maps to a Windows credential with just enough rights to read Perfmon/Registry/Services. See [Deployment &rarr; Prerequisites](deployment/prerequisites.md).
3. The **schedule** is encoded in `freq_type`/`freq_subday_type`/`freq_subday_interval`. The tables below decode those into human form.

## Monitoring the collectors themselves

Jobs that are themselves not collecting on time will cause dashboards to go stale. SQLMonitor ships three self-monitors for that:

| Self-monitor | What it does |
|---|---|
| `(dba) Check-SQLAgentJobs` | Writes every job's status into `dbo.sql_agent_jobs`. Feeds the **Job Activity Monitor** dashboard. |
| `(dba) Stop-StuckSQLMonitorJobs` | Kills & restarts any `(dba) *` job that has been running longer than its configured ceiling &mdash; usually because `sqlcmd` got stuck on a network hiccup. |
| `(dba) Get-AllServerCollectionLatencyInfo` | Populates `dbo.all_server_collection_latency_info` with per-table staleness, which drives the red "stale" indicators in the Distributed dashboard. |

## Scheduling conventions

The `Install-SQLMonitor.ps1` `-JobCollectionFrequency` parameter (see [Parameters](deployment/parameters.md)) can **uniformly increase** every 1-minute job to 2, 5, 10 or 30 minutes. Use this on larger fleets where the inventory server can't keep up with 1-minute pulls. Set it in your `Wrapper-Install-SQLMonitor.ps1` &mdash; not by editing individual `SCH-Job-*.sql` files.

---

## Full job catalog

Below is the authoritative list of all 46 jobs that `Install-SQLMonitor.ps1` creates, grouped by purpose. Links point at the exact `SCH-Job-*.sql` script the installer uses.

### Collection

| Job | Schedule | Subsystem | Script | Description |
|---|---|---|---|---|
| `(dba) Collect Login Expiration Info` | Once daily | CmdExec | [`SCH-Job-[(dba) Collect Login Expiration Info].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect%20Login%20Expiration%20Info].sql) | This job collects all info about SQL Server logins that are active on all servers, and populates them on dbo.all_server_ |
| `(dba) Collect-AgHealthState` | Every 2 minutes | CmdExec | [`SCH-Job-[(dba) Collect-AgHealthState].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-AgHealthState].sql) | Collect availability group health state. |
| `(dba) Collect-AllServerAlertMessages` | Every 10 seconds | CmdExec | [`SCH-Job-[(dba) Collect-AllServerAlertMessages].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-AllServerAlertMessages].sql) | Get Alert Messages from All Servers |
| `(dba) Collect-DiskSpace` | Every 30 minutes | CmdExec | [`SCH-Job-[(dba) Collect-DiskSpace-ManagedInstance].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-DiskSpace-ManagedInstance].sql) | Collect disk space on server into dbo.disk_space. |
| `(dba) Collect-DiskSpace` | Every 10 minutes | CmdExec | [`SCH-Job-[(dba) Collect-DiskSpace].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-DiskSpace].sql) | Get Disk Space info |
| `(dba) Collect-FileIOStats` | Every 10 minutes | CmdExec | [`SCH-Job-[(dba) Collect-FileIOStats].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-FileIOStats].sql) | Collect cumulative file io stats on server into dbo.file_io_stats. |
| `(dba) Collect-MemoryClerks` | Every 2 minutes | CmdExec | [`SCH-Job-[(dba) Collect-MemoryClerks].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-MemoryClerks].sql) | Collect top memory consumers on server into dbo.memory_clerks. |
| `(dba) Collect-OSProcesses` | Every 2 minutes | CmdExec | [`SCH-Job-[(dba) Collect-OSProcesses].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-OSProcesses].sql) | Get OS Processes CPU & Memory |
| `(dba) Collect-PerfmonData` | Every 30 seconds | CmdExec | [`SCH-Job-[(dba) Collect-PerfmonData-ManagedInstance].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-PerfmonData-ManagedInstance].sql) | Collect disk space on server into dbo.disk_space. |
| `(dba) Collect-PerfmonData` | Every 60 seconds | CmdExec | [`SCH-Job-[(dba) Collect-PerfmonData].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-PerfmonData].sql) | This job captures Perfmon data as per template https://github.com/imajaydwivedi/SqlServer-Baselining-Grafana/blob/maste |
| `(dba) Collect-PrivilegedInfo` | Every 10 minutes | CmdExec | [`SCH-Job-[(dba) Collect-PrivilegedInfo].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-PrivilegedInfo].sql) | Collect information that generally need Sysadmin access. |
| `(dba) Collect-WaitStats` | Every 10 minutes | CmdExec | [`SCH-Job-[(dba) Collect-WaitStats].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-WaitStats].sql) | Collect cumulative wait stats on server into dbo.wait_stats. |
| `(dba) Collect-XEvents` | Every 1 minute | CmdExec | [`SCH-Job-[(dba) Collect-XEvents].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Collect-XEvents].sql) | This job consumes data from XEvent [xevent_metrics] into dbo.xevent_metrics. |

### Aggregation

| Job | Schedule | Subsystem | Script | Description |
|---|---|---|---|---|
| `(dba) Get-AllServerAgHealthState` | Every 1 minute | CmdExec | [`SCH-Job-[(dba) Get-AllServerAgHealthState].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerAgHealthState].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.ag_health_state_all_servers https://ajaydwiv |
| `(dba) Get-AllServerAlertHistory` | Every 30 seconds | CmdExec | [`SCH-Job-[(dba) Get-AllServerAlertHistory].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerAlertHistory].sql) | This job execute procedure usp_GetAllServerCollectedData and populates in table dbo.alert_history_all_servers https://a |
| `(dba) Get-AllServerBackups` | Every 15 minutes | CmdExec | [`SCH-Job-[(dba) Get-AllServerBackups].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerBackups].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.backups_all_servers https://ajaydwivedi.com/ |
| `(dba) Get-AllServerCollectionLatencyInfo` | Every 15 minutes | CmdExec | [`SCH-Job-[(dba) Get-AllServerCollectionLatencyInfo].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerCollectionLatencyInfo].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.all_server_collection_latency_info https://a |
| `(dba) Get-AllServerDashboardMail` | Every 8 hours | CmdExec | [`SCH-Job-[(dba) Get-AllServerDashboardMail].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerDashboardMail].sql) | Send Mail for All Critical Metrics Every 8 Hours |
| `(dba) Get-AllServerDiskSpace` | Every 5 minutes | CmdExec | [`SCH-Job-[(dba) Get-AllServerDiskSpace].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerDiskSpace].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.disk_space_all_servers https://ajaydwivedi.c |
| `(dba) Get-AllServerLogSpaceConsumers` | Every 1 minute | CmdExec | [`SCH-Job-[(dba) Get-AllServerLogSpaceConsumers].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerLogSpaceConsumers].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.log_space_consumers_all_servers https://ajay |
| `(dba) Get-AllServerServices` | Every 10 minutes | CmdExec | [`SCH-Job-[(dba) Get-AllServerServices].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerServices].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.services_all_servers https://ajaydwivedi.com |
| `(dba) Get-AllServerSqlAgentJobs` | Every 5 minutes | CmdExec | [`SCH-Job-[(dba) Get-AllServerSqlAgentJobs].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerSqlAgentJobs].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.sql_agent_jobs_all_servers https://ajaydwive |
| `(dba) Get-AllServerStableInfo` | Every 5 minutes | CmdExec | [`SCH-Job-[(dba) Get-AllServerStableInfo].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerStableInfo].sql) | This job execute procedure usp_GetAllServerInfo and populates tables dbo.all_server_stable_info & dbo.all_server_stable_ |
| `(dba) Get-AllServerTempdbSpaceUsage` | Every 1 minute | CmdExec | [`SCH-Job-[(dba) Get-AllServerTempdbSpaceUsage].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerTempdbSpaceUsage].sql) | This job execute procedure usp_GetAllServerInfo and populates in table dbo.tempdb_space_usage_all_servers https://ajayd |
| `(dba) Get-AllServerVolatileInfo` | Every 30 seconds | CmdExec | [`SCH-Job-[(dba) Get-AllServerVolatileInfo].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Get-AllServerVolatileInfo].sql) | This job execute procedure usp_GetAllServerInfo and populates tables dbo.all_server_volatile_info & dbo.all_server_volat |
| `(dba) Populate Inventory Tables` | Once daily | CmdExec | [`SCH-Job-[(dba) Populate Inventory Tables].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Populate%20Inventory%20Tables].sql) | This job populates Inventory tables using SQLMonitor data |

### Ops/Health

| Job | Schedule | Subsystem | Script | Description |
|---|---|---|---|---|
| `(dba) Capture-AlertMessages` | (no schedule) | TSQL | [`SCH-Job-[(dba) Capture-AlertMessages].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Capture-AlertMessages].sql) | Job is trigged through SQL Agent Alerts. Purpose: Collect Alert Messages in table [dbo].[alert_history]. https://ajayd |
| `(dba) Check-InstanceAvailability` | Every 2 minutes | CmdExec | [`SCH-Job-[(dba) Check-InstanceAvailability].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Check-InstanceAvailability].sql) | Check if SQL Instances are online.  For additional validation, [DDLs\SCH-usp_ |
| `(dba) Check-SQLAgentJobs` | Every 5 minutes | CmdExec | [`SCH-Job-[(dba) Check-SQLAgentJobs].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Check-SQLAgentJobs].sql) | Collect SQL Agent Job Stats. |
| `(dba) Send Login Expiry EMails` | Once daily | CmdExec | [`SCH-Job-[(dba) Send Login Expiry EMails].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Send%20Login%20Expiry%20EMails].sql) | This job executes procedure dbo.usp_send_login_expiry_emails, and send login password expiry email notification to owner |
| `(dba) Stop-StuckSQLMonitorJobs` | Every 1 hour | CmdExec | [`SCH-Job-[(dba) Stop-StuckSQLMonitorJobs].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Stop-StuckSQLMonitorJobs].sql) | This job stops/restarts any stuck SQLMonitor job. |
| `(dba) Test-WindowsAdminAccess` | (no schedule) | PowerShell | [`SCH-Job-[(dba) Test-WindowsAdminAccess].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Test-WindowsAdminAccess].sql) | This job is temporary for testing if Proxy is required for calling PowerShell scripts. https://ajaydwivedi.com/github/s |
| `(dba) Update-SQLMonitorIP` | Every 5 minutes | CmdExec | [`SCH-Job-[(dba) Update-SQLMonitorIP].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Update-SQLMonitorIP].sql) | Update ip address of ajaydwivedi.ddns.net |
| `Update-SQLMonitorIPAddress` | Every 5 minutes | CmdExec | [`SCH-Job-[Update-SQLMonitorIPAddress].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[Update-SQLMonitorIPAddress].sql) | This job execute python script that keeps ip address updated for sqlmonitor.ajaydwivedi.com. https://github.com/imajaydw |

### Maintenance

| Job | Schedule | Subsystem | Script | Description |
|---|---|---|---|---|
| `(dba) Compute-AllServerVolatileInfoHistoryHourly` | Once daily | CmdExec | [`SCH-Job-[(dba) Compute-AllServerVolatileInfoHistoryHourly].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Compute-AllServerVolatileInfoHistoryHourly].sql) | Aggregate data from dbo.all_server_volatile_info_history and save it into hourly trend in table dbo.all_server_volatile_ |
| `(dba) Enable-PageCompression` | One-time | TSQL | [`SCH-Job-[(dba) Enable-PageCompression].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Enable-PageCompression].sql) | This job purges data from SQLMonitor tables mentioned in dbo.purge_table. |
| `(dba) Partitions-Maintenance` | Once daily | CmdExec | [`SCH-Job-[(dba) Partitions-Maintenance].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Partitions-Maintenance].sql) | This job takes care of creating new partitions and removing old partitions |
| `(dba) Purge-Tables` | Once daily | CmdExec | [`SCH-Job-[(dba) Purge-Tables].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Purge-Tables].sql) | This job purges data from SQLMonitor tables mentioned in dbo.purge_table. |
| `(dba) Remove-XEventFiles` | Every 30 minutes | CmdExec | [`SCH-Job-[(dba) Remove-XEventFiles].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Remove-XEventFiles].sql) | Remove files generated by XEvent [xevent_metrics] from disk. |
| `(dba) Update-SqlServerVersions` | Weekly (Wed,Fri) | CmdExec | [`SCH-Job-[(dba) Update-SqlServerVersions].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Update-SqlServerVersions].sql) | This job fetches script "https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/SqlServerVer |

### Diagnostics

| Job | Schedule | Subsystem | Script | Description |
|---|---|---|---|---|
| `(dba) Run-Blitz` | Weekly (Sat) | CmdExec | [`SCH-Job-[(dba) Run-Blitz].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Run-Blitz].sql) | Capture Overall Server Health Checks |
| `(dba) Run-BlitzIndex` | Once daily | CmdExec | [`SCH-Job-[(dba) Run-BlitzIndex].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Run-BlitzIndex].sql) | Capture index usage details into SQL Table . |
| `(dba) Run-BlitzIndex - Weekly` | Weekly (Sat) | CmdExec | [`SCH-Job-[(dba) Run-BlitzIndex - Weekly].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Run-BlitzIndex%20-%20Weekly].sql) | Capture index usage details into SQL Table . |
| `(dba) Run-LogSaver` | Every 5 minutes | CmdExec | [`SCH-Job-[(dba) Run-LogSaver].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Run-LogSaver].sql) | Find what transactions are causing database log file to get full, and kill session if required. https://ajaydwivedi.com |
| `(dba) Run-TempDbSaver` | Every 5 minutes | CmdExec | [`SCH-Job-[(dba) Run-TempDbSaver].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Run-TempDbSaver].sql) | Find what is consuming space in tempdb, and kill the session if required. |
| `(dba) Run-WhoIsActive` | Every 2 minutes | CmdExec | [`SCH-Job-[(dba) Run-WhoIsActive].sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/DDLs/SCH-Job-[(dba)%20Run-WhoIsActive].sql) | Capture sp_WhoIsActive result into dbo.WhoIsActive. |

_Total: 46 jobs in the `(dba) SQLMonitor` category._


## Triggering jobs outside their schedule

Every collector can be run manually:

```sql
-- On the target instance
EXEC msdb.dbo.sp_start_job @job_name = N'(dba) Collect-WaitStats';

-- Or run the proc directly (same effect, faster iteration)
EXEC DBA.dbo.usp_collect_wait_stats;
```

For the inventory side, use `@sql_instance` to scope:

```sql
EXEC DBA.dbo.usp_GetAllServerInfo @collection_name = N'volatile_info';
```

## Disabling collectors

If a collector is noisy for your environment, disable it rather than dropping it &mdash; that way `Install-SQLMonitor.ps1` will not recreate it on the next upgrade (the installer respects existing job enabled/disabled state):

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'(dba) Collect-XEvents', @enabled = 0;
```

## Related reading

- [Deployment &rarr; Install Steps](deployment/steps.md) &mdash; maps each job-creation step name to the SQL file.
- [Architecture &rarr; Components](architecture/components.md) &mdash; where these jobs fit in the overall flow.
- [Alerting](alerting.md) &mdash; how `dbo.alert_history` is populated and consumed.
