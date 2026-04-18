# Architecture

SQLMonitor's architecture has three logical tiers:

1. **Collection tier** &mdash; SQL Agent jobs (plus PowerShell and Python scripts) capture metrics from the monitored instance and its host OS.
2. **Storage tier** &mdash; collected metrics land in hourly-partitioned, page-compressed tables inside the `DBA` database. Core stability metrics use Memory-Optimized tables on the inventory server.
3. **Consumption tier** &mdash; Grafana dashboards, the Python alert engine, optional Prometheus (`sql_exporter`), and an optional AI agent all read from those tables.

``` mermaid
flowchart LR
    subgraph HOST["Monitored Windows host"]
        PERF[Perfmon BLG files]
        XE[XEvent .xel files]
        OS[OS processes / Tasklist]
    end
    subgraph INST["Monitored SQL instance (DBA database)"]
        AGENT[SQL Agent jobs]
        PROCS[Stored procedures<br/>usp_collect_*]
        TABLES[(Collection tables<br/>hourly-partitioned)]
    end
    subgraph INV["Inventory server (DBA database)"]
        AGG[Aggregation jobs<br/>Get-AllServer*]
        ALL[(all_server_*<br/>tables, Memory-Optimized)]
    end
    subgraph OBS["Observability plane"]
        GRAF[Grafana]
        PROM[Prometheus + sql_exporter]
        ALERT[Python Alert Engine]
        AI[AI Agent - Ollama]
    end
    PAGER[PagerDuty / Slack / Email]

    PERF & XE & OS --> AGENT
    AGENT --> PROCS --> TABLES
    TABLES -- linked server --> AGG
    AGG --> ALL
    ALL --> GRAF
    TABLES --> GRAF
    TABLES --> PROM
    ALL --> ALERT --> PAGER
    ALL --> AI
```

## Reading guide

- **[Topology](topology.md)** &mdash; the two deployment shapes (Distributed and Central) and where each SQL Agent job runs in each.
- **[Data Flow](data-flow.md)** &mdash; how a single metric (CPU %, wait stats, XEvent workload, &hellip;) flows from the OS to your screen, including purge and partition lifecycle.
- **[Components](components.md)** &mdash; a map of every folder in the repo and what it does.
- **[Data Model](data-model.md)** &mdash; the table layout (per-instance collection tables vs. `all_server_*` inventory tables), partitioning and purging.

## The three tiers at a glance

| Tier | Lives on | Files in repo | Runs as |
|---|---|---|---|
| Collection | Each monitored instance *or* a dedicated collector instance | `DDLs/SCH-Job-*.sql`, `SQLMonitor/*.ps1`, `DDLs/SCH-usp_collect_*.sql` | SQL Agent jobs (T-SQL, PowerShell proxy, or CmdExec calling `python`) |
| Storage | Monitored instance (`DBA` DB) + inventory instance (`DBA` DB) | `DDLs/SCH-Create-All-Objects.sql`, `DDLs/SCH-Create-Inventory-Specific-Objects.sql`, `DDLs/SCH-*-Partitioning.sql` | Tables & views, automatically partitioned hourly, page-compressed |
| Consumption | Grafana / Prometheus / alert host | `Grafana-Dashboards/*.json`, `sql_exporter/*.yml`, `Alerting/*.py` | Grafana data source, Prometheus job, Flask+APScheduler service |

## Why three tiers matter

- **Failure isolation.** The Grafana host can be recycled or re-imaged without any metric loss &mdash; data lives in SQL.
- **Multiple readers.** Grafana, the alert engine, the AI agent, a BI tool, or your own ad-hoc T-SQL can all query the same truth.
- **Performance.** Collection writes are light; reads are amortized across many consumers.

## Where to go next

- If you are installing for the first time &rarr; start with **[Deployment &rarr; Prerequisites](../deployment/prerequisites.md)**.
- If you are evaluating &rarr; continue with **[Topology](topology.md)**.
