# Data Flow

How one metric travels from "event happened on the host" to "you see it in Grafana and get paged".

## The canonical flow (Perfmon CPU example)

``` mermaid
sequenceDiagram
    autonumber
    participant OS as Windows Perfmon (BLG)
    participant HOST as Monitored host disk
    participant JOB as (dba) Collect-PerfmonData
    participant T as dbo.performance_counters
    participant INVJ as (dba) Get-AllServerVolatileInfo
    participant INV as Inventory.DBA.dbo.all_server_volatile_info
    participant G as Grafana
    participant A as Alert Engine

    OS->>HOST: Writes BLG every 10s via logman
    JOB->>HOST: Every 2 min: consume BLG &rarr; XML &rarr; bulk insert
    JOB->>T: INSERT rows (event_time, counter, value)
    INVJ->>T: SELECT delta over linked server
    INVJ->>INV: UPSERT aggregates (per server)
    G->>INV: Dashboard panel query
    G-->>-G: Render
    A->>INV: usp_get_active_alert_by_* procs
    A-->>A: Threshold check
    A-->>A: Route to PagerDuty / Slack / Email
```

## Pattern: three kinds of collection

SQLMonitor uses three distinct collection patterns depending on what is being measured.

### 1. Host-side file ingest (Perfmon, OS processes, Tasklist)

Files on disk &rarr; PowerShell reader &rarr; bulk insert.

| Job | Script | Destination table | Notes |
|---|---|---|---|
| `(dba) Collect-PerfmonData` | `SQLMonitor/perfmon-collector-push-to-sqlserver.ps1` | `dbo.performance_counters` | Reads `.blg` from `logman` data collector |
| `(dba) Collect-OSProcesses` | `SQLMonitor/perfmon-collector-push-to-sqlserver.ps1` (tasklist branch) | `dbo.os_task_list` | CPU / memory per process |
| `(dba) Collect-DiskSpace` | `SQLMonitor/disk-space-collector.ps1` | `dbo.disk_space` | Uses `Get-Volume` on the host |

### 2. In-engine T-SQL capture (WaitStats, FileIO, MemoryClerks, XEvents, BlitzFirst, &hellip;)

Stored procedure &rarr; table. Delta or snapshot depending on metric.

| Job | Procedure | Destination table | Capture style |
|---|---|---|---|
| `(dba) Collect-WaitStats` | `dbo.usp_collect_wait_stats` | `dbo.wait_stats` | Cumulative snapshot (compute delta at read-time) |
| `(dba) Collect-FileIOStats` | `dbo.usp_collect_file_io_stats` | `dbo.file_io_stats` | Cumulative snapshot |
| `(dba) Collect-MemoryClerks` | `dbo.usp_collect_memory_clerks` | `dbo.memory_clerks` | Point-in-time |
| `(dba) Collect-XEvents` | `dbo.usp_collect_xevent_metrics` | `dbo.xevent_metrics` | Consumes XE files, inserts normalized+hashed rows |
| `(dba) Collect-AgHealthState` | `dbo.usp_collect_ag_health_state` | `dbo.ag_health_state` | Point-in-time |
| `(dba) Run-WhoIsActive` | `dbo.usp_run_WhoIsActive` | `dbo.WhoIsActive` | Append per invocation |
| `(dba) Run-Blitz` / `Run-BlitzIndex` | `dbo.sp_Blitz` / `dbo.sp_BlitzIndex` | `dbo.blitz*` tables | Append weekly/daily |
| `(dba) Run-LogSaver` | `dbo.usp_LogSaver` | `dbo.log_space_consumers` | Finds txn-log fillers; can kill |
| `(dba) Run-TempDbSaver` | `dbo.usp_TempDbSaver` | `dbo.tempdb_space_usage` | Finds tempdb consumers; can kill |

### 3. Inventory aggregation (Get-AllServer*)

Per-instance tables &rarr; linked-server pull &rarr; `all_server_*` table on inventory.

| Job | Reads | Writes |
|---|---|---|
| `(dba) Get-AllServerVolatileInfo` | Remote `DBA` DB on each server via linked server | `dbo.all_server_volatile_info`, `dbo.all_server_volatile_info_history` (Memory-Optimized) |
| `(dba) Get-AllServerStableInfo` | Remote `DBA` DB | `dbo.all_server_stable_info`, `dbo.all_server_stable_info_history` |
| `(dba) Get-AllServerBackups` | `msdb.dbo.backupset` on each server | `dbo.backups_all_servers` |
| `(dba) Get-AllServerSqlAgentJobs` | `msdb` on each server | `dbo.sql_agent_jobs_all_servers` |
| `(dba) Get-AllServerAgHealthState` | `dbo.ag_health_state` on each server | `dbo.ag_health_state_all_servers` |
| `(dba) Get-AllServerDiskSpace` | `dbo.disk_space` on each server | `dbo.disk_space_all_servers` |
| `(dba) Get-AllServerLogSpaceConsumers` | `dbo.log_space_consumers` on each server | `dbo.log_space_consumers_all_servers` |
| `(dba) Get-AllServerTempdbSpaceUsage` | `dbo.tempdb_space_usage` on each server | `dbo.tempdb_space_usage_all_servers` |
| `(dba) Get-AllServerServices` | `sys.dm_server_services` on each server | `dbo.services_all_servers` |
| `(dba) Get-AllServerCollectionLatencyInfo` | Metadata on each server | `dbo.all_server_collection_latency_info` |

Aggregation is orchestrated by `dbo.usp_GetAllServerInfo` and its variants.

## Lifecycle: partition &rarr; compress &rarr; purge

``` mermaid
flowchart LR
    INS[Collector INSERT] --> P1[Hourly partition<br/>created by usp_partition_maintenance]
    P1 --> CMP[Page compression<br/>via usp_enable_page_compression]
    CMP --> OLD[Old partition<br/>exceeds retention]
    OLD --> PURGE[usp_purge_tables<br/>truncates partition]
```

Retention is declarative: `dbo.purge_table` holds one row per table with its retention days. The `(dba) Partitions-Maintenance` and `(dba) Purge-Tables` jobs do the rest.

## Alert path

``` mermaid
flowchart LR
    T[(Collection tables)] --> USP[usp_get_active_alert_by_key<br/>usp_get_active_alert_by_state]
    USP --> ENG[Alert Engine - Python Flask]
    ENG -->|new| SLACK[Slack]
    ENG -->|new| PD[PagerDuty]
    ENG -->|new| MAIL[DatabaseMail]
    ENG -->|update| SLACK
    ENG -->|ack/resolve| PD
```

Alert state is persisted in `dbo.sma_alerts` so re-raises, updates and resolutions are idempotent across restarts. See **[Alerting](../alerting.md)** for the full engine description.
