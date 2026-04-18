# Components

Map of the repository. Every top-level folder has a single purpose &mdash; this page tells you which one to open for what.

## Top-level folder map

| Folder | Purpose | Representative files |
|---|---|---|
| **`SQLMonitor/`** | Deployment orchestration. The install/remove wrappers and all PowerShell collectors. | `Install-SQLMonitor.ps1`, `Remove-SQLMonitor.ps1`, `perfmon-collector-*.ps1`, `disk-space-collector.ps1`, `tasklist-push-to-sqlserver.ps1`, `check-instance-availability.py`, `collect_all_server_alert_messages.py` |
| **`DDLs/`** | All SQL objects: tables, views, procs, jobs, partition schemes. | `SCH-Create-All-Objects.sql`, `SCH-Create-Inventory-Specific-Objects.sql`, 60+ `SCH-Job-*.sql`, 40+ `SCH-usp_*.sql`, `*-Partitioning.sql` |
| **`Grafana-Dashboards/`** | 17+ production-ready dashboard JSONs. | `Monitoring - Live - Distributed.json`, `WhoIsActive - SQL Server Queries - Workload.json`, `XEvent - Workload.json`, `t___*.json` |
| **`Alerting/`** | Python alert engine (Flask + APScheduler). | `AlertEngineApp.py`, `SQLMonitorAlertEngineApp.py`, `SmaAlertPackage/`, `Dockerfile`, `requirements.txt`, `Deployment-Instructions/` |
| **`sql_exporter/`** | Optional Prometheus path: `burningalchemist/sql_exporter` collector configs + windows_exporter config. | `sql_exporter.yml`, `mssql_*.collector.yml`, `windows_exporter_config.yml`, `SQL-Exporter-Metrics-*.md` |
| **`TSQLTextNormalizer/`** | C# CLR assembly that normalizes + hashes T-SQL text (used by XEvent workload). | `TSqlNormalizer.cs`, `TSqlVisitor.cs`, `SCH-Assembly-[SQLMonitorAssembly].sql` |
| **`Python-Scripts/`** | Ancillary Python tools (multi-server runners, alert raisers, IP updaters, etc.). | `Run-MultiServer-Parallel-Pool.py`, `Raise-*Alert-*.py`, `Send-SlackAlert.py`, `cloudflare-ddns-update-Python.py` |
| **`PowerShell-Scripts-Miscellaneous/`** | Standalone PowerShell utilities not called by the installer. | `Run-MultiServerScript.ps1`, `Disable-ExpiredLogins.ps1`, `Encrypt-SQLDatabases.ps1`, `Test-Port.ps1` |
| **`Credential-Manager/`** | SQL-based credential store for Python scripts. | `SCH-[dbo].[credential_manager].sql`, `SCH-[dbo].[usp_add_credential].sql`, &hellip; |
| **`Permissions/`** | Role, login, and proxy permission scripts. | &hellip; |
| **`AI-Agent/`** | Experimental LLM agent over the SQLMonitor database. | `sql_db_agent_4_sqlmonitor_using_ollama.py`, `setup-ai-agent.md`, `requirements.txt` |
| **`Partition-Table-Demo-Scripts/`** | Standalone partitioning reference / demo scripts. | `dbo.usp_partition_maintenance.sql`, `Create-Partition-Function-Scheme-n-SampleTable-SampleData.sql` |
| **`Sql-Queries/`** | Ad-hoc diagnostic queries for DBAs. | `QRY-WhoIsActive-Infra.sql`, `QRY-XEventMetrics-*.sql`, `QRY-sp_BlitzCache-Specific.sql`, `QRY-Forecast-Database-Growth.sql` |
| **`Wrapper-Samples/`** | Sample wrapper scripts for multi-server install/update/remove runs. Copy to `Private/` and edit. | `Wrapper-InstallSQLMonitor.ps1`, `Wrapper-RemoveSQLMonitor.ps1`, `Wrapper-All-Servers-Update-SQLMonitor-Objects.ps1` |
| **`XEvent/`** | XEvent session definition + extraction queries (reference). | `01) XEvent Definition.sql`, `02) XEvent Extraction.sql` |
| **`replication-latency-infra/`** | Add-on for tracking replication / readable-secondary latency. | `replication-latency-infra.ssmssqlproj` |
| **`NoteBooks/`** | Azure Data Studio / Jupyter notebooks. | &hellip; |

## Key scripts you'll actually touch

### `SQLMonitor/Install-SQLMonitor.ps1`

The single entry point for onboarding an instance. Accepts 40+ parameters, supports **59 named install steps** (each skippable via `SkipSteps`/`OnlySteps`/`StartAtStep`/`StopAtStep`). Full parameter reference in [Deployment &rarr; Parameters](../deployment/parameters.md); step list in [Install Steps](../deployment/steps.md).

### `SQLMonitor/Remove-SQLMonitor.ps1`

Reverses the install. Supports **145+ named removal steps** (jobs &rarr; procs &rarr; views &rarr; tables &rarr; proxies &rarr; inventory entry), each controllable via `SkipSteps`/`OnlySteps`/`StartAtStep`/`StopAtStep`.

### `Wrapper-Samples/Wrapper-InstallSQLMonitor.ps1`

**Do not edit this directly.** Copy it to `Private/Wrapper-InstallSQLMonitor.ps1`, fill in your environment, and run from there. `Private/` is in `.gitignore`.

### `Alerting/SQLMonitorAlertEngineApp.py`

The alert engine daemon. Runs as a Flask app + APScheduler. Dockerfile included; deploy via `Alerting/Deployment-Instructions/alertengine-on-podman.sh` or as a Windows service.

## Database objects: naming conventions

- **Tables** &mdash; `dbo.snake_case` for collection tables (`dbo.wait_stats`, `dbo.file_io_stats`). `dbo.all_server_*` for inventory aggregates.
- **Procs** &mdash; `dbo.usp_collect_*`, `dbo.usp_get_*`, `dbo.usp_compute_*`, `dbo.usp_run_*`, `dbo.usp_purge_*`.
- **Jobs** &mdash; `(dba) <Verb>-<Subject>`, category `(dba) SQLMonitor`. See the full [Jobs & Collectors catalog](../jobs.md).
- **Proxy / credential** &mdash; whatever you supply to `Install-SQLMonitor.ps1`; a SQL Agent proxy is created for PowerShell & CmdExec subsystems.
- **Grafana login** &mdash; `grafana` with `db_datareader` on `DBA` (created by step `40__GrafanaLogin`).

## CLR assembly

`TSQLTextNormalizer.dll` exposes T-SQL functions used by:

- `dbo.usp_collect_xevent_metrics_hashed` &mdash; normalizes `sql_text` and hashes it to `query_hash`, so workload views can "group by logical query" instead of "group by parameter literal".
- `dbo.fn_get_hash_for_string` &mdash; scalar helper used in multiple procs.

The assembly is signed with `CLR_FETCH_QUERY.snk` and registered via `TSQLTextNormalizer/SCH-Assembly-[SQLMonitorAssembly].sql` during install step `2__AllDatabaseObjects`.
