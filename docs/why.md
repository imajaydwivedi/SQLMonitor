# Why SQLMonitor?

SQLMonitor was built to solve a practical problem: **DBA teams need to see, correlate and alert on SQL Server behavior across every environment &mdash; without paying per-instance licenses** and without locking themselves into a SaaS that cannot see their on-prem DEV/UAT clusters.

## The problem

Existing monitoring products typically fall into one of three buckets:

- **Enterprise-priced tools** (SolarWinds DPA, Quest Spotlight, Redgate SQL Monitor, SentryOne/SolarWinds). Excellent, but per-instance licensing usually means you only buy coverage for PROD &mdash; which is exactly where you *least* want to tune under fire, because you have no baseline from non-prod to compare against.
- **Generic APMs** (Datadog, New Relic). They surface *some* SQL metrics, but rarely the DBA-specific diagnostics (wait stats, WhoIsActive-style live workload, BlitzIndex recommendations, AG health, file IO latency bucketed per drive).
- **Home-grown scripts.** Every team has them. They tend to be undocumented, not partitioned, not purged, and no one knows which server runs the scheduler.

SQLMonitor is a fourth option: an **open, script-first** toolkit that:

- monitors **every** environment (DEV/UAT/QA/PROD) because there is no per-instance cost,
- uses **SQL-Agent-native** collection so any DBA can read, debug and extend it,
- ships with **ready-made Grafana dashboards** for the things DBAs actually look at.

## Design principles

### 1. Boring, legible tech

Collection is SQL Agent jobs calling stored procedures. Visualization is Grafana reading SQL Server directly (or, optionally, Prometheus via [`burningalchemist/sql_exporter`][sqlexp]). No agents, no collectors-of-collectors, no proprietary binary protocols.

### 2. Minimal footprint on the monitored instance

- Perfmon data is captured to **small BLG/XML files** and bulk-loaded &mdash; not a polling T-SQL query storm.
- Extended Events sessions use **small file targets** that are consumed and removed by `(dba) Collect-XEvents` + `(dba) Remove-XEventFiles`.
- Query text is **normalized and hashed** by a CLR assembly (`TSQLTextNormalizer`) so we store one row per logical query, not per parameter variant.
- Tables are **hourly-partitioned and page-compressed** (where the edition supports it). Purging is declarative in `dbo.purge_table`.

### 3. Scales through data-engineering, not hardware

- Core stability metrics land in **Memory-Optimized tables** on the inventory server.
- Grafana panel queries are **dynamically parameterized T-SQL** so they use the same execution plans regardless of `$__timeFilter` range &mdash; letting the plan cache actually work when 20 people open dashboards at once.
- Data destination is decoupled: the instance being baselined can push to a *different* SQL instance of your choice. Large fleets push to a dedicated observability SQL server.

### 4. One switch between Central and Distributed

SQLMonitor supports both [topologies](architecture/topology.md) with the same codebase. Small shops use **Distributed** (each instance monitors itself, a single inventory server aggregates). Large fleets use **Central** with all jobs running on the observability server. Same jobs, same tables, same dashboards.

### 5. Alert on what the dashboard shows

The [Alert Engine](alerting.md) reads the same tables the dashboards read. If you can graph it, you can alert on it.

## What SQLMonitor is *not*

- **Not a SaaS.** You host it. That is the point.
- **Not a replacement for Brent Ozar's [First Responder Kit][fr]** &mdash; SQLMonitor *orchestrates* `sp_Blitz`, `sp_BlitzIndex`, `sp_WhoIsActive` and persists their output; it does not re-implement them.
- **Not a silver bullet for badly-tuned queries.** It tells you *where* to look; tuning is still your job.

## When NOT to use SQLMonitor

- You only have one SQL instance and already pay for Redgate / Quest / Datadog and are happy with it &mdash; don't switch for the sake of it.
- You are on Linux SQL Server with no Windows host anywhere in the picture &mdash; the **inventory server** is fully supported on Linux (see [Linux Inventory Server](deployment/linux-inventory.md)), but several *monitored-instance* collectors (Perfmon BLG ingestion, OS process capture) still rely on Windows PowerShell. The SQL-only collectors work everywhere, so a Linux-only fleet leaves a few per-instance dashboards empty.
- You want **zero code on the monitored instance**. SQLMonitor installs objects into the `DBA` database on every instance.

## Feature summary

- :material-check: Distributed **or** Central topology &mdash; same repo
- :material-check: Ships 17+ production-ready Grafana dashboards
- :material-check: Perfmon + XEvent + WaitStats + FileIO + MemoryClerks + AG + Backups + DiskSpace + WhoIsActive + OS Processes
- :material-check: BrentOzar First Responder Kit (sp_Blitz / sp_BlitzIndex / sp_BlitzCache) scheduled & persisted
- :material-check: Darling Data (`sp_HumanEvents`, etc.) bundled
- :material-check: Ola Hallengren Maintenance Solution bundled
- :material-check: Python alert engine with **PagerDuty / Slack / Email** routing
- :material-check: Optional Prometheus path via `sql_exporter` + `windows_exporter`
- :material-check: CLR-based **T-SQL text normalizer** for hashed workload views
- :material-check: Automatic hourly partitioning & page compression
- :material-check: Declarative purging via `dbo.purge_table`
- :material-check: Optional **AI agent** (Ollama + LangChain) over the collected data

[sqlexp]: https://github.com/burningalchemist/sql_exporter
[fr]: https://www.brentozar.com/first-aid/
