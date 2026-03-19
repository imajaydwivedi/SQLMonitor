# SQL Server Exporter Metrics Dashboard Documentation

## Overview

This repository now contains the current Grafana dashboard for SQL Server metrics exposed by `sql_exporter`:

- `sql_exporter/SQL-Exporter-Metrics-Dashboard.json`
  - cleaner operational layout intended for day-to-day use

The current dashboard details are:

- **Title:** `SQL Exporter Metrics`
- **UID:** `sql-exporter-metrics`
- **Panels:** 53
- **Rows:** 10
- **Metric families covered:** 74 `mssql_*` metrics from `sql_exporter/sql_exporter_metrics.txt`

Every panel includes a description so the dashboard remains self-documenting inside Grafana.

## Which Dashboard Should You Use?

### Use `SQL-Exporter-Metrics-Dashboard.json` when you want

- a cleaner operational layout
- a stronger top-level overview row
- better grouping for troubleshooting
- easier side-by-side monitoring of workload, waits, memory, I/O, and log pressure

## Dashboard Structure

### 1. Overview

Top-row KPIs for fast triage:

- **SQL Instance Up**: `mssql_up`
- **SQL Agent Service**: `mssql_service_info` filtered to SQL Server Agent
- **User Connections**: `mssql_user_connections`
- **Batch Req/sec**: rate of `mssql_batch_requests`
- **SQL CPU %**: `mssql_cpu_utilization_percentage`
- **Memory Util %**: `mssql_memory_utilization_percentage`
- **PLE (sec)**: `mssql_page_life_expectancy_seconds`
- **Max Log Used %**: max of `mssql_database_percent_log_used`

This row is intended to answer: **Is the instance up, busy, pressured, or approaching a log-space issue?**

### 2. Availability & Inventory

- Instance & service availability trend
- HA / replica queue gauges
- Exporter local time
- Service & instance metadata snapshot table
- Database inventory snapshot table

Use this row to confirm exporter coverage, instance availability, service state, and discovered database metadata.

### 3. Workload, Sessions & Connections

- connections by database
- login / logout / reset rates
- active cursors and SQL attentions

Use this row to understand connection churn and session pressure.

### 4. CPU, Compilation & Execution Patterns

- CPU by scope, resource pool, and workload group
- batch requests, compilations, recompilations, and auto-parameterization
- access methods activity

Use this row to identify CPU pressure, heavy compilation churn, and scan-heavy behavior.

### 5. Memory & Buffer Pool

- host / OS / page file memory
- SQL process memory and grant pressure
- memory manager breakdown
- buffer pool capacity
- buffer cache health
- buffer manager operations / checkpoints

Use this row for memory pressure analysis and buffer pool behavior.

### 6. I/O, Pages & Latches

- page lookup / read / write rates
- I/O stall by database
- latch, network I/O, and page I/O wait gauges

Use this row to correlate read/write patterns with storage or latch bottlenecks.

### 7. Transactions, Locks & Waits

- transaction activity
- blocking, lock waits, and deadlocks
- waits in progress

Use this row for contention investigations and long-running transaction analysis.

### 8. Database Storage & File Layout

- database file sizes
- database log used %
- XTP memory by database

Use this row for capacity review and per-database file footprint tracking.

### 9. Transaction Log, Redo & Data Movement

- log flushes / bytes / waits
- log wait time / events / growths
- mirroring / redo movement

Use this row when diagnosing log write pressure, AG / redo issues, or database growth events.

### 10. Errors & Tempdb

- SQL errors and connection kills
- tempdb space and temp objects
- misc operational counters

Use this row for application-facing issues, tempdb pressure, and general anomaly detection.

## Single-Server Selection

Both dashboards intentionally allow **one server at a time**.

### Variable details

- **Variable name:** `Server`
- **Query:** `label_values(mssql_up, instance)`
- **Multi-select:** `false`
- **Include All:** `false`

The `Server` selector still comes from `mssql_up` because it is now the clean instance-level availability metric and always carries the Prometheus `instance` target label.

### How it works

1. Select one target from the `Server` dropdown.
2. Every panel filters on `instance="$Server"`.
3. This prevents mixed-server graphs and makes troubleshooting clearer.

## Panel Descriptions

Every panel in the dashboard JSON includes a description that references the underlying metric family or families.

This is especially useful when:

- importing the dashboard into a new Grafana environment
- handing the dashboard to another DBA or SRE
- troubleshooting unfamiliar counters directly from the Grafana UI

## Metric Coverage

The dashboards were generated from the metrics reference file:

- `sql_exporter/sql_exporter_metrics.txt`

The current generated dashboards are intended to cover all discovered `mssql_*` metric families from that file.

Key domains represented include:

- availability
- connections and sessions
- workload and compilations
- CPU and memory
- buffer pool and page activity
- I/O and latch waits
- transactions, locks, and waits
- database file and log usage
- tempdb and errors

## Operational Interpretation Guide

### Healthy signals

- `mssql_up = 1` for the selected SQL instance
- `mssql_service_info = 1` for expected services such as SQL Server Agent
- CPU generally below sustained saturation
- memory utilization stable relative to your baseline
- page life expectancy stable or improving
- deadlocks near zero
- blocked processes near zero
- log used % comfortably below critical thresholds

### Warning signals

- rising recompilation rates
- falling PLE
- increasing blocked processes
- recurring deadlocks
- growing I/O stall rates
- rising tempdb usage
- persistent log growth events

### Critical signals

- SQL instance down (`mssql_up = 0` or absent)
- expected SQL services not reporting through `mssql_service_info`
- sustained high CPU or memory pressure
- log space nearing full
- sharp spike in waits / deadlocks / blocking
- rapid rise in SQL errors or kill-connection errors

## Import and Customization

### Recommended import target

Import this file:

- `sql_exporter/SQL-Exporter-Metrics-Dashboard.json`

### After import

1. select your Prometheus datasource
2. select a single `Server`
3. compare observed values against your own environment baseline
4. tune thresholds if your workload profile needs different warning levels

## Related Files

- `sql_exporter/SQL-Exporter-Metrics-Dashboard.json`
- `sql_exporter/SQL-Exporter-Metrics-QuickRef.md`
- `sql_exporter/sql_exporter_metrics.txt`

## References

- SQL Server DMV documentation: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/system-dynamic-management-views
- Grafana dashboard documentation: https://grafana.com/docs/grafana/latest/dashboards/
