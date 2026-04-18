# Data Model

SQLMonitor stores everything in two databases:

- **`DBA` on each monitored instance** &mdash; the "collection" tables populated by local SQL Agent jobs.
- **`DBA` on the inventory / observability server** &mdash; the `all_server_*` aggregate tables populated by `(dba) Get-AllServer*` jobs.

## Collection tables (per monitored instance)

Created by `DDLs/SCH-Create-All-Objects.sql`. Hourly-partitioned where the edition supports it, otherwise heap or clustered index.

| Table | Populated by | Key columns | Retention default |
|---|---|---|---|
| `dbo.performance_counters` | `(dba) Collect-PerfmonData` | `collection_time`, `object_name`, `counter_name`, `instance_name`, `cntr_value` | Driven by `dbo.purge_table` |
| `dbo.wait_stats` | `(dba) Collect-WaitStats` | `collection_time`, `wait_type`, `wait_time_ms`, `signal_wait_time_ms`, `waiting_tasks_count` | &hellip; |
| `dbo.file_io_stats` | `(dba) Collect-FileIOStats` | `collection_time`, `database_id`, `file_id`, `num_of_reads`, `io_stall_read_ms`, `num_of_writes`, `io_stall_write_ms` | &hellip; |
| `dbo.memory_clerks` | `(dba) Collect-MemoryClerks` | `collection_time`, `type`, `pages_kb`, `virtual_memory_reserved_kb` | &hellip; |
| `dbo.ag_health_state` | `(dba) Collect-AgHealthState` | `collection_time`, `ag_name`, `replica_server_name`, `role`, `synchronization_state`, `is_local` | &hellip; |
| `dbo.disk_space` | `(dba) Collect-DiskSpace` | `collection_time`, `drive_letter`, `total_size_mb`, `free_space_mb` | &hellip; |
| `dbo.os_task_list` | `(dba) Collect-OSProcesses` | `collection_time`, `image_name`, `pid`, `cpu_percent`, `memory_mb` | &hellip; |
| `dbo.xevent_metrics` | `(dba) Collect-XEvents` | `event_time`, `event_name`, `session_id`, `database_id`, `cpu_time`, `logical_reads`, `duration`, `query_hash`, `sql_text_normalized` | **Heavy**; tight retention |
| `dbo.xevent_metrics_hashed` | `dbo.usp_collect_xevent_metrics_hashed` | `event_time_start`, `query_hash`, `execution_count`, aggregated times/reads/writes | Longer retention than raw |
| `dbo.WhoIsActive` | `(dba) Run-WhoIsActive` | `collection_time`, `session_id`, `login_name`, `wait_info`, `sql_text`, `blocking_session_id`, `reads`, `writes` | 7-14 days typical |
| `dbo.WhoIsActive_Staging` | `sp_WhoIsActive` into &rarr; merged into `WhoIsActive` | transient |
| `dbo.blitz` / `dbo.blitz_index` / `dbo.blitz_index_mode*` | `(dba) Run-Blitz*` | `CheckDate`, `CheckID`, `DatabaseName`, `Details` | Long retention (weekly run) |
| `dbo.log_space_consumers` | `(dba) Run-LogSaver` | `collection_time`, `session_id`, `log_reuse_wait_desc`, `log_used_gb` | Short |
| `dbo.tempdb_space_usage` | `(dba) Run-TempDbSaver` | `collection_time`, `session_id`, `space_used_mb` | Short |
| `dbo.alert_history` | `(dba) Capture-AlertMessages` (triggered by SQL Agent alerts) | `collection_time`, `error_num`, `error_severity`, `error_message` | Long |

## Inventory tables (on the inventory server only)

Created by `DDLs/SCH-Create-Inventory-Specific-Objects.sql`. Core stability metrics use **Memory-Optimized** tables for write throughput.

| Table | Populated by | Shape |
|---|---|---|
| `dbo.sma_sql_instance` | `(dba) Populate Inventory Tables` + `dbo.usp_populate_sma_sql_instance` | Master list of instances in scope |
| `dbo.all_server_volatile_info` | `(dba) Get-AllServerVolatileInfo` | Current snapshot per server (CPU %, memory %, active requests, blocking, &hellip;) |
| `dbo.all_server_volatile_info_history` | same | Memory-Optimized; short history |
| `dbo.all_server_volatile_info_history_hourly` | `(dba) Compute-AllServerVolatileInfoHistoryHourly` | Hourly roll-up, long retention |
| `dbo.all_server_stable_info` | `(dba) Get-AllServerStableInfo` | Config-ish facts (edition, CU, cores, max-memory, &hellip;) |
| `dbo.all_server_stable_info_history` | same | Change history |
| `dbo.all_server_collection_latency_info` | `(dba) Get-AllServerCollectionLatencyInfo` | Per-collector freshness (is collection actually happening?) |
| `dbo.backups_all_servers` | `(dba) Get-AllServerBackups` | DB backup history normalized across fleet |
| `dbo.sql_agent_jobs_all_servers` | `(dba) Get-AllServerSqlAgentJobs` | Job inventory + last outcomes |
| `dbo.ag_health_state_all_servers` | `(dba) Get-AllServerAgHealthState` | Availability group state across fleet |
| `dbo.disk_space_all_servers` | `(dba) Get-AllServerDiskSpace` | Free/used per drive per server |
| `dbo.services_all_servers` | `(dba) Get-AllServerServices` | SQL services running/stopped per host |
| `dbo.tempdb_space_usage_all_servers` | `(dba) Get-AllServerTempdbSpaceUsage` | &hellip; |
| `dbo.log_space_consumers_all_servers` | `(dba) Get-AllServerLogSpaceConsumers` | &hellip; |
| `dbo.alert_history_all_servers` | `(dba) Get-AllServerAlertHistory` | Fleet-wide alert messages |

## Partition scheme

Large collection tables use hourly partitioning via `DDLs/SCH-*-Partitioning.sql` and the daily `(dba) Partitions-Maintenance` job (`dbo.usp_partition_maintenance`).

```text
PARTITION FUNCTION pf_hourly (datetime2)
AS RANGE RIGHT FOR VALUES (
    '2024-12-01 00:00',
    '2024-12-01 01:00',
    '2024-12-01 02:00',
    ...
);
PARTITION SCHEME ps_hourly AS PARTITION pf_hourly ALL TO ([PRIMARY]);
```

The maintenance proc:

1. Adds forward partitions so inserts never hit the unbounded tail.
2. Merges / truncates old partitions per `dbo.purge_table.retention_days`.
3. Rebuilds page compression on recently-sealed partitions via `dbo.usp_enable_page_compression`.

## Purge control

Every purgeable table has a row in `dbo.purge_table`:

| Column | Meaning |
|---|---|
| `schema_name`, `table_name` | target |
| `retention_days` | how long to keep |
| `date_key_column` | column used for purging |
| `is_partitioned` | use SWITCH/TRUNCATE PARTITION vs. DELETE |
| `active` | toggle purging on/off without a code change |

`(dba) Purge-Tables` (daily) &mdash; runs `dbo.usp_purge_tables`, which iterates this table.

## Views (for Grafana consumption)

The installer creates `all_server_*` **views** in the local `DBA` database of every monitored instance *when* `SqlInstanceAsDataDestination` points at a different SQL instance &mdash; these views transparently union-from-linked-server, letting dashboards query "locally" regardless of physical location. See install step `43__AlterViewsForDataDestinationInstance`.

## Further reading

- [Jobs & Collectors catalog](../jobs.md) &mdash; every job, its schedule, and which table it writes.
- [Install Steps](../deployment/steps.md) &mdash; the exact order in which objects are created.
- `DDLs/SCH-Create-All-Objects.sql` &mdash; the authoritative schema script.
