# Live Demo

A fully-provisioned SQLMonitor instance is kept publicly available so you can click around before deploying.

!!! info "Credentials"

    | Portal | URL | Username | Password |
    |---|---|---|---|
    | Grafana | <https://sqlmonitor.ajaydwivedi.com> | `guest` | `ajaydwivedi-guest` |
    | SQL instance | `sqlmonitor.ajaydwivedi.com:1433` | `grafana` | `grafana` |

    The SQL endpoint is read-only (grafana login) and exposes the inventory `DBA` database &mdash; point your SSMS at it if you want to poke at the raw tables.

## Dashboards on the live instance

| Dashboard | Link |
|---|---|
| Monitoring &mdash; Live &mdash; Distributed | <https://sqlmonitor.ajaydwivedi.com/d/distributed_live_dashboard/monitoring-live-distributed?orgId=1&refresh=5s> |
| Monitoring &mdash; Live &mdash; All Servers | <https://sqlmonitor.ajaydwivedi.com/d/distributed_live_dashboard_all_servers/monitoring-live-all-servers> |
| Monitoring &mdash; Live &mdash; Job Activity Monitor | <https://sqlmonitor.ajaydwivedi.com/d/job_activity_monitor/monitoring-live-all-servers-job-activity-monitor> |
| Monitoring &mdash; Perfmon Counters &mdash; Quest Software | <https://sqlmonitor.ajaydwivedi.com/d/distributed_perfmon/monitoring-perfmon-counters-quest-softwares-distributed> |
| Core Metrics &mdash; Trend | <https://sqlmonitor.ajaydwivedi.com/d/core_metrics_trend/core-metrics-trend> |
| WhoIsActive &mdash; Workload | <https://sqlmonitor.ajaydwivedi.com/d/WhoIsActive/whoisactive-sql-server-queries-workload> |
| XEvent &mdash; Workload | <https://sqlmonitor.ajaydwivedi.com/d/XEvents/xevent-workload> |
| XEvent &mdash; Trend | <https://sqlmonitor.ajaydwivedi.com/d/XEvents-Trends/xevent-trend> |
| Wait Stats | <https://sqlmonitor.ajaydwivedi.com/d/wait_stats/wait-stats> |
| Blitz Server Health Analysis | <https://sqlmonitor.ajaydwivedi.com/d/t___Blitz_Server_Health_Analysis/t-blitz-server-health-analysis> |
| BlitzIndex Analysis | <https://sqlmonitor.ajaydwivedi.com/d/t___BlitzIndex_Analysis/t-blitzindex-analysis> |
| AG Health State | <https://sqlmonitor.ajaydwivedi.com/d/ag_health_state/t-ag-health-state> |
| Backup History | <https://sqlmonitor.ajaydwivedi.com/d/backup_history/t-backup-history> |
| Disk Space | <https://sqlmonitor.ajaydwivedi.com/d/disk_space/t-disk-space> |
| Database File IO Stats | <https://sqlmonitor.ajaydwivedi.com/d/database_file_io_stats/t-database-file-io-stats> |
| DBA Inventory | <https://sqlmonitor.ajaydwivedi.com/d/t__DBA_Inventory/dba-inventory> |
| SQLMonitor-Alerts | <https://sqlmonitor.ajaydwivedi.com/d/alerts/sqlmonitor-alerts> |

## What's in the demo environment

The live demo monitors a small lab fleet (inventory server + a couple of Availability-Group hosts). That means you get real data for:

- AG health state and failover (the hosts rotate primary occasionally on purpose).
- A modest but continuous workload from a test harness.
- Real Perfmon data, real WhoIsActive output, real Blitz findings.
- The **Alert Engine** firing real (demo) alerts into a sandboxed Slack & PagerDuty.

## Looking at the tables directly

Point SSMS (or Azure Data Studio, or DBeaver, or `sqlcmd`) at:

```text
Server: sqlmonitor.ajaydwivedi.com,1433
Auth:   SQL Server Authentication
User:   grafana
Pass:   grafana
DB:     DBA
```

Some queries to try:

```sql
-- Fleet snapshot
SELECT sql_instance, cpu_percent, active_requests, blocked_requests, collection_time_utc
FROM dbo.all_server_volatile_info
ORDER BY sql_instance;

-- Top waits in the last hour, fleet-wide
SELECT TOP 20 sql_instance, wait_type, SUM(wait_time_ms_delta)/1000.0 AS wait_sec
FROM DBA.dbo.vw_wait_stats_deltas
WHERE collection_time > DATEADD(HOUR, -1, GETDATE())
GROUP BY sql_instance, wait_type
ORDER BY wait_sec DESC;

-- Newest alert messages
SELECT TOP 20 sql_instance, error_severity, collection_time, error_message
FROM DBA.dbo.alert_history_all_servers
ORDER BY collection_time DESC;
```

## What this demo does **not** demonstrate

- **Multi-hundred-server scale.** The demo fleet is intentionally small. For scale guidance see [Architecture](../architecture/index.md).
- **Production alert routing.** Slack and PagerDuty are sandboxed &mdash; they demonstrate the *flow* but not a real oncall experience.
- **Sensitive data.** The demo strips real query text where possible. Your own deployment will see its own queries in plaintext in `dbo.xevent_metrics`; plan accordingly.
