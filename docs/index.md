---
title: SQLMonitor
description: Open-source SQL Server monitoring & alerting built on SQL Agent jobs, Grafana and Python.
hide:
  - navigation
---

# SQLMonitor

**Open-source Microsoft SQL Server monitoring, baselining, and alerting &mdash; powered by SQL Agent jobs and Grafana.**

SQLMonitor helps DBAs and developers understand *current load vs. usual load* across every SQL Server instance they operate &mdash; **DEV, TEST, UAT and PROD** &mdash; without the price tag of enterprise monitoring tools.

<div class="grid cards" markdown>

-   :material-view-dashboard-outline: **Live dashboards**

    Ready-to-import Grafana dashboards for server health, wait stats, query workload, disk space, backups, AGs, and more.

    [Browse dashboards &rarr;](dashboards/index.md)

-   :material-server-network: **SQL-Agent-native collection**

    Metric collection is plain SQL Agent jobs calling stored procedures &mdash; easy to read, debug and extend.

    [How it works &rarr;](architecture/index.md)

-   :material-download: **One-command deploy**

    A single PowerShell wrapper script onboards an instance end-to-end: objects, jobs, proxies, partitions, linked servers, logins.

    [Install SQLMonitor &rarr;](deployment/install.md)

-   :material-bell-alert-outline: **Alerting built-in**

    Python-based alert engine with routing to **PagerDuty, Slack and Email**.

    [Alerting guide &rarr;](alerting.md)

</div>

---

## Live demo

A fully-provisioned lab instance is available for you to click around:

[:material-rocket-launch: Open live dashboard](https://sqlmonitor.ajaydwivedi.com/d/distributed_live_dashboard/monitoring-live-distributed?orgId=1&refresh=5s){ .md-button .md-button--primary }
[:material-presentation-play: Job Activity Monitor](https://sqlmonitor.ajaydwivedi.com/d/job_activity_monitor/monitoring-live-all-servers-job-activity-monitor){ .md-button }

| Portal | URL | User | Password |
|---|---|---|---|
| Grafana | [sqlmonitor.ajaydwivedi.com](https://sqlmonitor.ajaydwivedi.com/dashboards?tag=sqlmonitor) | `guest` | `ajaydwivedi-guest` |
| SQL Instance | `sqlmonitor.ajaydwivedi.com:1433` | `grafana` | `grafana` |

![Live dashboards montage](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor/Live-Dashboards-All.gif?raw=true)

---

## What you get

| Capability | What it looks like |
|---|---|
| **Core health metrics** &mdash; CPU, Memory, Disk, I/O, Waits, Transactions, Active Requests, Blocking | [Monitoring - Live - Distributed](https://sqlmonitor.ajaydwivedi.com/d/distributed_live_dashboard/monitoring-live-distributed) |
| **Quest-recommended Perfmon counters** across every instance | [Monitoring - Perfmon Counters](https://sqlmonitor.ajaydwivedi.com/d/distributed_perfmon/monitoring-perfmon-counters-quest-softwares-distributed) |
| **WhoIsActive workload** &mdash; long runners, blockers, top consumers | [WhoIsActive - Workload](https://sqlmonitor.ajaydwivedi.com/d/WhoIsActive) |
| **Extended Events workload** &mdash; normalized & hashed query trends | [XEvent - Workload](https://sqlmonitor.ajaydwivedi.com/d/XEvents) / [Trend](https://sqlmonitor.ajaydwivedi.com/d/XEvents-Trends) |
| **Blitz Server Health & BlitzIndex Analysis** | [Blitz Server Health](https://sqlmonitor.ajaydwivedi.com/d/t___Blitz_Server_Health_Analysis) / [BlitzIndex](https://sqlmonitor.ajaydwivedi.com/d/t___BlitzIndex_Analysis) |
| **Availability Group health**, **Backup History**, **Disk Space**, **File IO Stats** | [AG Health](https://sqlmonitor.ajaydwivedi.com/d/ag_health_state) / [Backups](https://sqlmonitor.ajaydwivedi.com/d/backup_history) / [Disk](https://sqlmonitor.ajaydwivedi.com/d/disk_space) / [File IO](https://sqlmonitor.ajaydwivedi.com/d/database_file_io_stats) |
| **Alerting** via **PagerDuty / Slack / Email** | [Alert Engine](alerting.md) |
| **Optional** Prometheus path via `sql_exporter` + Windows Exporter | [Prometheus](prometheus.md) |

![Alert engine](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor-AlertEngine/Sma-Slack-3-Images-Gif.gif?raw=true)

---

## 60-second elevator pitch

!!! info "Why teams adopt SQLMonitor"

    - **No SaaS.** Everything runs on your own SQL Servers and Grafana.
    - **Boring tech on purpose.** Just SQL Agent jobs, stored procedures, T-SQL tables, PowerShell and Python. Debug it like any other DBA asset.
    - **Scales cheaply.** Hourly-partitioned tables with page compression. Memory-Optimized tables on the central inventory server. Dynamically parameterized Grafana queries so concurrent dashboard users do not thrash the monitor.
    - **Flexible topology.** Distributed (each instance monitors itself) **or** Central (one inventory server polls everyone) &mdash; same codebase.
    - **Broad SQL Server support.** All supported SQL Server versions (XEvent collection requires 2012+).

---

## Where next?

- New here? Start with **[Why SQLMonitor](why.md)** and **[Architecture](architecture/index.md)**.
- Ready to install? Jump to **[Deployment &rarr; Install Walkthrough](deployment/install.md)**.
- Looking for a specific dashboard? See the **[Dashboards Index](dashboards/index.md)**.
- Want to alert on something? See **[Alerting](alerting.md)**.

[:fontawesome-brands-github: Source on GitHub](https://github.com/imajaydwivedi/SQLMonitor){ .md-button }
[:fontawesome-brands-youtube: YouTube Playlist](https://ajaydwivedi.com/youtube/sqlmonitor){ .md-button }
[:fontawesome-brands-slack: #sqlmonitor on Slack](https://ajaydwivedi.com/sqlmonitor/slack){ .md-button }
