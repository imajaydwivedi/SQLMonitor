# Dashboards

SQLMonitor ships **17 production-ready Grafana dashboards** (plus a handful of community add-ons). Every JSON under [`Grafana-Dashboards/`](https://github.com/imajaydwivedi/SQLMonitor/tree/dev/Grafana-Dashboards) is ready to import.

All dashboards use a single data source named exactly **`SQLMonitor`** of type **Microsoft SQL Server**, pointing at the inventory server's `DBA` database. Create that data source once, then import the JSONs.

[:material-rocket-launch: Try the live demo](live-demo.md){ .md-button .md-button--primary }
[:material-book-cog-outline: Variables & conventions](variables.md){ .md-button }

## At a glance

### Live / operations

| Dashboard | File | Live URL | What it shows |
|---|---|---|---|
| **Monitoring &mdash; Live &mdash; Distributed** | [`Monitoring - Live - Distributed.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/Monitoring%20-%20Live%20-%20Distributed.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/distributed_live_dashboard/monitoring-live-distributed) | Core live metrics for one instance: CPU%, memory %, waits per core / minute, active requests, blocking, transactions/sec, IO latency, disk space. |
| **Monitoring &mdash; Live &mdash; All Servers** | [`Monitoring - Live - All Servers.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/Monitoring%20-%20Live%20-%20All%20Servers.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/distributed_live_dashboard_all_servers/monitoring-live-all-servers) | Fleet-wide heatmap of core health metrics &mdash; single pane for an entire environment. |
| **Monitoring &mdash; Live &mdash; Job Activity Monitor** | [`Monitoring - Live - All Servers - Job Activity Monitor.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/Monitoring%20-%20Live%20-%20All%20Servers%20-%20Job%20Activity%20Monitor.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/job_activity_monitor/monitoring-live-all-servers-job-activity-monitor) | Currently-running & recently-failed SQL Agent jobs across the fleet. |
| **Monitoring &mdash; Perfmon Counters &mdash; Quest Softwares &mdash; Distributed** | [`Monitoring - Perfmon Counters - Quest Softwares - Distributed.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/Monitoring%20-%20Perfmon%20Counters%20-%20Quest%20Softwares%20-%20Distributed.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/distributed_perfmon/monitoring-perfmon-counters-quest-softwares-distributed) | Every Windows Perfmon counter Quest Software recommends for SQL baselining. |
| **Core Metrics &mdash; Trend** | [`Core Metrics - Trend.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/Core%20Metrics%20-%20Trend.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/core_metrics_trend/core-metrics-trend) | Long-range trends for CPU, memory, waits, IO. Same metric set as Live-Distributed but over days/weeks. |

### Workload

| Dashboard | File | Live URL | What it shows |
|---|---|---|---|
| **WhoIsActive &mdash; SQL Server Queries &mdash; Workload** | [`WhoIsActive - SQL Server Queries - Workload.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/WhoIsActive%20-%20SQL%20Server%20Queries%20-%20Workload.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/WhoIsActive/whoisactive-sql-server-queries-workload) | Persisted `sp_WhoIsActive` output: live + historical. Top blockers, long-runners, top CPU / reads / writes. |
| **XEvent &mdash; Workload** | [`XEvent - Workload.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/XEvent%20-%20Workload.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/XEvents/xevent-workload) | Normalized / hashed query workload captured by the `XEventMetrics` session &mdash; per-query CPU, reads, duration, exec count. |
| **XEvent &mdash; Trend** | [`XEvent - Trend.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/XEvent%20-%20Trend.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/XEvents-Trends/xevent-trend) | Trend of total CPU / reads / duration across the workload; click-through to per-query. |
| **Wait Stats** | [`Wait Stats.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/Wait%20Stats.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/wait_stats/wait-stats) | Delta-computed wait statistics over time, grouped by category. |

### Diagnostics

| Dashboard | File | Live URL | What it shows |
|---|---|---|---|
| **t___Blitz_Server_Health_Analysis** | [`t___Blitz_Server_Health_Analysis.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/t___Blitz_Server_Health_Analysis.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/t___Blitz_Server_Health_Analysis/t-blitz-server-health-analysis) | `sp_Blitz` findings browsable by priority, category, database. |
| **t___BlitzIndex_Analysis** | [`t___BlitzIndex_Analysis.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/t___BlitzIndex_Analysis.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/t___BlitzIndex_Analysis/t-blitzindex-analysis) | Duplicate indexes, unused indexes, heaps, missing-index recommendations. |

### Infrastructure

| Dashboard | File | Live URL | What it shows |
|---|---|---|---|
| **t___Ag Health State** | [`t___Ag Health State.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/t___Ag%20Health%20State.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/ag_health_state/t-ag-health-state) | Availability Group replica sync state, failover history, send/redo queue sizes. |
| **t___Backup_History** | [`t___Backup_History.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/t___Backup_History.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/backup_history/t-backup-history) | Fleet-wide backup calendar &mdash; FULL/DIFF/LOG freshness, size, duration. |
| **t___Disk Space** | [`t___Disk Space.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/t___Disk%20Space.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/disk_space/t-disk-space) | Per-host, per-drive free-space trend with forecasting. |
| **t___Database File IO Stats** | [`t___Database File IO Stats.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/t___Database%20File%20IO%20Stats.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/database_file_io_stats/t-database-file-io-stats) | Per-database-file read/write latency, IOPS, MB/s &mdash; delta over `sys.dm_io_virtual_file_stats`. |
| **t__DBA_Inventory (DBA Inventory)** | [`DBA Inventory.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/DBA%20Inventory.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/t__DBA_Inventory/dba-inventory) | One row per monitored instance: edition, CU, cores, max memory, last-seen, owner, login expiry. |

### Alerts

| Dashboard | File | Live URL | What it shows |
|---|---|---|---|
| **SQLMonitor-Alerts** | [`SQLMonitor-Alerts.json`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Grafana-Dashboards/SQLMonitor-Alerts.json) | [:material-link: open](https://sqlmonitor.ajaydwivedi.com/d/alerts/sqlmonitor-alerts) | Live alert stream from the [Alert Engine](../alerting.md) with links to PagerDuty / Slack / Email evidence. |

## Importing

=== "Grafana UI"

    1. Grafana &rarr; Dashboards &rarr; **Import**.
    2. Upload the JSON from `Grafana-Dashboards/`.
    3. At the **SQLMonitor** data source dropdown, select the data source you created.
    4. (Recommended) Set the **Folder** to `SQLMonitor` to keep them grouped.

=== "Grafana API"

    ```bash
    for f in Grafana-Dashboards/*.json; do
        curl -sS -u "$GRAF_USER:$GRAF_PASS" \
            -H "Content-Type: application/json" \
            -X POST "$GRAF_URL/api/dashboards/db" \
            --data @<(jq '{dashboard: ., overwrite: true, folderUid: "SQLMonitor"}' "$f")
    done
    ```

=== "Terraform"

    Use [`grafana_dashboard`](https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/dashboard) with `config_json = file("...")`.

See **[Variables & Conventions](variables.md)** for the dashboard variable contract, and **[Live Demo](live-demo.md)** for how the live instance is kept up to date.
