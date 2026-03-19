## Resumable Retry Plan

### Objective
1. Inventory metrics/data covered by `Grafana-Dashboards/*.json` and `DDLs/SCH-usp_collect_performance_metrics.sql`.
2. Ensure matching coverage exists in `sql_exporter/mssql_*.collector.yml`; add missing items to `sql_exporter/mssql_dba_metrics.collector.yml`.
3. Copy `Grafana-Dashboards/Monitoring - Perfmon Counters - Quest Softwares - Distributed.json` into `sql_exporter/` and retarget its datasource/queries to `sql_exporter` metrics without changing layout, thresholds, or titles.

### Checkpoints
- [ ] Step 01A: Extract dashboard metric inventory from `Grafana-Dashboards/`
- [ ] Step 01B: Extract procedure metric/data inventory from `DDLs/SCH-usp_collect_performance_metrics.sql`
- [ ] Step 01C: Compare inventory with `sql_exporter/mssql_*.collector.yml`
- [ ] Step 01D: Add missing items to `sql_exporter/mssql_dba_metrics.collector.yml`
- [ ] Step 02A: Copy Perfmon dashboard into `sql_exporter/`
- [ ] Step 02B: Retarget datasource and queries to `sql_exporter` metrics
- [ ] Step 02C: Validate migrated dashboard JSON

### Current status
- Active phase: Step 01A / Step 01B inventory gathering
- Notes: task list created and repository scope confirmed.

### Resume instructions
- Re-open this file first.
- Continue from the first unchecked checkpoint.
- Re-run only the inventory/validation commands for the incomplete phase.

