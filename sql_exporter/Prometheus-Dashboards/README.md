# Prometheus-backed Grafana Dashboards

This folder contains Grafana dashboard JSON files that port the SQL-backed
dashboards in `../../Grafana-Dashboards/` to use the Prometheus data source
populated by `sql_exporter` and `windows_exporter`.

## Why two copies?

SQLMonitor's original dashboards query SQL Server directly. These Prometheus
ports consume the same data via scraped metrics instead, which means:

- no direct 1433 reachability is required from Grafana to each SQL instance,
- dashboards keep working when an instance is temporarily down (last-known
  values remain visible),
- Grafana Alerting can run off the same TSDB without a second datasource,
- metric history is retained on the Prometheus side per its configured
  retention, independent of the `DBA` database.

## Dashboards in this folder — Phase 1 (12 dashboards)

| UID | Title | Source SQL dashboard | Data panels |
|---|---|---|---:|
| `prom_core_metrics_trend` | Core Metrics - Trend | `Core Metrics - Trend.json` | 9 |
| `prom_wait_stats` | Wait Stats | `Wait Stats.json` | 4 |
| `prom_disk_space` | Disk Space | `t___Disk Space.json` | 5 |
| `prom_ag_health_state` | Ag Health State | `t___Ag Health State.json` | 3 |
| `prom_sql_agent_jobs` | SQL Agent Jobs | `Monitoring - Live - All Servers - Job Activity Monitor.json` | 6 |
| `prom_backup_history` | Backup History | `t___Backup_History.json` | 6 |
| `prom_xevent_trend` | XEvent - Trend | `XEvent - Trend.json` | 4 |
| `prom_database_file_io_stats` | Database File IO Stats | `t___Database File IO Stats.json` | 12 |
| `prom_dba_inventory` | DBA Inventory | `DBA Inventory.json` | 6 (+8 deep-links) |
| `prom_monitoring_live_all_servers` | Monitoring - Live - All Servers | `Monitoring - Live - All Servers.json` | 15 (+6 deep-links) |
| `prom_monitoring_live_distributed` | Monitoring - Live - Distributed | `Monitoring - Live - Distributed.json` | 52 (+6 deep-links) |
| `prom_monitoring_perfmon_quest` | Monitoring - Perfmon Counters - Quest Softwares - Distributed | `Monitoring - Perfmon Counters - Quest Softwares - Distributed.json` | 51 (+4 deep-links) |

Source panels that depend on the SQLMonitor central inventory database
(alert history, AG-vs-nonAG backup split, LAMA config-change deltas,
`dm_os_memory_clerks` snapshot, tempdb/log_space cache tables,
sql_server_patching …) are rendered as `legacy_link_panel(...)` markdown
tiles that deep-link back to the SQL-backed dashboard so every source
section remains visible.

## Required `sql_exporter` collectors

All files live in `../`:

- `mssql_standard.collector.yml`  *(upstream, required)*
- `mssql_dba_cached.collector.yml`
- `mssql_dba_regular.collector.yml`
- `mssql_dba_stableinfo.collector.yml`
- `mssql_dba_aghealth.collector.yml`
- `mssql_dba_whoisactive.collector.yml`
- `mssql_sqlagent_jobs.collector.yml`    *(new in Phase 1)*
- `mssql_backup_history.collector.yml`   *(new in Phase 1)*
- `mssql_xevent.collector.yml`           *(new in Phase 1 — reads `DBA.dbo.xevent_metrics` populated by the ring-buffer or file-target XEvent collector proc)*

Plus `windows_exporter` with the `cpu`, `memory`, `logical_disk`,
`physical_disk`, `net`, `os`, `paging_file`, `process`, `service`,
`system` collectors enabled for OS-level panels.

## Regeneration workflow

Every dashboard is generated from a small Python spec in `_specs/`:

```text
_specs/<name>.py   →   generate.py   →   ./<Title>.json
```

- `_lib/prom_dashboard.py` — `Panel`, `Target`, `query_var`, `custom_var`,
  `constant_var`, `row`, `legacy_link_panel`.
- `_lib/build.py` — JSON serialization (`schemaVersion: 42`, `__inputs`,
  per-panel-type option defaults).
- `_tools/validate.py` — structural JSON + target/expr sanity check.
- `_tools/inspect_panels.py` — source-dashboard panel inventory.

```bash
cd sql_exporter/Prometheus-Dashboards
python3 generate.py                    # rebuild every dashboard
python3 generate.py backup             # filter: rebuild only backup_history
python3 _tools/validate.py             # structural validation
```

## Variable conventions

All ports use a `DS_PROMETHEUS` datasource variable so the JSON is
portable between Grafana instances, plus a `Server` query variable built
from `label_values(mssql_up, instance)`. Per-dashboard variables
(`database`, `disk_drive`, `backup_type`, `grouping_key`, `percentile`,
`trend_window` …) are documented in the source spec file.

## Importing into Grafana

### Interactive

1. Grafana &rarr; Dashboards &rarr; **New &rarr; Import**.
2. Upload any `*.json` file from this folder.
3. Select your Prometheus datasource for the `DS_PROMETHEUS` placeholder.

### Bulk (Grafana API)

```bash
TOKEN="<grafana api token>"
FOLDER_UID="prometheus"
for f in *.json; do
  body=$(jq --slurpfile d "$f" -n '{dashboard: $d[0], folderUid: "'$FOLDER_UID'", overwrite: true, inputs: [{name: "DS_PROMETHEUS", type: "datasource", pluginId: "prometheus", value: "Prometheus"}]}')
  curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       -XPOST -d "$body" https://grafana.example.com/api/dashboards/import
done
```

## Deep links to SQL dashboards

The `legacy_link_panel(...)` tiles render a markdown link of the form:

```
/d/<sql-dashboard-uid>
```

Grafana resolves the UID regardless of which folder the SQL dashboard
lives in, so the deep-link keeps working after folder reorganizations as
long as the UID is preserved.

## Future phases

- **Phase 2** — 5 text-bound dashboards (WhoIsActive Workload, XEvent
  Workload, SQLMonitor-Alerts, Blitz Server Health, BlitzIndex Analysis)
  as numeric-summary + deep-link dashboards.
- **Phase 3** — `sql_exporter/README-sql_exporter.md` refresh with
  collector map + Mermaid flow diagrams; cross-links from
  `docs/deployment/prometheus.md` to each generated dashboard.
- **Phase 4** — deploy collectors to live VMs (`sqlmonitor`,
  `AgHost-1A`, `AgHost-1B`) and validate series on
  `https://prometheus.ajaydwivedi.com`.
