import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent
METRICS_FILE = ROOT / "sql_exporter_metrics.txt"
OUTPUT_FILE = ROOT / "SQL-Exporter-Metrics-All-Metrics-Dashboard.json"
PROM = {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}


def parse_metric_meta(path: pathlib.Path):
    meta = {}
    for line in path.read_text().splitlines():
        if line.startswith("# HELP "):
            rest = line[7:]
            name, help_text = rest.split(" ", 1)
            meta.setdefault(name, {})["help"] = help_text
        elif line.startswith("# TYPE "):
            rest = line[7:]
            name, metric_type = rest.split(" ", 1)
            meta.setdefault(name, {})["type"] = metric_type
        elif line and not line.startswith("#"):
            m = re.match(r"([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{([^}]*)\})?", line)
            if not m:
                continue
            name = m.group(1)
            raw = m.group(2)
            item = meta.setdefault(name, {})
            item.setdefault("help", "")
            item.setdefault("type", "gauge")
            labels = item.setdefault("labels", set())
            if raw:
                for part in raw.split(","):
                    if "=" in part:
                        labels.add(part.split("=", 1)[0].strip())
    for item in meta.values():
        item["labels"] = sorted(item.get("labels", set()))
    return meta


class DashboardBuilder:
    def __init__(self, meta):
        self.meta = meta
        self.panels = []
        self.covered = set()
        self.next_id = 1
        self.y = 0

    def _id(self):
        out = self.next_id
        self.next_id += 1
        return out

    def _unit(self, metrics, unit):
        if unit != "auto":
            return unit
        names = " ".join(metrics)
        if "bytes" in names:
            return "bytes"
        if "percent" in names or "percentage" in names:
            return "percent"
        if "_ms" in names or "wait_time_ms" in names:
            return "ms"
        if "seconds" in names or names.endswith("_sec"):
            return "s"
        return "short"

    def _desc(self, metrics):
        return "\n".join(f"- {m}: {self.meta[m]['help']}" for m in metrics)

    def row(self, title):
        self.panels.append({
            "collapsed": False,
            "gridPos": {"h": 1, "w": 24, "x": 0, "y": self.y},
            "id": self._id(),
            "panels": [],
            "title": title,
            "type": "row",
        })
        self.y += 1

    def stat(self, title, metric, expr, x, w=3, h=4, unit="auto", thresholds=None, mappings=None):
        self.covered.add(metric)
        self.panels.append({
            "datasource": PROM,
            "description": self.meta[metric]["help"],
            "fieldConfig": {
                "defaults": {
                    "unit": self._unit([metric], unit),
                    "color": {"mode": "thresholds"},
                    "thresholds": thresholds or {"mode": "absolute", "steps": [{"color": "green", "value": None}]},
                    "mappings": mappings or [],
                },
                "overrides": [],
            },
            "gridPos": {"h": h, "w": w, "x": x, "y": self.y},
            "id": self._id(),
            "options": {
                "colorMode": "value",
                "graphMode": "area",
                "justifyMode": "center",
                "orientation": "auto",
                "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                "textMode": "auto",
            },
            "targets": [{"refId": "A", "expr": expr, "datasource": PROM}],
            "title": title,
            "type": "stat",
        })

    def timeseries(self, title, metrics, targets, x, w=8, h=8, unit="auto"):
        self.covered.update(metrics)
        self.panels.append({
            "datasource": PROM,
            "description": self._desc(metrics),
            "fieldConfig": {
                "defaults": {
                    "unit": self._unit(metrics, unit),
                    "color": {"mode": "palette-classic"},
                    "custom": {
                        "axisCenteredZero": False,
                        "axisColorMode": "text",
                        "axisPlacement": "auto",
                        "barAlignment": 0,
                        "drawStyle": "line",
                        "fillOpacity": 8,
                        "gradientMode": "none",
                        "lineInterpolation": "linear",
                        "lineWidth": 1,
                        "pointSize": 3,
                        "scaleDistribution": {"type": "linear"},
                        "showPoints": "auto",
                        "stacking": {"group": "A", "mode": "none"},
                        "thresholdsStyle": {"mode": "off"},
                    },
                },
                "overrides": [],
            },
            "gridPos": {"h": h, "w": w, "x": x, "y": self.y},
            "id": self._id(),
            "options": {
                "legend": {"calcs": [], "displayMode": "table", "placement": "bottom", "showLegend": True},
                "tooltip": {"mode": "multi", "sort": "desc"},
            },
            "targets": targets,
            "title": title,
            "type": "timeseries",
        })

    def table(self, title, metrics, expr, x=0, w=24, h=8):
        self.covered.update(metrics)
        self.panels.append({
            "datasource": PROM,
            "description": self._desc(metrics),
            "fieldConfig": {"defaults": {}, "overrides": []},
            "gridPos": {"h": h, "w": w, "x": x, "y": self.y},
            "id": self._id(),
            "options": {"cellHeight": "sm", "footer": {"countRows": False, "fields": "", "reducer": ["sum"], "show": False}, "showHeader": True},
            "targets": [{"refId": "A", "expr": expr, "format": "table", "instant": True, "datasource": PROM}],
            "title": title,
            "transformations": [],
            "type": "table",
        })

    def gap(self, h):
        self.y += h


def q(ref_id, expr, legend=None):
    out = {"refId": ref_id, "expr": expr, "datasource": PROM}
    if legend:
        out["legendFormat"] = legend
    return out


def build_dashboard(meta):
    b = DashboardBuilder(meta)
    b.row("Overview")
    b.stat("SQL Server Up", "mssql_service_info", 'max(mssql_service_info{instance="$Server",service_name="MSSQLSERVER"})', 0, thresholds={"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]}, mappings=[{"type": "value", "options": {"0": {"text": "Down", "color": "red"}, "1": {"text": "Up", "color": "green"}}}])
    b.stat("User Connections", "mssql_user_connections", 'mssql_user_connections{instance="$Server"}', 3)
    b.stat("Batch Req/sec", "mssql_batch_requests", 'sum(rate(mssql_batch_requests{instance="$Server"}[$__rate_interval]))', 6)
    b.stat("SQL CPU %", "mssql_cpu_utilization_percentage", 'mssql_cpu_utilization_percentage{instance="$Server",scope="sqlserver"}', 9, unit="percent", thresholds={"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "yellow", "value": 70}, {"color": "red", "value": 90}]})
    b.stat("Memory Util %", "mssql_memory_utilization_percentage", 'mssql_memory_utilization_percentage{instance="$Server"}', 12, unit="percent", thresholds={"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "yellow", "value": 75}, {"color": "red", "value": 90}]})
    b.stat("Blocked Processes", "mssql_processes_blocked", 'mssql_processes_blocked{instance="$Server"}', 15)
    b.stat("Deadlocks/sec", "mssql_deadlocks", 'sum(rate(mssql_deadlocks{instance="$Server"}[$__rate_interval]))', 18)
    b.stat("Max Log Used %", "mssql_database_percent_log_used", 'max(mssql_database_percent_log_used{instance="$Server"})', 21, unit="percent", thresholds={"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "yellow", "value": 70}, {"color": "red", "value": 90}]})
    b.gap(4)

    b.row("Availability & Instance")
    b.timeseries("Service Availability Trend", ["mssql_service_info"], [q("A", 'mssql_service_info{instance="$Server"}', "{{service_name_str}}")], 0)
    b.stat("Exporter Local Time", "mssql_local_time_seconds", 'mssql_local_time_seconds{instance="$Server"}', 8, w=4, h=8, unit="s")
    b.timeseries("Replication / AG Queue Gauges", ["mssql_log_apply_pending_queue", "mssql_log_remaining_for_undo", "mssql_log_send_queue", "mssql_transaction_delay"], [q("A", 'mssql_log_apply_pending_queue{instance="$Server"}', "Log apply pending"), q("B", 'mssql_log_remaining_for_undo{instance="$Server"}', "Remaining for undo"), q("C", 'mssql_log_send_queue{instance="$Server"}', "Log send queue"), q("D", 'mssql_transaction_delay{instance="$Server"}', "Transaction delay")], 12)
    b.gap(8)

    b.row("Workload, Connections & Sessions")
    b.timeseries("Connections by Database", ["mssql_connections"], [q("A", 'mssql_connections{instance="$Server"}', "{{db}}")], 0)
    b.timeseries("Session Activity Rates", ["mssql_logins", "mssql_logouts", "mssql_connection_reset"], [q("A", 'rate(mssql_logins{instance="$Server"}[$__rate_interval])', "Logins/sec"), q("B", 'rate(mssql_logouts{instance="$Server"}[$__rate_interval])', "Logouts/sec"), q("C", 'rate(mssql_connection_reset{instance="$Server"}[$__rate_interval])', "Resets/sec")], 8)
    b.timeseries("User Connections & Active Cursors", ["mssql_user_connections", "mssql_active_cursors"], [q("A", 'mssql_user_connections{instance="$Server"}', "User connections"), q("B", 'mssql_active_cursors{instance="$Server"}', "{{cursor_type}}")], 16)
    b.gap(8)

    b.row("CPU, Scheduling & Wait Pressure")
    b.timeseries("CPU Utilization", ["mssql_cpu_utilization_percentage"], [q("A", 'mssql_cpu_utilization_percentage{instance="$Server"}', "{{scope}}")], 0, unit="percent")
    b.timeseries("Resource Pool / Workload Group CPU", ["mssql_resource_pool_cpu_usage_percentage", "mssql_workload_group_cpu_usage_percentage"], [q("A", 'mssql_resource_pool_cpu_usage_percentage{instance="$Server"}', "Pool {{resource_pool}}"), q("B", 'mssql_workload_group_cpu_usage_percentage{instance="$Server"}', "Group {{workload_group}}")], 8, unit="percent")
    b.timeseries("Current Waits In Progress", ["mssql_waits_in_progress"], [q("A", 'mssql_waits_in_progress{instance="$Server"}', "{{wait_type}}")], 16)
    b.gap(8)

    b.row("Memory & Buffer Pool")
    b.timeseries("Host / OS Memory", ["mssql_host_physical_memory_bytes", "mssql_os_memory", "mssql_os_page_file"], [q("A", 'mssql_host_physical_memory_bytes{instance="$Server"}', "Host {{state}}"), q("B", 'mssql_os_memory{instance="$Server"}', "OS memory {{state}}"), q("C", 'mssql_os_page_file{instance="$Server"}', "OS page file {{state}}")], 0, unit="bytes")
    b.timeseries("SQL Process Memory", ["mssql_resident_memory_bytes", "mssql_virtual_memory_bytes", "mssql_sql_process_memory_bytes"], [q("A", 'mssql_resident_memory_bytes{instance="$Server"}', "Resident"), q("B", 'mssql_virtual_memory_bytes{instance="$Server"}', "Virtual"), q("C", 'mssql_sql_process_memory_bytes{instance="$Server"}', "{{state}}")], 8, unit="bytes")
    b.timeseries("Memory Manager Breakdown", ["mssql_memory_manager_bytes", "mssql_memory_grants_outstanding", "mssql_memory_grants_pending", "mssql_memory_utilization_percentage"], [q("A", 'mssql_memory_manager_bytes{instance="$Server"}', "Manager {{state}}"), q("B", 'mssql_memory_grants_outstanding{instance="$Server"}', "Outstanding grants"), q("C", 'mssql_memory_grants_pending{instance="$Server"}', "Pending grants"), q("D", 'mssql_memory_utilization_percentage{instance="$Server"}', "Memory util %")], 16)
    b.gap(8)
    b.timeseries("Buffer Pool Size & Commit Targets", ["mssql_buffer_database_pages", "mssql_buffer_target_pages", "mssqlbuffer_pool_committed", "mssqlbuffer_pool_committed_target"], [q("A", 'mssql_buffer_database_pages{instance="$Server"}', "Database pages"), q("B", 'mssql_buffer_target_pages{instance="$Server"}', "Target pages"), q("C", 'mssqlbuffer_pool_committed{instance="$Server"}', "Committed bytes"), q("D", 'mssqlbuffer_pool_committed_target{instance="$Server"}', "Committed target bytes")], 0)
    b.timeseries("Buffer Cache Health", ["mssql_buffer_cache_hit_ratio", "mssql_page_life_expectancy_seconds", "mssql_page_fault_count"], [q("A", 'mssql_buffer_cache_hit_ratio{instance="$Server"}', "Buffer cache hit ratio"), q("B", 'mssql_page_life_expectancy_seconds{instance="$Server"}', "Page life expectancy"), q("C", 'rate(mssql_page_fault_count{instance="$Server"}[$__rate_interval])', "Page faults/sec")], 8)
    b.timeseries("Buffer Manager Ops & Checkpoints", ["mssql_buffer_manager_operations_total", "mssql_checkpoint_pages_sec"], [q("A", 'rate(mssql_buffer_manager_operations_total{instance="$Server"}[$__rate_interval])', "{{operation}}"), q("B", 'mssql_checkpoint_pages_sec{instance="$Server"}', "Checkpoint pages/sec")], 16)
    b.gap(8)

    b.row("Access Methods, I/O & Latches")
    b.timeseries("Access Methods Activity", ["mssql_access_methods_total"], [q("A", 'rate(mssql_access_methods_total{instance="$Server"}[$__rate_interval])', "{{operation}}")], 0)
    b.timeseries("Page Lookups / Reads / Writes", ["mssql_page_lookups", "mssql_page_reads", "mssql_page_writes"], [q("A", 'rate(mssql_page_lookups{instance="$Server"}[$__rate_interval])', "Page lookups/sec"), q("B", 'rate(mssql_page_reads{instance="$Server"}[$__rate_interval])', "Page reads/sec"), q("C", 'rate(mssql_page_writes{instance="$Server"}[$__rate_interval])', "Page writes/sec")], 8)
    b.timeseries("I/O Stall by DB and Operation", ["mssql_io_stall_seconds", "mssql_io_stall_total_seconds"], [q("A", 'rate(mssql_io_stall_seconds{instance="$Server"}[$__rate_interval])', "{{db}} {{operation}}"), q("B", 'rate(mssql_io_stall_total_seconds{instance="$Server"}[$__rate_interval])', "{{db}} total")], 16)
    b.gap(8)
    b.timeseries("Latch / Network Wait Gauges", ["mssql_average_latch_wait_time_ms", "mssql_network_io_waits_ms", "mssql_page_io_latch_waits_ms"], [q("A", 'mssql_average_latch_wait_time_ms{instance="$Server"}', "Average latch wait ms"), q("B", 'mssql_network_io_waits_ms{instance="$Server"}', "Network IO waits ms"), q("C", 'mssql_page_io_latch_waits_ms{instance="$Server"}', "Page IO latch waits ms")], 0, unit="ms")
    b.gap(8)

    b.row("Transactions, Locks & Concurrency")
    b.timeseries("Transaction Gauges", ["mssql_active_transactions_count", "mssql_longest_transaction_running_time_seconds", "mssql_processes_blocked"], [q("A", 'mssql_active_transactions_count{instance="$Server"}', "Active transactions"), q("B", 'mssql_longest_transaction_running_time_seconds{instance="$Server"}', "Longest running transaction sec"), q("C", 'mssql_processes_blocked{instance="$Server"}', "Blocked processes")], 0)
    b.timeseries("Lock Waits / Wait Time / Deadlocks", ["mssql_lock_waits_total", "mssql_lock_wait_time_ms_total", "mssql_deadlocks"], [q("A", 'rate(mssql_lock_waits_total{instance="$Server"}[$__rate_interval])', "Lock waits/sec"), q("B", 'rate(mssql_lock_wait_time_ms_total{instance="$Server"}[$__rate_interval])', "Lock wait ms/sec"), q("C", 'rate(mssql_deadlocks{instance="$Server"}[$__rate_interval])', "Deadlocks/sec")], 8)
    b.timeseries("Database Active Transactions", ["mssql_database_active_transactions"], [q("A", 'mssql_database_active_transactions{instance="$Server"}', "{{db}}")], 16)
    b.gap(8)

    b.row("Databases, Files & Inventory")
    b.timeseries("Database File Sizes", ["mssql_database_file_size_bytes"], [q("A", 'mssql_database_file_size_bytes{instance="$Server"}', "{{db}} {{state}}")], 0, unit="bytes")
    b.timeseries("Database Log Used %", ["mssql_database_percent_log_used"], [q("A", 'mssql_database_percent_log_used{instance="$Server"}', "{{db}}")], 8, unit="percent")
    b.timeseries("Database XTP Memory", ["mssql_database_xtp_memory_used_bytes"], [q("A", 'mssql_database_xtp_memory_used_bytes{instance="$Server"}', "{{db}}")], 16, unit="bytes")
    b.gap(8)
    b.table("Database Inventory Snapshot", ["mssql_database_info"], 'mssql_database_info{instance="$Server"}')
    b.gap(8)

    b.row("Transaction Log, Redo & Data Movement")
    b.timeseries("Log Flushes / Bytes / Waits", ["mssql_database_log_flushes_total", "mssql_database_log_bytes_flushed_total", "mssql_database_log_waits_total"], [q("A", 'rate(mssql_database_log_flushes_total{instance="$Server"}[$__rate_interval])', "{{db}} flushes/sec"), q("B", 'rate(mssql_database_log_bytes_flushed_total{instance="$Server"}[$__rate_interval])', "{{db}} bytes/sec"), q("C", 'rate(mssql_database_log_waits_total{instance="$Server"}[$__rate_interval])', "{{db}} waits/sec")], 0)
    b.timeseries("Log Flush Wait Time", ["mssql_database_log_flush_wait_time_ms_total"], [q("A", 'rate(mssql_database_log_flush_wait_time_ms_total{instance="$Server"}[$__rate_interval])', "{{db}} ms/sec")], 8, unit="ms")
    b.timeseries("Log Events & Growths", ["mssql_database_log_events_total", "mssql_log_growths"], [q("A", 'rate(mssql_database_log_events_total{instance="$Server"}[$__rate_interval])', "{{db}} {{event}}"), q("B", 'rate(mssql_log_growths{instance="$Server"}[$__rate_interval])', "{{db}} growths")], 16)
    b.gap(8)
    b.timeseries("Redo / Mirroring Movement", ["mssql_mirrored_write_transactions", "mssql_redo_blocked"], [q("A", 'rate(mssql_mirrored_write_transactions{instance="$Server"}[$__rate_interval])', "Mirrored write tx/sec"), q("B", 'rate(mssql_redo_blocked{instance="$Server"}[$__rate_interval])', "Redo blocked/sec")], 0)
    b.gap(8)

    b.row("SQL Compilation, Errors & Tempdb")
    b.timeseries("Compilations / Recompilations / Auto Params", ["mssql_sql_compilations", "mssql_sql_recompilations", "mssql_sql_auto_params_total"], [q("A", 'rate(mssql_sql_compilations{instance="$Server"}[$__rate_interval])', "Compilations/sec"), q("B", 'rate(mssql_sql_recompilations{instance="$Server"}[$__rate_interval])', "Recompilations/sec"), q("C", 'rate(mssql_sql_auto_params_total{instance="$Server"}[$__rate_interval])', "{{mode}}/sec")], 0)
    b.timeseries("SQL Errors & Attentions", ["mssql_sql_errors_total", "mssql_user_errors", "mssql_kill_connection_errors", "mssql_sql_attentions_total"], [q("A", 'rate(mssql_sql_errors_total{instance="$Server"}[$__rate_interval])', "{{error_type}}/sec"), q("B", 'rate(mssql_user_errors{instance="$Server"}[$__rate_interval])', "User errors/sec"), q("C", 'rate(mssql_kill_connection_errors{instance="$Server"}[$__rate_interval])', "Kill connection errors/sec"), q("D", 'rate(mssql_sql_attentions_total{instance="$Server"}[$__rate_interval])', "SQL attentions/sec")], 8)
    b.timeseries("Tempdb & Temp Objects", ["mssql_tempdb_active_temp_tables", "mssql_tempdb_space_bytes", "mssql_temp_tables_for_destruction"], [q("A", 'mssql_tempdb_active_temp_tables{instance="$Server"}', "Active temp tables"), q("B", 'mssql_tempdb_space_bytes{instance="$Server"}', "tempdb {{state}}"), q("C", 'mssql_temp_tables_for_destruction{instance="$Server"}', "Awaiting destruction")], 16, unit="bytes")
    b.gap(8)

    uncovered = sorted(set(meta) - b.covered)
    if uncovered:
        raise RuntimeError(f"Uncovered metrics: {uncovered}")
    return {
        "__inputs": [{"name": "DS_PROMETHEUS", "label": "Prometheus", "description": "Prometheus data source for SQL Exporter metrics", "type": "datasource", "pluginId": "prometheus", "pluginName": "Prometheus"}],
        "__requires": [{"type": "grafana", "id": "grafana", "name": "Grafana", "version": "11.3.1"}, {"type": "datasource", "id": "prometheus", "name": "Prometheus", "version": "1.0.0"}, {"type": "panel", "id": "timeseries", "name": "Time series", "version": ""}, {"type": "panel", "id": "stat", "name": "Stat", "version": ""}, {"type": "panel", "id": "table", "name": "Table", "version": ""}],
        "annotations": {"list": [{"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)", "name": "Annotations & Alerts", "type": "dashboard"}]},
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "id": None,
        "links": [],
        "panels": b.panels,
        "refresh": "30s",
        "schemaVersion": 40,
        "tags": ["SQL Server", "sql_exporter", "all-metrics", "prometheus"],
        "templating": {"list": [{"current": {"text": "Prometheus", "value": "Prometheus"}, "description": "Prometheus data source for SQL Exporter metrics", "hide": 2, "includeAll": False, "label": "Data Source", "multi": False, "name": "prometheus_datasource", "options": [], "query": "prometheus", "refresh": 1, "regex": "", "skipUrlSync": False, "sort": 0, "tagValuesQuery": "", "tagsQuery": "", "type": "datasource", "useTags": False}, {"current": {}, "datasource": {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}, "definition": "label_values(mssql_up, instance)", "description": "Select one Prometheus target/server at a time. Multi-select is intentionally disabled.", "hide": 0, "includeAll": False, "label": "Server", "multi": False, "name": "Server", "options": [], "query": "label_values(mssql_up, instance)", "refresh": 1, "regex": "", "skipUrlSync": False, "sort": 1, "tagValuesQuery": "", "tagsQuery": "", "type": "query", "useTags": False}]},
        "time": {"from": "now-6h", "to": "now"},
        "timepicker": {},
        "timezone": "browser",
        "title": "SQL Exporter Metrics - All Metrics",
        "uid": "sql-exporter-metrics-all",
        "version": 1,
        "weekStart": "",
    }


if __name__ == "__main__":
    dashboard = build_dashboard(parse_metric_meta(METRICS_FILE))
    OUTPUT_FILE.write_text(json.dumps(dashboard, indent=2))
    print(f"Wrote {OUTPUT_FILE}")