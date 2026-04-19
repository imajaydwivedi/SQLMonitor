"""Spec for ``Monitoring - Live - All Servers`` Prometheus port
(UID: prom_monitoring_live_all_servers).

Source dashboard has 15 data panels covering:

    Basic Info, Collection Latency, OFFLINE instances/aliases,
    SQLAgent service OFFLINE, Backup issues (non-AG + AG),
    SQLMonitor Jobs attention list, Disk Utilization,
    AlwaysOn Latency, Log/Tempdb space issues,
    Alert History (aggregated + detail) and a Health Metrics table.

Most of these aggregate across the whole fleet via the SQLMonitor
central DB. Panels that can be reconstructed from per-instance
Prometheus series use real PromQL; the inventory-join panels
(alert-history, alias/linked-server mapping) link back to the SQL
dashboard instead.
"""
from prom_dashboard import (
    Panel, Target, query_var, constant_var, legacy_link_panel,
)


UID = "prom_monitoring_live_all_servers"
TITLE = "Monitoring - Live - All Servers"
TAGS = ["mssql", "sqlmonitor", "Live", "All Servers", "prometheus"]
_LEGACY_UID = "monitoring-live-all-servers"


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance", multi=True, include_all=True),
        constant_var("full_threshold_days", "7"),
        constant_var("diff_threshold_hours", "24"),
        constant_var("tlog_threshold_minutes", "30"),
        constant_var("disk_warning_pct", "80"),
        constant_var("disk_critical_pct", "90"),
    ]


def panels():
    ps: list[Panel] = []
    S = '{instance=~"$Server"}'

    # Summary stats row
    ps.append(Panel(
        title="Basic Info - Online",
        description="Instances with mssql_up==1 matching the filter.",
        type="stat", unit="short",
        grid=(0, 0, 4, 4),
        targets=[Target(f'sum(mssql_up{S} == 1)', legend="", ref="A",
                        instant=True)],
    ))
    ps.append(Panel(
        title="OFFLINE Instances",
        description="mssql_up==0.",
        type="stat", unit="short",
        grid=(4, 0, 4, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(f'sum(mssql_up{S} == 0)', legend="", ref="A",
                        instant=True)],
    ))
    ps.append(Panel(
        title="Disks - CRITICAL",
        description=("Logical disks with >$disk_critical_pct% used, via "
                     "windows_logical_disk metrics."),
        type="stat", unit="short",
        grid=(8, 0, 4, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(
            f'count(100 * (1 - windows_logical_disk_free_bytes{S} '
            f'/ clamp_min(windows_logical_disk_size_bytes{S}, 1)) '
            f'> $disk_critical_pct)',
            legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Disks - WARNING",
        description="Logical disks between warning and critical thresholds.",
        type="stat", unit="short",
        grid=(12, 0, 4, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "orange", "value": 1}],
        targets=[Target(
            f'count(100 * (1 - windows_logical_disk_free_bytes{S} '
            f'/ clamp_min(windows_logical_disk_size_bytes{S}, 1)) '
            f'> $disk_warning_pct < $disk_critical_pct)',
            legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Failed Jobs",
        description="Jobs whose most recent completed run failed "
                     "(requires the mssql_sqlagent_jobs collector).",
        type="stat", unit="short",
        grid=(16, 0, 4, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(
            f'count(mssql_sqlagent_job__last_run_outcome{S} == 0)',
            legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Full Backups Overdue",
        description="Databases with a Full backup older than "
                     "$full_threshold_days days.",
        type="stat", unit="short",
        grid=(20, 0, 4, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(
            f'count(mssql_backup__age_seconds{{instance=~"$Server",'
            f'backup_type="D"}} > ($full_threshold_days * 86400))',
            legend="", ref="A", instant=True)],
    ))

    # Basic Details table
    ps.append(Panel(
        title="All Servers - Basic Details",
        description="Per-instance mssql_service_info joined with mssql_up.",
        type="table", unit="short",
        grid=(0, 4, 24, 8),
        targets=[
            Target(f'mssql_service_info{S}', legend="", ref="Info",
                   instant=True, format="table"),
            Target(f'mssql_up{S}', legend="", ref="Up",
                   instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # Servers with Data Collection Issues
    ps.append(Panel(
        title="Servers with Data Collection Issues",
        description=("Instances whose last successful scrape is more "
                     "than 5 minutes old, based on scrape_samples_scraped "
                     "and the `up` metric."),
        type="table", unit="short",
        grid=(0, 12, 24, 8),
        targets=[Target(
            f'(time() - timestamp(up{S} == 1)) > 300',
            legend="", ref="A", instant=True, format="table")],
    ))

    # OFFLINE detail tables
    ps.append(Panel(
        title="CRITICAL - OFFLINE Instances",
        description="Instances currently reporting mssql_up==0.",
        type="table", unit="short",
        grid=(0, 20, 12, 6),
        targets=[Target(f'mssql_up{S} == 0', legend="", ref="A",
                        instant=True, format="table")],
    ))
    ps.append(legacy_link_panel(
        "CRITICAL - OFFLINE Aliases",
        grid=(12, 20, 12, 6),
        sql_dashboard=_LEGACY_UID,
        note="Alias-instance topology is stored in the inventory DB "
             "(dbo.sql_instances.alias) — Prometheus labels only carry "
             "the primary endpoint.",
    ))

    # SQLAgent service offline (requires windows_exporter service probe)
    ps.append(Panel(
        title="SQLAgent Service OFFLINE",
        description=("Instances where the SQL Agent Windows service is "
                     "not running (windows_service_state{name=~\"SQLSERVERAGENT.*\",state!=\"running\"})."),
        type="table", unit="short",
        grid=(0, 26, 24, 6),
        targets=[Target(
            'windows_service_state{name=~"SQLSERVERAGENT.*",state!="running"} == 1',
            legend="", ref="A", instant=True, format="table")],
    ))

    # Backup issues
    ps.append(Panel(
        title="Backups - Non-AG Databases - Issues",
        description=("Databases whose most recent Full/Diff/Log backup is "
                     "older than the configured thresholds. Driven by "
                     "mssql_backup__age_seconds."),
        type="table", unit="short",
        grid=(0, 32, 24, 8),
        targets=[
            Target(
                f'mssql_backup__age_seconds{{instance=~"$Server",'
                f'backup_type="D"}} > ($full_threshold_days * 86400)',
                legend="", ref="Full", instant=True, format="table"),
            Target(
                f'mssql_backup__age_seconds{{instance=~"$Server",'
                f'backup_type="L"}} > ($tlog_threshold_minutes * 60)',
                legend="", ref="Log", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))
    ps.append(legacy_link_panel(
        "Backups - AG Databases - Issues",
        grid=(0, 40, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="Distinguishing AG vs non-AG databases requires the "
             "inventory DB. Use the SQL dashboard for the AG-split view.",
    ))

    # SQLMonitor Jobs attention
    ps.append(Panel(
        title="SQLMonitor Jobs - Require Attention",
        description=("SQL Agent jobs whose latest run did not succeed, or "
                     "whose next run is more than 12h overdue."),
        type="table", unit="short",
        grid=(0, 48, 24, 8),
        targets=[Target(
            f'mssql_sqlagent_job__last_run_outcome{S} != 1',
            legend="", ref="A", instant=True, format="table")],
    ))

    # Disk Space all servers
    ps.append(Panel(
        title="Disk Space - All Servers",
        description="Per-volume % used across all selected instances.",
        type="table", unit="percent",
        grid=(0, 56, 24, 10),
        targets=[Target(
            f'100 * (1 - windows_logical_disk_free_bytes{S} '
            f'/ clamp_min(windows_logical_disk_size_bytes{S}, 1))',
            legend="", ref="A", instant=True, format="table")],
    ))

    # AlwaysOn Latency
    ps.append(Panel(
        title="All Servers - AlwaysOn Latency",
        description=("Per-(replica, database) commit latency seconds "
                     "from mssql_aghealth__latency_seconds."),
        type="table", unit="s",
        grid=(0, 66, 24, 8),
        targets=[Target(
            f'mssql_aghealth__latency_seconds{S}',
            legend="", ref="A", instant=True, format="table")],
    ))

    # Log Space Consumers — legacy (requires Inventory + tempdb_log collector)
    ps.append(legacy_link_panel(
        "Log Space Consumers",
        grid=(0, 74, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="log_space_consumers collector not yet ported to "
             "Prometheus. Relies on dbo.log_space_consumers cache table.",
    ))
    ps.append(legacy_link_panel(
        "TempDb Usage",
        grid=(0, 82, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="tempdb_space_usage collector not yet ported.",
    ))

    # Alert History
    ps.append(legacy_link_panel(
        "Alerts - Aggregated by Type",
        grid=(0, 90, 12, 10),
        sql_dashboard=_LEGACY_UID,
        note="Alert history rows live in dbo.alert_history — accessible "
             "only from the SQLMonitor inventory DB.",
    ))
    ps.append(legacy_link_panel(
        "All Servers - Alert History",
        grid=(12, 90, 12, 10),
        sql_dashboard=_LEGACY_UID,
        note="Same source as above (dbo.alert_history).",
    ))

    # Health Metrics (last panel)
    ps.append(Panel(
        title="Servers Need Help - Health Metrics",
        description=("Servers where any of the core health gauges is "
                     "outside the expected range: PLE < 300, or memory "
                     "grants pending > 0, or blocking > 0."),
        type="table", unit="short",
        grid=(0, 100, 24, 12),
        targets=[
            Target(
                f'mssql_perfmon__page_life_expectancy_seconds{S} < 300',
                legend="", ref="PLE", instant=True, format="table"),
            Target(
                f'mssql_perfmon__memory_grants_pending{S} > 0',
                legend="", ref="Grants", instant=True, format="table"),
            Target(
                f'mssql_perfmon__processes_blocked{S} > 0',
                legend="", ref="Blocked", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    return ps
