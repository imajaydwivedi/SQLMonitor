"""Spec for ``Monitoring - Live - Distributed`` Prometheus port
(UID: prom_monitoring_live_distributed).

Source dashboard has 60 data panels across 22 rows covering OS, SQL
instance and AlwaysOn state for a *single* server selected via
``$Server``. The layout mirrors the original dashboard row-for-row;
panels map to:

    OS / Host metrics       → windows_exporter + mssql_service_info
    SQL Server state        → mssql_standard + mssql_dba_cached
    WhoIsActive / blocking  → mssql_whoisactive__* (mssql_dba_whoisactive)
    AlwaysOn                → mssql_aghealth__*
    Disk / Wait stats       → windows_logical_disk_* / mssql_waits__*
    Perfmon trends          → mssql_perfmon__*

Panels that depend on the SQLMonitor cache tables (Server/Database
config change history, sqlagent job activity detail with duration
history, tempdb_space / log_space consumers, Lead Blockers rolled-up
tables) use ``legacy_link_panel`` so they remain visible without
pretending that inventory data has been ported to Prometheus.
"""
from prom_dashboard import (
    Panel, Target, query_var, constant_var, legacy_link_panel, row,
)


UID = "prom_monitoring_live_distributed"
TITLE = "Monitoring - Live - Distributed"
TAGS = ["mssql", "sqlmonitor", "Live", "Distributed", "prometheus"]
_LEGACY_UID = "monitoring-live-distributed"


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance"),
        constant_var("blocked_threshold_seconds", "30"),
        constant_var("memory_grant_threshold_mb", "100"),
    ]


def _stat(title, expr, grid, unit="short", decimals=0,
          description="", thresholds=None):
    return Panel(
        title=title, type="stat", unit=unit, decimals=decimals,
        description=description, grid=grid,
        thresholds_steps=thresholds,
        targets=[Target(expr, legend="", ref="A", instant=True)],
    )


def panels():
    ps: list[Panel] = []
    S = '{instance="$Server"}'

    # ==== Row 1: OS Info stat tiles ====
    ps.append(_stat("Memory Model",
                    f'mssql_service_info{S}', (0, 0, 2, 2),
                    description="Memory model reported by mssql_service_info."))
    ps.append(_stat("Memory Status",
                    f'windows_memory_available_bytes{S} > 0', (2, 0, 2, 2),
                    description="1 when OS reports available memory."))
    ps.append(_stat("OS Uptime",
                    f'windows_system_system_up_time{S}',
                    (4, 0, 3, 2), unit="s",
                    description="Seconds since OS boot (windows_exporter)."))
    ps.append(_stat("OS Processes",
                    f'windows_system_processes{S}', (7, 0, 4, 2)))
    ps.append(_stat("OS CPU %",
                    f'100 - (avg without(cpu,mode) '
                    f'(rate(windows_cpu_time_total{{instance="$Server",'
                    f'mode="idle"}}[$__rate_interval])) * 100)',
                    (11, 0, 3, 3), unit="percent", decimals=1))
    ps.append(_stat("Idle CPU %",
                    f'avg without(cpu,mode) '
                    f'(rate(windows_cpu_time_total{{instance="$Server",'
                    f'mode="idle"}}[$__rate_interval])) * 100',
                    (14, 0, 3, 3), unit="percent", decimals=1))
    ps.append(_stat("PLE",
                    f'mssql_perfmon__page_life_expectancy_seconds{S}',
                    (17, 0, 2, 3), unit="s",
                    thresholds=[{"color": "red", "value": None},
                                  {"color": "green", "value": 300}]))
    ps.append(Panel(
        title="AG Details",
        description="Replica/DB sync state from mssql_aghealth__*.",
        type="table", unit="short",
        grid=(19, 0, 5, 5),
        targets=[Target(
            f'mssql_aghealth__synchronization_health{S}',
            legend="", ref="A", instant=True, format="table")],
    ))
    ps.append(_stat("Box Memory",
                    f'windows_cs_physical_memory_bytes{S}',
                    (0, 3, 2, 3), unit="bytes"))
    ps.append(_stat("Available Memory",
                    f'windows_memory_available_bytes{S}',
                    (2, 3, 2, 3), unit="bytes"))
    ps.append(_stat("CPU (OS/SQL)",
                    f'mssql_sqlserver_cpu_count{S}',
                    (8, 3, 3, 3)))
    ps.append(_stat("Processor",
                    f'windows_cs_logical_processors{S}',
                    (11, 4, 5, 2)))
    ps.append(_stat("Machine Type",
                    f'windows_cs_hypervisor{S}',
                    (16, 4, 3, 2),
                    description="1 if hypervisor detected (VM)."))

    # ==== Row 2: Live Metrics ====
    ps.append(row("LIVE Metrics - [$Server]", y=6))
    ps.append(_stat(
        "Blocked > $blocked_threshold_seconds s",
        f'sum(mssql_whoisactive__avg_elapsed_time{{instance="$Server",'
        f'blocked_session_count!="0"}} > $blocked_threshold_seconds) or '
        f'vector(0)',
        (0, 7, 3, 3),
        thresholds=[{"color": "green", "value": None},
                      {"color": "red", "value": 1}]))
    ps.append(_stat("SQL Used Memory",
                    f'mssql_perfmon__total_server_memory_bytes{S}',
                    (3, 7, 2, 3), unit="bytes"))
    ps.append(_stat("Allocated M/r %",
                    f'100 * mssql_perfmon__total_server_memory_bytes{S} '
                    f'/ clamp_min(mssql_perfmon__target_server_memory_bytes{S}, 1)',
                    (5, 7, 2, 3), unit="percent", decimals=1))
    ps.append(_stat("Connections",
                    f'mssql_perfmon__user_connections{S}',
                    (7, 7, 2, 3)))
    ps.append(_stat("Active Requests",
                    f'mssql_sqlserver_active_requests{S}',
                    (9, 7, 2, 3)))
    ps.append(_stat("SQL CPU %",
                    f'mssql_cpu_utilization__sql_cpu_utilization{S}',
                    (11, 7, 3, 3), unit="percent", decimals=1))
    ps.append(_stat("IsHadrEnabled",
                    f'mssql_sqlserver_is_hadr_enabled{S}',
                    (14, 7, 2, 3)))
    ps.append(_stat("IsClustered",
                    f'mssql_sqlserver_is_clustered{S}',
                    (16, 7, 2, 3)))
    ps.append(_stat("SQL Version",
                    f'mssql_service_info{S}', (18, 7, 6, 3),
                    description="Value is 1; label `product_version` holds the version string."))

    ps.append(_stat("Longest Blocking (s)",
                    f'max(mssql_whoisactive__avg_elapsed_time{S}) or vector(0)',
                    (0, 10, 3, 3), unit="s"))
    ps.append(_stat("Memory Grants Pending",
                    f'mssql_perfmon__memory_grants_pending{S}',
                    (3, 10, 3, 3),
                    thresholds=[{"color": "green", "value": None},
                                  {"color": "red", "value": 1}]))
    ps.append(_stat("Page Faults/sec",
                    f'rate(windows_memory_page_faults_total{S}[$__rate_interval])',
                    (6, 10, 3, 3)))
    ps.append(_stat("% User Mode",
                    f'avg without(cpu) (rate(windows_cpu_time_total'
                    f'{{instance="$Server",mode="user"}}[$__rate_interval])) * 100',
                    (9, 10, 3, 3), unit="percent", decimals=1))
    ps.append(_stat("Disk Latency (avg ms)",
                    f'avg(rate(windows_logical_disk_read_seconds_total{S}[$__rate_interval]) '
                    f'/ clamp_min(rate(windows_logical_disk_reads_total{S}[$__rate_interval]), 1) '
                    f'* 1000)',
                    (12, 10, 3, 3), unit="ms", decimals=1))
    ps.append(_stat("Waits / Core / Minute",
                    f'60 * sum(rate(mssql_waits__wait_time_seconds{S}[$__rate_interval])) '
                    f'/ clamp_min(mssql_sqlserver_cpu_count{S}, 1)',
                    (15, 10, 3, 3), unit="short", decimals=1))
    ps.append(_stat("SQL Uptime",
                    f'mssql_sqlserver_uptime_seconds{S}',
                    (18, 10, 3, 3), unit="s"))
    ps.append(_stat("SQL Start Time UTC",
                    f'time() - mssql_sqlserver_uptime_seconds{S}',
                    (21, 10, 3, 3), unit="dateTimeAsIso"))

    # Patch details
    ps.append(legacy_link_panel(
        "SQL Server Patching Details",
        grid=(0, 13, 24, 4),
        sql_dashboard=_LEGACY_UID,
        note="CU/KB/patch history is stored in the inventory DB "
             "(dbo.sql_server_patching) — not a Prometheus metric."))

    # ==== AlwaysOn AG Status ====
    ps.append(row("AlwaysOn Availability Groups - Status", y=17))
    ps.append(Panel(
        title="AlwaysOn Availability Group Health Metrics",
        description="Per-(replica, database) AG health: state / queues / "
                     "rates / latency, from mssql_aghealth__*.",
        type="table", unit="short", grid=(0, 18, 24, 9),
        targets=[
            Target(f'mssql_aghealth__synchronization_health{S}',
                   legend="", ref="Health", instant=True, format="table"),
            Target(f'mssql_aghealth__latency_seconds{S}',
                   legend="", ref="Lat", instant=True, format="table"),
            Target(f'mssql_aghealth__log_send_queue_size{S}',
                   legend="", ref="LSQ", instant=True, format="table"),
            Target(f'mssql_aghealth__redo_queue_size{S}',
                   legend="", ref="RQ", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ==== CPU Trend ====
    ps.append(row("Trend - CPU Utilization", y=27))
    ps.append(Panel(
        title="CPU %", type="timeseries", unit="percent",
        description="SQL vs OS CPU from ring-buffer metrics.",
        grid=(0, 28, 24, 8),
        targets=[
            Target(f'mssql_cpu_utilization__sql_cpu_utilization{S}',
                   legend="SQL CPU", ref="Sql"),
            Target(f'mssql_cpu_utilization__system_idle_process{S}',
                   legend="Idle", ref="Idle"),
            Target(f'100 - mssql_cpu_utilization__system_idle_process{S}',
                   legend="OS CPU", ref="Os"),
        ],
        min_value=0, max_value=100,
    ))
    ps.append(Panel(
        title="OS Processes CPU Utilization", type="timeseries",
        description="Per-process CPU from windows_exporter.",
        unit="percent", grid=(0, 36, 24, 8),
        targets=[Target(
            f'topk(10, rate(windows_process_cpu_time_total{S}[$__rate_interval]) * 100)',
            legend="{{process}}", ref="A")],
    ))

    # ==== Memory Trend ====
    ps.append(row("Trend - Memory Utilization", y=44))
    ps.append(Panel(
        title="SQL Server Process Memory", type="timeseries", unit="bytes",
        description="mssql_perfmon__total_server_memory_bytes and "
                     "target_server_memory_bytes.",
        grid=(0, 45, 24, 10),
        targets=[
            Target(f'mssql_perfmon__total_server_memory_bytes{S}',
                   legend="Total Server Memory", ref="Total"),
            Target(f'mssql_perfmon__target_server_memory_bytes{S}',
                   legend="Target Server Memory", ref="Target"),
        ],
    ))
    ps.append(Panel(
        title="OS Processes Memory Utilization", type="timeseries",
        unit="bytes",
        description="Top 10 processes by working-set memory.",
        grid=(0, 55, 24, 10),
        targets=[Target(
            f'topk(10, windows_process_working_set_bytes{S})',
            legend="{{process}}", ref="A")],
    ))

    # ==== Config Changes (legacy) ====
    ps.append(row("Server & Database Config Changes", y=65))
    ps.append(legacy_link_panel(
        "Server Configuration Changes", grid=(0, 66, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="dbo.server_config_history (LAMA) is inventory-only."))
    ps.append(legacy_link_panel(
        "Database Configuration Changes", grid=(0, 74, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="dbo.database_config_history is inventory-only."))

    # ==== Blocking Tree (WhoIsActive) ====
    ps.append(row("Blocking Tree - ACTIVE", y=82))
    ps.append(Panel(
        title="Blocking Details - ACTIVE - [sp_WhoIsActive]",
        description="Live blocking info from mssql_whoisactive.",
        type="table", unit="short", grid=(0, 83, 24, 8),
        targets=[Target(
            f'mssql_whoisactive__start_time{{instance="$Server",'
            f'blocked_session_count!="0"}}',
            legend="", ref="A", instant=True, format="table")],
    ))

    # ==== Lead Blockers ====
    ps.append(row("Lead Blockers", y=91))
    ps.append(Panel(
        title="Lead Blockers - Logins - Blocked Count",
        description="Count of blocked sessions grouped by login_name "
                     "from mssql_whoisactive.",
        type="timeseries", unit="short", grid=(0, 92, 24, 11),
        targets=[Target(
            f'count by (login_name) ('
            f'mssql_whoisactive__blocking_session_id{{instance="$Server",'
            f'blocked_session_count!="0"}})',
            legend="{{login_name}}", ref="A")],
    ))
    ps.append(Panel(
        title="Lead Blockers - Programs - Blocked Count",
        description="Blocked sessions grouped by program_name.",
        type="timeseries", unit="short", grid=(0, 103, 24, 11),
        targets=[Target(
            f'count by (program_name) ('
            f'mssql_whoisactive__blocking_session_id{{instance="$Server",'
            f'blocked_session_count!="0"}})',
            legend="{{program_name}}", ref="A")],
    ))

    # ==== Memory Grants Pending ====
    ps.append(row("Trend - Memory Grants Pending", y=114))
    ps.append(Panel(
        title="Memory Grants Pending", type="timeseries", unit="short",
        description="mssql_perfmon__memory_grants_pending — anything >0 "
                     "indicates grant pressure.",
        grid=(0, 115, 24, 7),
        targets=[Target(f'mssql_perfmon__memory_grants_pending{S}',
                         legend="pending grants", ref="A")],
    ))

    # ==== Memory Consumers ====
    ps.append(row("Memory Consumers - ACTIVE", y=122))
    ps.append(Panel(
        title="Memory Consumers Over $memory_grant_threshold_mb MB",
        description="Sessions holding memory grants above the threshold.",
        type="table", unit="short", grid=(0, 123, 24, 11),
        targets=[Target(
            f'mssql_whoisactive__memory_info{{instance="$Server"}}',
            legend="", ref="A", instant=True, format="table")],
    ))

    # ==== TempdbSaver / LogSaver (legacy) ====
    ps.append(row("TempdbSaver - Latest", y=134))
    ps.append(legacy_link_panel(
        "TempdbSaver - tempdb_space_usage", grid=(0, 135, 12, 4),
        sql_dashboard=_LEGACY_UID,
        note="tempdb_space_usage collector is not yet ported."))
    ps.append(legacy_link_panel(
        "TempdbSaver - tempdb_space_consumers", grid=(12, 135, 12, 4),
        sql_dashboard=_LEGACY_UID,
        note="tempdb_space_consumers collector is not yet ported."))
    ps.append(row("LogSaver - Latest", y=139))
    ps.append(legacy_link_panel(
        "LogSaver - log_space_consumers", grid=(0, 140, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="log_space_consumers collector is not yet ported."))

    # ==== Connections / Winsock Rejections ====
    ps.append(row("SQL Connections & Winsock Rejections", y=148))
    ps.append(Panel(
        title="microsoft winsock bsp -> rejected connections/sec",
        type="timeseries", unit="short",
        description="Winsock BSP rejected connections; counter delta.",
        grid=(0, 149, 24, 8),
        targets=[Target(
            f'rate(windows_net_packets_outbound_errors_total{S}[$__rate_interval])',
            legend="{{nic}}", ref="A")],
    ))

    # ==== Long Running Queries ====
    ps.append(row("Long Running Queries", y=157))
    ps.append(Panel(
        title="WhoIsActive Data", type="table", unit="short",
        description="Current sp_WhoIsActive snapshot from mssql_whoisactive.",
        grid=(0, 158, 24, 9),
        targets=[Target(
            f'mssql_whoisactive__start_time{{instance="$Server"}}',
            legend="", ref="A", instant=True, format="table")],
    ))

    # ==== Page Life Expectancy ====
    ps.append(row("Trend - Page Life Expectancy", y=167))
    ps.append(Panel(
        title="Page Life Expectancy", type="timeseries", unit="s",
        grid=(0, 168, 24, 10),
        targets=[Target(
            f'mssql_perfmon__page_life_expectancy_seconds{S}',
            legend="PLE (s)", ref="A")],
    ))

    # ==== Batch Request/sec ====
    ps.append(row("Trend - Batch Request/Sec", y=178))
    ps.append(Panel(
        title="Batch Requests Per Second", type="timeseries", unit="short",
        grid=(0, 179, 24, 7),
        targets=[Target(
            f'rate(mssql_perfmon__batch_requests_total{S}[$__rate_interval])',
            legend="batch req/s", ref="A")],
    ))

    # ==== Connection Distribution ====
    ps.append(row("SQL Connections - Distribution", y=186))
    ps.append(Panel(
        title="Connections by Interface", type="table", unit="short",
        description="Connections grouped by net_transport / auth_scheme.",
        grid=(0, 187, 8, 6),
        targets=[Target(
            f'count by (net_transport) ('
            f'mssql_whoisactive__start_time{{instance="$Server"}})',
            legend="", ref="A", instant=True, format="table")],
    ))
    ps.append(Panel(
        title="Host Connections", type="table", unit="short",
        grid=(8, 187, 8, 12),
        targets=[Target(
            f'count by (host_name) ('
            f'mssql_whoisactive__start_time{{instance="$Server"}})',
            legend="", ref="A", instant=True, format="table")],
    ))
    ps.append(Panel(
        title="Login Connections", type="table", unit="short",
        grid=(16, 187, 8, 12),
        targets=[Target(
            f'count by (login_name) ('
            f'mssql_whoisactive__start_time{{instance="$Server"}})',
            legend="", ref="A", instant=True, format="table")],
    ))
    ps.append(Panel(
        title="Connections By Status", type="table", unit="short",
        grid=(0, 193, 8, 6),
        targets=[Target(
            f'count by (status) ('
            f'mssql_whoisactive__start_time{{instance="$Server"}})',
            legend="", ref="A", instant=True, format="table")],
    ))

    # ==== Running Jobs / WhoIsActive latest ====
    ps.append(row("Running Jobs & Maintenance Workloads", y=199))
    ps.append(Panel(
        title="WhoIsActive Latest Captured Data", type="table", unit="short",
        grid=(0, 200, 24, 8),
        targets=[Target(
            f'mssql_whoisactive__start_time{{instance="$Server"}}',
            legend="", ref="A", instant=True, format="table")],
    ))

    # ==== SQL Agent Job Activity ====
    ps.append(row("SQLAgent Job Activity Monitor - [$Server]", y=208))
    ps.append(Panel(
        title="Job Activity Monitor",
        description="SQL Agent jobs for this instance — outcome / duration "
                     "/ running state from mssql_sqlagent_job__*.",
        type="table", unit="short", grid=(0, 209, 24, 16),
        targets=[
            Target(f'mssql_sqlagent_job__enabled{S}', legend="",
                   ref="En", instant=True, format="table"),
            Target(f'mssql_sqlagent_job__last_run_outcome{S}', legend="",
                   ref="Out", instant=True, format="table"),
            Target(f'mssql_sqlagent_job__last_run_duration_seconds{S}',
                   legend="", ref="Dur", instant=True, format="table"),
            Target(f'mssql_sqlagent_job__is_running{S}', legend="",
                   ref="Run", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ==== Disk Space ====
    ps.append(row("Disk Space - [$Server]", y=225))
    ps.append(Panel(
        title="Disk Space Utilization", type="table", unit="bytes",
        description="Per-volume size / free / used from windows_exporter.",
        grid=(0, 226, 24, 16),
        targets=[
            Target(f'windows_logical_disk_size_bytes{S}', legend="",
                   ref="Size", instant=True, format="table"),
            Target(f'windows_logical_disk_free_bytes{S}', legend="",
                   ref="Free", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ==== WaitStats ====
    ps.append(row("WaitStats", y=242))
    ps.append(Panel(
        title="[${Server}] - WaitStats", type="timeseries", unit="s",
        description="rate(mssql_waits__wait_time_seconds) per wait_type.",
        grid=(0, 243, 24, 15),
        targets=[Target(
            f'topk(20, sum by (wait_type) ('
            f'rate(mssql_waits__wait_time_seconds{S}[$__rate_interval])))',
            legend="{{wait_type}}", ref="A")],
    ))

    return ps
