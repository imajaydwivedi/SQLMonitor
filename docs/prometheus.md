# Prometheus / sql_exporter Path

SQLMonitor's classic architecture pulls everything into SQL Server tables. For shops that already run **Prometheus + Grafana** &mdash; or want lower-latency, cardinality-rich metrics &mdash; there is a parallel path that publishes the same signal set as Prometheus metrics via [burningalchemist/sql_exporter](https://github.com/burningalchemist/sql_exporter).

The two paths are **complementary**, not mutually exclusive. Most of the Grafana dashboards can switch between a SQL datasource and a Prometheus datasource using the same panel queries wrapped in `$__interval`.

## What you get

| | |
|---|---|
| **Exporter** | `sql_exporter` (Go binary) running on every monitored instance on TCP **9399**. |
| **Scrape cadence** | 15s default (configurable in `prometheus.yml`). |
| **Collectors** | 7 YAML files under `sql_exporter/`, one per signal family. |
| **Prometheus dashboard** | `SQL-Exporter-Metrics-Dashboard-External.json` &mdash; drop-in replacement for "Monitoring &mdash; Live &mdash; All Servers". |
| **Alerting rules** | `sql_exporter/alert-engine/Alert-Rules-SQLMonitor.yaml` &mdash; Grafana unified alerting format. |

## Files in the repo

| File | Purpose |
|---|---|
| `sql_exporter.yml` | Top-level exporter config &mdash; targets, credentials, job groups. |
| `mssql_dba_cached.collector.yml` | Low-churn metrics cached server-side (disk space, databases, file IO). |
| `mssql_dba_regular.collector.yml` | The bread-and-butter volatile metrics (CPU, memory, active/blocked requests, wait stats). |
| `mssql_dba_stableinfo.collector.yml` | Instance- and host-level stable facts (SQL version, core count, RAM). |
| `mssql_dba_aghealth.collector.yml` | AG primary/secondary state, redo/log-send queue. |
| `mssql_dba_whoisactive.collector.yml` | Top concurrent queries &mdash; higher cardinality. |
| `mssql_sqlagent_jobs.collector.yml` | SQL Agent job status / outcome / duration / next-run / 24h-failure count from `msdb`. |
| `mssql_backup_history.collector.yml` | Per-(database, backup_type) last-time / size / duration / age from `msdb.dbo.backupset`. |
| `mssql_xevent.collector.yml` | 5-minute aggregates from `DBA.dbo.xevent_metrics` (guarded with an existence check; no-op where the XEvent collector proc isn't installed). |
| `mssql_standard.collector.yml` | The upstream [sql_exporter](https://github.com/burningalchemist/sql_exporter/tree/master/examples/mssql_standard) stock collector. |
| `windows_exporter_config.yml` | Matching config for [windows_exporter](https://github.com/prometheus-community/windows_exporter) &mdash; host-level CPU, disk, network. |
| `tessell-metrics.collector.yml` | Managed-instance variant (no `xp_cmdshell`). |

Full metric reference: [`SQL-Exporter-Metrics-Documentation.md`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/sql_exporter/SQL-Exporter-Metrics-Documentation.md) and the [quick-ref](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/sql_exporter/SQL-Exporter-Metrics-QuickRef.md).

## Install &mdash; Windows

```powershell
# 1. Drop the binary + config in place
#    (Download sql_exporter.exe from https://github.com/burningalchemist/sql_exporter/releases)
Copy-Item .\sql_exporter.exe      C:\Program Files\sql_exporter\
Copy-Item .\sql_exporter\*.yml    C:\Program Files\sql_exporter\

# 2. Register as a service
New-Service -Name sql_exporter `
    -BinaryPathName 'C:\Program Files\sql_exporter\sql_exporter.exe --config.file C:\Program Files\sql_exporter\sql_exporter.yml' `
    -StartupType Automatic `
    -DisplayName 'SQL Exporter for Prometheus'

# 3. Set the service logon account to the sqlmonitor proxy user, then start
Start-Service sql_exporter

# 4. Open the scrape port
New-NetFirewallRule -DisplayName 'SQL Exporter (TCP/9399)' `
    -Direction Inbound -Protocol TCP -LocalPort 9399 -Action Allow

# 5. Smoke test
Invoke-WebRequest http://localhost:9399/metrics -UseBasicParsing | Select-Object -ExpandProperty Content | Select-Object -First 20
```

## Install &mdash; macOS (launchd)

Full step-by-step (including plist and log rotation) is in [`README-sql_exporter.md`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/sql_exporter/README-sql_exporter.md). Summary:

```bash
brew install prometheus grafana
sudo cp com.sql_exporter.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.sql_exporter.plist
curl http://localhost:9399/metrics | head
```

## Wire into Prometheus

Add a job to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: sqlmonitor_mssql
    scrape_interval: 15s
    static_configs:
      - targets:
          - sqlnode-01.corp:9399
          - sqlnode-02.corp:9399
          - aghost-1a.corp:9399
          - aghost-1b.corp:9399
    relabel_configs:
      - source_labels: [__address__]
        regex: '([^:]+):.*'
        target_label: sql_instance
        replacement: '$1'
```

For AGs add `sqlmonitor_ag` with `scrape_interval: 30s` pointing at the same targets &mdash; the `mssql_dba_aghealth` collector is slightly heavier.

## Wire into Grafana

1. Add a Prometheus datasource named **`Prometheus`** (the dashboards query it by that exact name).
2. Import `sql_exporter/SQL-Exporter-Metrics-Dashboard-External.json` &mdash; this is the Prometheus counterpart of the SQL-backed distributed dashboard.
3. Optionally import the unified-alerting YAMLs from `sql_exporter/alert-engine/` &mdash; they define the same CPU / memory / wait / blocking alerts the Python engine provides, but run inside Grafana Alerting instead.

## Prometheus-backed dashboard pack

The repo ships a parallel set of Grafana dashboards under [`sql_exporter/Prometheus-Dashboards/`](https://github.com/imajaydwivedi/SQLMonitor/tree/dev/sql_exporter/Prometheus-Dashboards) that mirror the SQL-backed dashboards in [`Grafana-Dashboards/`](https://github.com/imajaydwivedi/SQLMonitor/tree/dev/Grafana-Dashboards) but source every panel from Prometheus metrics.

Phase 1 ships 12 dashboards covering the fleet's core signal set:

| UID | Title | Data panels |
|---|---|---:|
| `prom_core_metrics_trend` | Core Metrics - Trend | 9 |
| `prom_wait_stats` | Wait Stats | 4 |
| `prom_disk_space` | Disk Space | 5 |
| `prom_ag_health_state` | Ag Health State | 3 |
| `prom_sql_agent_jobs` | SQL Agent Jobs | 6 |
| `prom_backup_history` | Backup History | 6 |
| `prom_xevent_trend` | XEvent - Trend | 4 |
| `prom_database_file_io_stats` | Database File IO Stats | 12 |
| `prom_dba_inventory` | DBA Inventory | 6 (+8 deep-links) |
| `prom_monitoring_live_all_servers` | Monitoring - Live - All Servers | 15 (+6 deep-links) |
| `prom_monitoring_live_distributed` | Monitoring - Live - Distributed | 52 (+6 deep-links) |
| `prom_monitoring_perfmon_quest` | Monitoring - Perfmon Counters - Quest Softwares - Distributed | 51 (+4 deep-links) |

Panels that depend on the SQLMonitor central inventory database (alert history, AG-vs-nonAG backup split, LAMA config-change deltas, `dm_os_memory_clerks` snapshot, tempdb/log_space cache tables, `sql_server_patching`) render as markdown **deep-link tiles** that jump back to the SQL-backed dashboard so every source section remains visible.

### Regenerating the dashboards

Each dashboard is built from a small Python spec:

```bash
cd sql_exporter/Prometheus-Dashboards
python3 generate.py                  # rebuild every *.json
python3 generate.py backup           # filter: rebuild only backup_history
python3 _tools/validate.py           # structural + expr sanity check
```

High-fidelity PromQL patterns used across the specs:

- `increase(metric[$__range])` &mdash; selective-duration deltas (File IO, Wait Stats).
- `@ end() offset $__range` &mdash; prior-window comparison tables (day-over-day).
- `quantile_over_time($percentile_q, (expr)[$trend_window:])` &mdash; percentile trends.
- `topk($top_n, sum by (...) (...))` &mdash; XEvent / wait-type / memory-consumer trends.
- `time() - timestamp(up == 1)` &mdash; data-collection-issue detection.

See the folder's [`README.md`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/sql_exporter/Prometheus-Dashboards/README.md) for the full spec-driven workflow and Grafana API bulk-import snippet.

## Choosing between the two paths

| Consideration | SQL table path (classic) | Prometheus path |
|---|---|---|
| Installation on monitored hosts | SQL Agent jobs only | Requires `sql_exporter` + `windows_exporter` service |
| Retention | You decide (SQL partitioned tables, months-to-years) | Prometheus TSDB (weeks) or Mimir/Thanos for long-term |
| Query shape | Ad-hoc T-SQL, great for forensic deep dives | PromQL, great for fleet aggregates and alerting |
| Historical dashboards | Fast (pre-aggregated tables) | Fast (per-scrape time series) |
| WhoIsActive / Blitz | Native | Cardinality spike &mdash; run on a separate scrape job |
| Alerting | `Alerting/` Python engine | Grafana Alerting / Alertmanager |

A common production topology uses **both**: the SQL path for long retention + forensic tooling, and Prometheus for low-latency fleet dashboards and PagerDuty-grade alert routing.

## Migrating from Perfmon file-collection to sql_exporter

Historically SQLMonitor captured host Perfmon counters into BLG files and parsed them server-side. That path is still available, but shops that already run Prometheus usually switch to `windows_exporter` + `sql_exporter` instead. The migration story (mapping old counters to Prometheus metric names) is tracked in [`Perfmon-SQL-Exporter-Migration-Progress.md`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/sql_exporter/Perfmon-SQL-Exporter-Migration-Progress.md).

## PromQL quick-start

A tutorial tailored to the SQLMonitor metric set lives at [`_README-PromQL-Querying.md`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/sql_exporter/_README-PromQL-Querying.md) &mdash; covers the common `rate()`, `increase()`, `topk()` patterns for wait stats, CPU, IOPS and AG health.
