# SQL Server Metrics Quick Reference

## Recommended Dashboard

Use:

- `sql_exporter/SQL-Exporter-Metrics-Dashboard.json`

This is the cleaner operational dashboard.

### Current dashboard facts

- **Grafana title:** `SQL Exporter Metrics`
- **UID:** `sql-exporter-metrics`
- **Panels:** 53
- **Rows:** 10
- **Metrics covered:** 74 `mssql_*` metric families
- **Server selector:** single-select only

## Key Features

✅ **Single Server Selection** - one instance at a time  
✅ **Overview KPIs** - fast operational triage  
✅ **Category Rows** - organized by troubleshooting domain  
✅ **Trend Panels** - time-series views for operational drift  
✅ **Panel Descriptions** - each panel documents its metric source  
✅ **Inventory Tables** - service and database snapshots  

---

## Row-by-Row Layout

| Row | Purpose | Example Panels |
|-----|---------|----------------|
| Overview | Fast health check | SQL Instance Up, SQL Agent Service, User Connections, SQL CPU %, PLE |
| Availability & Inventory | Instance/service state and discovered objects | Instance & Service Availability, Metadata Snapshot, Database Inventory Snapshot |
| Workload, Sessions & Connections | Connection churn and session pressure | Connections by Database, Login/Logout/Reset Rates |
| CPU, Compilation & Execution Patterns | CPU pressure and plan churn | CPU by Scope, Batch/Compilation Trends, Access Methods |
| Memory & Buffer Pool | Memory pressure and cache behavior | Host/OS Memory, Memory Grants, Buffer Cache Health |
| I/O, Pages & Latches | Disk and latch bottlenecks | Page Read/Write Rates, I/O Stall by Database |
| Transactions, Locks & Waits | Contention analysis | Transaction Activity, Blocking/Deadlocks, Waits in Progress |
| Database Storage & File Layout | Capacity and file footprint | File Sizes, Log Used %, XTP Memory |
| Transaction Log, Redo & Data Movement | Log write and HA flow analysis | Log Flushes, Log Events/Growths, Mirroring/Redo |
| Errors & Tempdb | Error spikes and tempdb pressure | SQL Errors, Tempdb Space, Temp Objects |

---

## Overview KPIs to Watch First

| KPI | Metric Basis | Healthy Direction |
|-----|--------------|------------------|
| SQL Instance Up | `mssql_up` | should be `1` |
| SQL Agent Service | `mssql_service_info{service_name="SQLSERVERAGENT"}` | should be `1` when expected |
| User Connections | `mssql_user_connections` | stable around baseline |
| Batch Req/sec | `rate(mssql_batch_requests)` | workload-dependent baseline |
| SQL CPU % | `mssql_cpu_utilization_percentage` | avoid sustained high values |
| Memory Util % | `mssql_memory_utilization_percentage` | stable relative to baseline |
| PLE (sec) | `mssql_page_life_expectancy_seconds` | stable / higher is generally better |
| Max Log Used % | `mssql_database_percent_log_used` | keep comfortably below critical |

---

## Single-Server Filtering

The dashboard intentionally restricts analysis to **one server at a time**.

- **Variable:** `Server`
- **Query:** `label_values(mssql_up, instance)`
- **Multi-select:** disabled
- **Include All:** disabled

The selector uses `mssql_up` because it is now the instance-level metric, while `mssql_service_info` holds service-specific state and metadata.

All Prometheus queries filter on:

- `instance="$Server"`

This prevents cross-server mixing in the same graph.

---

## Quick Triage Guide

### If CPU is high

Check these rows in order:

1. **Overview** - confirm CPU spike
2. **CPU, Compilation & Execution Patterns** - compilations, recompilations, scans
3. **Workload, Sessions & Connections** - connection surge

### If memory pressure is suspected

Check:

1. **Overview** - Memory Util % and PLE
2. **Memory & Buffer Pool** - grants, cache health, page faults
3. **I/O, Pages & Latches** - rising physical reads / page activity

### If blocking or slowness is reported

Check:

1. **Transactions, Locks & Waits**
2. **I/O, Pages & Latches**
3. **Transaction Log, Redo & Data Movement**

### If log growth is a concern

Check:

1. **Overview** - Max Log Used %
2. **Database Storage & File Layout** - per-database log used %
3. **Transaction Log, Redo & Data Movement** - flush waits, events, growths

---

## Baseline Template

Record these against a known-good period:

- Batch Requests/sec
- SQL CPU %
- Memory Util %
- Page Life Expectancy
- Max Log Used %
- I/O Stall by Database
- Deadlocks/sec
- Lock Waits/sec
- User Connections

---

## File Locations

- `sql_exporter/SQL-Exporter-Metrics-Dashboard.json`
- `sql_exporter/SQL-Exporter-Metrics-Documentation.md`
- `sql_exporter/SQL-Exporter-Metrics-QuickRef.md`
- `sql_exporter/sql_exporter_metrics.txt`

---

## Recommended Import Choice

Import this dashboard:

- `sql_exporter/SQL-Exporter-Metrics-Dashboard.json`

---

**Last Updated:** 2026-03-17  
**Dashboard Version:** 2.0  
**Metrics Covered:** 74  
**Panels:** 53  
