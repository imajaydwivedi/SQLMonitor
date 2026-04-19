# Variables & Conventions

SQLMonitor's dashboards follow a strict naming and templating contract so that:

- Every panel in every dashboard works for any monitored instance without manual edits.
- Cross-dashboard drill-downs (click WhoIsActive &rarr; open XEvent trend for the same query) work out of the box.
- Queries recycle execution plans across concurrent users.

## The variable contract

Every dashboard declares (at minimum) these template variables:

| Variable | Bound to | Populated from | Used in |
|---|---|---|---|
| `$sqlmonitor_datasource` | The `SQLMonitor` data source UID | Grafana's data-source picker | Every query |
| `$server` | `sql_instance` value | `SELECT sql_instance FROM dbo.sma_sql_instance WHERE is_active = 1 ORDER BY 1` | Instance filter |
| `$inventory_db` | Inventory DB name | Constant, default `DBA` | `FROM $inventory_db.dbo.all_server_*` |
| `$dba_db` | DBA DB name on target | Constant, default `DBA` | `FROM $dba_db.dbo.*` |
| `$host_name` | Windows host of `$server` | `SELECT host_name FROM dbo.sma_sql_instance WHERE sql_instance = '$server'` | Perfmon joins |
| `$perfmon_host_name` | host used by Perfmon tables (may differ from `$host_name` for FCIs) | same | Perfmon queries |
| `$is_local` | `1` when inventory == monitored | SQL expression | Switch between local table and linked-server view |
| `$ip` / `$fqdn` | Network identity for the instance | `dbo.sma_sql_instance` | Info panels |
| `$sql_schedulers` | `CPU count` | `sys.dm_os_schedulers` | Normalization (waits per core, etc.) |
| `$sqlserver_start_time_utc` | Last SQL Server restart | `sys.dm_os_sys_info` | "Since Startup" views |
| `$collection_time_utc` | Latest collection timestamp | Per-table | "As of…" panel titles |

The hidden `*_table_name` variables (`$diskspace_table_name`, `$fileiostats_table_name`, &hellip;) let a dashboard query the **local** collection table when `is_local=1` and a **linked-server view** otherwise &mdash; same query, two destinations.

## The `$server` change bus

Changing `$server` should cascade automatically to `$host_name`, `$sql_schedulers`, `$ip`, etc. This is achieved by declaring the derived variables **after** `$server` with SQL like:

```sql
-- $host_name
SELECT host_name
FROM $inventory_db.dbo.sma_sql_instance
WHERE sql_instance = '$server'
```

…and setting "Refresh: On Dashboard Load" + "On Time Range Change" so the chain re-evaluates.

## Time filtering

Every time-series query uses `$__timeFilter` on a `datetime2` column named `collection_time` or `event_time`:

```sql
SELECT collection_time AS time, wait_type, wait_time_ms
FROM $dba_db.dbo.wait_stats
WHERE $__timeFilter(collection_time)
  AND sql_instance = '$server';
```

## Cross-dashboard drill-down URL conventions

Panels use these patterns for **Data Links** (see `_README-Grafana-Variables.sql`):

| From | To | Link template |
|---|---|---|
| Any fleet grid | Live Distributed for the clicked row | `d/distributed_live_dashboard?var-server=${__data.fields.srv_name}` |
| Live Distributed | WhoIsActive for a session | `d/WhoIsActive?var-server=${server}&var-session_id=${__data.fields.spid}&viewPanel=132` |
| Live Distributed | Perfmon for a tempdb sub-panel | `d/distributed_perfmon?var-server=${__data.fields.sql_instance}&var-database=tempdb&viewPanel=115` |
| Wait Stats | sqlskills wait docs | `https://www.sqlskills.com/help/waits/${__value.raw}` |
| Disk Space | Disk Space (drilled) | `d/disk_space?var-server=${__data.fields.sql_instance}&var-perfmon_host_name=${__data.fields.host_name}&var-disk_drive=${__data.fields.disk_volume}&viewPanel=26` |

## Dynamic SQL pattern (why queries are so readable)

A recurring pattern you'll see inside SQLMonitor panels:

```sql
DECLARE @server sysname = '$server';
DECLARE @is_local bit = $is_local;
DECLARE @sql nvarchar(max) =
N'SELECT collection_time AS time, counter, value
  FROM ' + QUOTENAME('$dba_db') + '.dbo.performance_counters
  WHERE $__timeFilter(collection_time)
    AND sql_instance = @server';
IF @is_local = 0
    SET @sql = REPLACE(@sql, N'.dbo.performance_counters', N'.dbo.vw_performance_counters_remote');
EXEC sys.sp_executesql @sql, N'@server sysname', @server;
```

This yields **one compiled plan** regardless of which instance is selected, because the static plan is `sys.sp_executesql` with a `sysname` parameter.

## Adding a new dashboard

1. Base it on `Monitoring - Live - Distributed.json` so you inherit the variable chain.
2. Tag it `mssql, sqlmonitor, <area>`. The Grafana folder & search filters rely on these.
3. Use `$__timeFilter(<datetime_column>)` on every time series.
4. Never hard-code `DBA` or an instance name &mdash; always use `$dba_db` / `$server`.
5. Export with `Share &rarr; Export &rarr; Export for sharing externally` to strip data-source UIDs.

See [`_README-Grafana-Variables.sql`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/_README-Grafana-Variables.sql) for more URL templates.
