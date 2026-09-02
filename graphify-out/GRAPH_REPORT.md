# Graph Report - .  (2026-09-02)

## Corpus Check
- Large corpus: 438 files · ~1,301,765 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 672 nodes · 732 edges · 182 communities (149 shown, 33 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 93 edges (avg confidence: 0.77)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Component 0|Component 0]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Component 2|Component 2]]
- [[_COMMUNITY_Component 3|Component 3]]
- [[_COMMUNITY_Component 4|Component 4]]
- [[_COMMUNITY_Component 5|Component 5]]
- [[_COMMUNITY_Component 6|Component 6]]
- [[_COMMUNITY_Component 7|Component 7]]
- [[_COMMUNITY_Component 8|Component 8]]
- [[_COMMUNITY_Component 9|Component 9]]
- [[_COMMUNITY_Component 10|Component 10]]
- [[_COMMUNITY_Component 11|Component 11]]
- [[_COMMUNITY_Component 12|Component 12]]
- [[_COMMUNITY_Component 13|Component 13]]
- [[_COMMUNITY_Component 14|Component 14]]
- [[_COMMUNITY_Component 15|Component 15]]
- [[_COMMUNITY_Component 16|Component 16]]
- [[_COMMUNITY_Component 17|Component 17]]
- [[_COMMUNITY_Component 18|Component 18]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_Component 20|Component 20]]
- [[_COMMUNITY_Component 21|Component 21]]
- [[_COMMUNITY_Component 22|Component 22]]
- [[_COMMUNITY_Alerting System|Alerting System]]
- [[_COMMUNITY_Component 26|Component 26]]
- [[_COMMUNITY_Index & Table Management|Index & Table Management]]
- [[_COMMUNITY_Component 28|Component 28]]
- [[_COMMUNITY_Component 29|Component 29]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Job Scheduling|Job Scheduling]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Alerting System|Alerting System]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_IO & Disk|I/O & Disk]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Replication & Backup|Replication & Backup]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Index & Table Management|Index & Table Management]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_IO & Disk|I/O & Disk]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_Performance Analysis|Performance Analysis]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Design Patterns|Design Patterns]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_Monitoring & Queries|Monitoring & Queries]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Code Module|Code Module]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Alerting System|Alerting System]]

## God Nodes (most connected - your core abstractions)
1. `SmaAlert` - 37 edges
2. `SQLMonitor` - 18 edges
3. `get_pretty_table()` - 17 edges
4. `get_sma_params()` - 16 edges
5. `SmaAgDbBackupIssueAlert` - 15 edges
6. `SmaAgLatencyAlert` - 15 edges
7. `SmaAvailableMemoryAlert` - 15 edges
8. `SmaCpuAlert` - 15 edges
9. `SmaDiskLatencyAlert` - 15 edges
10. `SmaDiskSpaceAlert` - 15 edges

## Surprising Connections (you probably didn't know these)
- `SQLMonitor` --references--> `Collection Tier`  [INFERRED]
  README.md → architecture/index.md
- `SQLMonitor` --references--> `Consumption Tier`  [INFERRED]
  README.md → architecture/index.md
- `SQLMonitor` --references--> `Storage Tier`  [INFERRED]
  README.md → architecture/index.md
- `Consumption Tier` --references--> `Prometheus`  [EXTRACTED]
  architecture/index.md → README.md
- `Alerting Folder` --references--> `Python Alert Engine`  [EXTRACTED]
  architecture/components.md → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Production Dashboards** — dashboards_index_monitoring_live_distributed, dashboards_index_monitoring_live_all_servers, dashboards_index_whoisactive_workload, dashboards_index_xevent_workload, dashboards_index_wait_stats [EXTRACTED 1.00]
- **Collection Patterns** — architecture_data_flow_perfmon_collection, architecture_data_flow_tsql_capture, architecture_data_flow_inventory_aggregation [EXTRACTED 1.00]
- **Repository Folder Structure** — architecture_components_sqlmonitor_folder, architecture_components_ddls_folder, architecture_components_grafana_dashboards_folder, architecture_components_alerting_folder, architecture_components_sql_exporter_folder [EXTRACTED 1.00]
- **SQL Exporter Collectors Ecosystem** — sql_exporter_mssql_dba_cached_collector, sql_exporter_mssql_dba_regular_collector, sql_exporter_mssql_dba_stableinfo_collector, sql_exporter_mssql_dba_aghealth_collector, sql_exporter_mssql_standard_collector, sql_exporter_mssql_dba_whoisactive_collector, sql_exporter_mssql_sqlagent_jobs_collector, sql_exporter_mssql_backup_history_collector, sql_exporter_mssql_xevent_collector [INFERRED 0.85]
- **Alert Delivery Chain** — sql_exporter_alert_rules_sqlmonitor, sql_exporter_contact_points_sqlmonitor, sql_exporter_notification_policies_sqlmonitor [INFERRED 0.85]
- **SQL Exporter Job Configuration** — sql_exporter_job_mssql_common, sql_exporter_job_mssql_ag, sql_exporter_job_mssql_long_running, sql_exporter_job_mssql_msdb, sql_exporter_job_mssql_xevent [EXTRACTED 1.00]

## Communities (182 total, 33 thin omitted)

### Community 0 - "Component 0"
Cohesion: 0.05
Nodes (18): SYNOPSIS: Class to represent dbo.sma_alert table         INPUT:, SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, _summary_          Args:             size (float): _description_             uni, Converts the given time value to a more human-readable format (minutes, hours, d, SmaAlert, alert_action(), auto_resolve_cleared_alerts() (+10 more)

### Community 1 - "Documentation"
Cohesion: 0.06
Nodes (36): Alerting Folder, Grafana-Dashboards Folder, Install-SQLMonitor.ps1, Remove-SQLMonitor.ps1, sql_exporter Folder, Alert Engine Path, Inventory Aggregation Pattern, Perfmon Collection Pattern (+28 more)

### Community 2 - "Component 2"
Cohesion: 0.11
Nodes (8): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent cpu alert, SmaAvailableMemoryAlert, get_oncall_teams(), get_pretty_data_size(), get_pretty_table(), get_sma_params()

### Community 3 - "Component 3"
Cohesion: 0.08
Nodes (26): mssql_ag Job, mssql_long_running Job, mssql_msdb Job, mssql_xevent Job, mssql_aghealth__latency_seconds Metric, mssql_aghealth__synchronization_state Metric, mssql_backup__last_duration_seconds Metric, mssql_backup__last_time_utc Metric (+18 more)

### Community 4 - "Component 4"
Cohesion: 0.10
Nodes (22): mssql_common Job, mssql_buffer_cache_hit_ratio Metric, mssql_database_file_size_bytes Metric, mssql_db__* Configuration Metrics, mssql_db__create_date Metric, mssql_deadlocks Metric, mssql_host_physical_memory_bytes Metric, mssql_io_stall_seconds Metric (+14 more)

### Community 5 - "Component 5"
Cohesion: 0.16
Nodes (5): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent backup issue alert, SmaAgDbBackupIssueAlert, get_pandas_dataframe()

### Community 6 - "Component 6"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent ag latency alert, SmaAgLatencyAlert

### Community 7 - "Component 7"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent cpu alert, SmaCpuAlert

### Community 8 - "Component 8"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent cpu alert, SmaDiskLatencyAlert

### Community 9 - "Component 9"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent disk space alert, SmaDiskSpaceAlert

### Community 10 - "Component 10"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent log space alert, SmaLogSpaceAlert

### Community 11 - "Component 11"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent cpu alert, SmaMemoryGrantsPendingAlert

### Community 12 - "Component 12"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent backup issue alert, SmaNonAgDbBackupIssueAlert

### Community 13 - "Component 13"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent offline server alert, SmaOfflineAgentAlert

### Community 14 - "Component 14"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent offline server alert, SmaOfflineServerAlert

### Community 15 - "Component 15"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent sql blocking alert, SmaSqlBlockingAlert

### Community 16 - "Component 16"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent sqlmonitor jobs alert, SmaSqlMonitorJobsAlert

### Community 17 - "Component 17"
Cohesion: 0.19
Nodes (4): SYNOPSIS: Constructor, SYNOPSIS: Computes derived attributes like State, Severity, header, logger, desc, SYNOPSIS: Class to represent tempdb alert, SmaTempdbAlert

### Community 18 - "Component 18"
Cohesion: 0.28
Nodes (5): Path, build_dashboard(), DashboardBuilder, parse_metric_meta(), q()

### Community 19 - "Monitoring & Queries"
Cohesion: 0.15
Nodes (12): AI-Agent, Alerting, Credential-Manager, DDLs, Grafana-Dashboards, NoteBooks, Private, Sql-Queries (+4 more)

### Community 20 - "Component 20"
Cohesion: 0.17
Nodes (10): BinaryLiteral, InPredicate, IntegerLiteral, MoneyLiteral, NumericLiteral, RealLiteral, StringLiteral, TSqlFragmentVisitor (+2 more)

### Community 21 - "Component 21"
Cohesion: 0.25
Nodes (6): SqlBoolean, SqlFunction, SqlInt32, SqlString, StringOp, TSQLTextNormalizer

### Community 22 - "Component 22"
Cohesion: 0.33
Nodes (5): int, String, Batch, TSqlNormalizer, TSQLTextNormalizer

### Community 24 - "Alerting System"
Cohesion: 0.33
Nodes (6): CPU > 80% for 5m Alert, Disk Utilization > 70% Alert, Available Memory Below Min Alert, Alert Rules SQLMonitor, Email Contact Point, Slack Contact Point

### Community 27 - "Index & Table Management"
Cohesion: 0.40
Nodes (5): DDLs Folder, dbo.file_io_stats Table, TSQLTextNormalizer Assembly, dbo.wait_stats Table, dbo.xevent_metrics Table

### Community 28 - "Component 28"
Cohesion: 0.60
Nodes (4): _is_external(), on_page_content(), MkDocs hook: open external links in a new tab.  Rewrites every rendered ``<a hre, _rewrite()

### Community 33 - "Documentation"
Cohesion: 0.67
Nodes (3): Central Topology, Distributed Topology, Hybrid Topology Variants

### Community 38 - "Code Module"
Cohesion: 0.67
Nodes (3): CPU Collector, Disk Drive Collector, Windows Exporter Configuration

## Knowledge Gaps
- **114 isolated node(s):** `alertengine-on-podman.sh script`, `install-ms-odbc-drivers-18-sqlserver.sh script`, `Alerting`, `Credential-Manager`, `DDLs` (+109 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **33 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SmaAlert` connect `Component 0` to `Component 2`, `Component 5`, `Component 6`, `Component 7`, `Component 8`, `Component 9`, `Component 10`, `Component 11`, `Component 12`, `Component 13`, `Component 14`, `Component 15`, `Component 16`, `Component 17`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **Why does `SmaTempdbAlert` connect `Component 17` to `Component 0`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Why does `SmaSqlMonitorJobsAlert` connect `Component 16` to `Component 0`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Are the 17 inferred relationships involving `SmaAlert` (e.g. with `SmaAgDbBackupIssueAlert` and `SmaAgLatencyAlert`) actually correct?**
  _`SmaAlert` has 17 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `SQLMonitor` (e.g. with `Collection Tier` and `Consumption Tier`) actually correct?**
  _`SQLMonitor` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `get_pretty_table()` (e.g. with `.__compute_description()` and `.__compute_description()`) actually correct?**
  _`get_pretty_table()` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `get_sma_params()` (e.g. with `.__compute_sqlmonitor_dashboard_url()` and `.__compute_sqlmonitor_dashboard_url()`) actually correct?**
  _`get_sma_params()` has 15 INFERRED edges - model-reasoned connections that need verification._