"""Spec for ``Monitoring - Perfmon Counters - Quest Softwares - Distributed``
Prometheus port (UID: prom_monitoring_perfmon_quest).

The source dashboard is a 53-timeseries perfmon catalogue for a single
server. Every panel maps to either ``mssql_perfmon__*`` (from
mssql_standard / mssql_dba_cached) or ``windows_*`` (from
windows_exporter). Rows that rely on the SQLMonitor dbo.os_task_list
cache table or dbo.memory_clerks snapshot are rendered as
``legacy_link_panel`` so every source row is accounted for.
"""
from prom_dashboard import (
    Panel, Target, query_var, legacy_link_panel, row,
)


UID = "prom_monitoring_perfmon_quest"
TITLE = "Monitoring - Perfmon Counters - Quest Softwares - Distributed"
TAGS = ["mssql", "sqlmonitor", "Perfmon", "Quest", "prometheus"]
_LEGACY_UID = "monitoring-perfmon-counters-quest-softwares-distributed"


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance"),
        query_var("database",
                  'label_values(mssql_perfmon__log_bytes_flushed_total{instance="$Server"}, database_name)',
                  label="Database", multi=True, include_all=True),
        query_var("disk_drive",
                  'label_values(windows_logical_disk_size_bytes{instance="$Server"}, volume)',
                  label="Disk", multi=True, include_all=True),
    ]


def _ts(title, exprs_legend, grid, unit="short", description=""):
    return Panel(
        title=title, type="timeseries", unit=unit,
        description=description, grid=grid,
        targets=[Target(e, legend=l, ref=chr(65 + i))
                   for i, (e, l) in enumerate(exprs_legend)],
    )


def panels():
    ps: list[Panel] = []
    S = '{instance="$Server"}'
    Sd = '{instance="$Server",database_name=~"$database"}'
    Svol = '{instance="$Server",volume=~"$disk_drive"}'
    rate = "$__rate_interval"

    y = 0
    # 1. CPU & Processor
    ps.append(row("CPU & Processor", y)); y += 1
    ps.append(_ts("%Processor Time (SQL Server)",
                  [(f'mssql_cpu_utilization__sql_cpu_utilization{S}',
                    'SQL CPU'),
                   (f'100 - mssql_cpu_utilization__system_idle_process{S}',
                    'OS CPU')],
                  (0, y, 24, 7), unit="percent",
                  description="SQL vs OS CPU %.")); y += 7
    ps.append(_ts("System: Processor Queue Length",
                  [(f'windows_system_processor_queue_length{S}',
                    'queue length')],
                  (0, y, 24, 5))); y += 5

    # 2. OS Memory & Paging
    ps.append(row("OS Memory & Paging Performance Counters", y)); y += 1
    ps.append(_ts("Memory - Available Mbytes",
                  [(f'windows_memory_available_bytes{S} / 1024 / 1024',
                    'Available MB')],
                  (0, y, 24, 6), unit="decmbytes")); y += 6
    ps.append(_ts("Memory - Pages Input/sec, Pages/sec",
                  [(f'rate(windows_memory_swap_page_operations_total{S}[{rate}])',
                    'Pages/sec'),
                   (f'rate(windows_memory_swap_page_reads_total{S}[{rate}])',
                    'Pages Input/sec')],
                  (0, y, 24, 11))); y += 11
    ps.append(_ts("Paging File Usage",
                  [(f'windows_paging_file_usage_percent{S}', 'usage %')],
                  (0, y, 24, 7), unit="percent")); y += 7

    # 3. SQL Server: Memory Manager
    ps.append(row("SQL Server: Memory Manager Counters", y)); y += 1
    ps.append(_ts("SQL Server Process Memory",
                  [(f'mssql_perfmon__total_server_memory_bytes{S}',
                    'Total Server Memory'),
                   (f'mssql_perfmon__target_server_memory_bytes{S}',
                    'Target Server Memory')],
                  (0, y, 24, 11), unit="bytes")); y += 11
    ps.append(_ts("SQL Server: Memory Manager",
                  [(f'mssql_perfmon__memory_grants_pending{S}',
                    'Memory Grants Pending'),
                   (f'mssql_perfmon__memory_grants_outstanding{S}',
                    'Memory Grants Outstanding')],
                  (0, y, 24, 11))); y += 11
    ps.append(_ts("Memory Grants",
                  [(f'mssql_perfmon__memory_grants_pending{S}', 'pending'),
                   (f'mssql_perfmon__memory_grants_outstanding{S}',
                    'outstanding')],
                  (0, y, 24, 8))); y += 8

    # 4. MSSQL Data Access
    ps.append(row("MSSQL Data Access Performance Counters", y)); y += 1
    ps.append(_ts("Batch Requests/sec",
                  [(f'rate(mssql_perfmon__batch_requests_total{S}[{rate}])',
                    'Batch Req/sec')],
                  (0, y, 24, 6))); y += 6
    ps.append(_ts("SQLServer:Access Methods",
                  [(f'rate(mssql_perfmon__page_splits_total{S}[{rate}])',
                    'Page Splits/sec'),
                   (f'rate(mssql_perfmon__full_scans_total{S}[{rate}])',
                    'Full Scans/sec'),
                   (f'rate(mssql_perfmon__index_searches_total{S}[{rate}])',
                    'Index Searches/sec'),
                   (f'rate(mssql_perfmon__forwarded_records_total{S}[{rate}])',
                    'Forwarded Records/sec')],
                  (0, y, 24, 15))); y += 15
    Svol = '{instance="$Server",volume=~"$disk_drive"}'
    Sd = '{instance="$Server",database_name=~"$database"}'
    _extend_disk_network(ps, S, Sd, Svol, rate, y)
    return ps


def _extend_disk_network(ps, S, Sd, Svol, rate, y):
    # 5. Logical Disk
    ps.append(row("Logical Disk Counters", y)); y += 1
    ps.append(_ts("Logical Disk (Disk Queue Length)",
                  [(f'windows_logical_disk_avg_read_requests_queued{Svol}',
                    'read queue {{volume}}'),
                   (f'windows_logical_disk_avg_write_requests_queued{Svol}',
                    'write queue {{volume}}')],
                  (0, y, 24, 5))); y += 5
    ps.append(_ts("Logical Disk - Latency (ms)",
                  [(f'1000 * rate(windows_logical_disk_read_seconds_total{Svol}[{rate}]) '
                    f'/ clamp_min(rate(windows_logical_disk_reads_total{Svol}[{rate}]), 1)',
                    'read ms {{volume}}'),
                   (f'1000 * rate(windows_logical_disk_write_seconds_total{Svol}[{rate}]) '
                    f'/ clamp_min(rate(windows_logical_disk_writes_total{Svol}[{rate}]), 1)',
                    'write ms {{volume}}')],
                  (0, y, 24, 6), unit="ms")); y += 6
    ps.append(_ts("Logical Disk - IOPS",
                  [(f'rate(windows_logical_disk_reads_total{Svol}[{rate}])',
                    'reads/s {{volume}}'),
                   (f'rate(windows_logical_disk_writes_total{Svol}[{rate}])',
                    'writes/s {{volume}}')],
                  (0, y, 24, 8), unit="ops")); y += 8
    ps.append(_ts("Logical Disk - Throughput",
                  [(f'rate(windows_logical_disk_read_bytes_total{Svol}[{rate}])',
                    'read B/s {{volume}}'),
                   (f'rate(windows_logical_disk_write_bytes_total{Svol}[{rate}])',
                    'write B/s {{volume}}')],
                  (0, y, 24, 7), unit="Bps")); y += 7

    # 6. Physical Disk
    ps.append(row("Physical Disk Counters", y)); y += 1
    ps.append(_ts("Physical Disk (Disk Queue Length)",
                  [(f'windows_physical_disk_avg_read_requests_queued{S}',
                    'read queue {{disk}}'),
                   (f'windows_physical_disk_avg_write_requests_queued{S}',
                    'write queue {{disk}}')],
                  (0, y, 24, 5))); y += 5
    ps.append(_ts("Physical Disk - Latency (ms)",
                  [(f'1000 * rate(windows_physical_disk_read_seconds_total{S}[{rate}]) '
                    f'/ clamp_min(rate(windows_physical_disk_reads_total{S}[{rate}]), 1)',
                    'read ms {{disk}}'),
                   (f'1000 * rate(windows_physical_disk_write_seconds_total{S}[{rate}]) '
                    f'/ clamp_min(rate(windows_physical_disk_writes_total{S}[{rate}]), 1)',
                    'write ms {{disk}}')],
                  (0, y, 24, 6), unit="ms")); y += 6
    ps.append(_ts("Physical Disk - Throughput",
                  [(f'rate(windows_physical_disk_read_bytes_total{S}[{rate}])',
                    'read B/s {{disk}}'),
                   (f'rate(windows_physical_disk_write_bytes_total{S}[{rate}])',
                    'write B/s {{disk}}')],
                  (0, y, 24, 7), unit="Bps")); y += 7
    ps.append(_ts("Physical Disk - IOPS",
                  [(f'rate(windows_physical_disk_reads_total{S}[{rate}])',
                    'reads/s {{disk}}'),
                   (f'rate(windows_physical_disk_writes_total{S}[{rate}])',
                    'writes/s {{disk}}')],
                  (0, y, 24, 8), unit="ops")); y += 8

    # 7. Network
    ps.append(row("Network Interface Counters", y)); y += 1
    ps.append(_ts("Network Interface - Bytes Total/sec",
                  [(f'rate(windows_net_bytes_total{S}[{rate}])',
                    '{{nic}}')],
                  (0, y, 24, 7), unit="Bps")); y += 7

    # 8. MSSQL Databases - Size
    ps.append(row("MSSQL Databases - Size Counters", y)); y += 1
    ps.append(_ts("SQLServer:Databases - Log File Size",
                  [(f'mssql_perfmon__log_file_used_size_kb{Sd} * 1024',
                    '{{database_name}} log used (B)'),
                   (f'mssql_perfmon__log_file_size_kb{Sd} * 1024',
                    '{{database_name}} log size (B)')],
                  (0, y, 24, 15), unit="bytes")); y += 15
    ps.append(_ts("SQLServer:Databases - Data File Size",
                  [(f'mssql_perfmon__data_file_size_kb{Sd} * 1024',
                    '{{database_name}} data (B)')],
                  (0, y, 24, 12), unit="bytes")); y += 12

    _extend_sql_statistics(ps, S, Sd, rate, y)


def _extend_sql_statistics(ps, S, Sd, rate, y):
    # 9. User Database Performance
    ps.append(row("MSSQL User Database - Performance Counters", y)); y += 1
    ps.append(_ts("SqlServer:Databases - Log Bytes Flushed/sec",
                  [(f'rate(mssql_perfmon__log_bytes_flushed_total{Sd}[{rate}])',
                    '{{database_name}}')],
                  (0, y, 24, 9), unit="Bps")); y += 9
    ps.append(_ts("SqlServer:Databases - Log Flush Wait Time",
                  [(f'rate(mssql_perfmon__log_flush_wait_time_ms_total{Sd}[{rate}])',
                    '{{database_name}}')],
                  (0, y, 24, 10), unit="ms")); y += 10
    ps.append(_ts("SqlServer:Databases - Others",
                  [(f'rate(mssql_perfmon__transactions_total{Sd}[{rate}])',
                    'tx/s {{database_name}}'),
                   (f'rate(mssql_perfmon__write_transactions_total{Sd}[{rate}])',
                    'write-tx/s {{database_name}}')],
                  (0, y, 24, 15))); y += 15

    # 10. SQL Statistics — Auto Parameterization
    ps.append(row("SQL Server - SQL Statistics - Auto Parameterization", y))
    y += 1
    ps.append(_ts("SQLServer:SQL Statistics - Auto Parameterization",
                  [(f'rate(mssql_perfmon__auto_param_attempts_total{S}[{rate}])',
                    'auto-param attempts/s'),
                   (f'rate(mssql_perfmon__failed_auto_params_total{S}[{rate}])',
                    'failed auto-params/s'),
                   (f'rate(mssql_perfmon__safe_auto_params_total{S}[{rate}])',
                    'safe auto-params/s')],
                  (0, y, 24, 10))); y += 10

    # 11. Buffer Manager & Memory
    ps.append(row("MSSQL Buffer Manager & Memory Performance Counters", y))
    y += 1
    ps.append(_ts("Batch Requests/sec",
                  [(f'rate(mssql_perfmon__batch_requests_total{S}[{rate}])',
                    'batch req/s')],
                  (0, y, 24, 6))); y += 6
    ps.append(_ts("Page Life Expectancy",
                  [(f'mssql_perfmon__page_life_expectancy_seconds{S}', 'PLE')],
                  (0, y, 24, 7), unit="s")); y += 7
    ps.append(_ts("SQLServer:Buffer Manager",
                  [(f'mssql_perfmon__buffer_cache_hit_ratio{S}',
                    'buffer cache hit %'),
                   (f'rate(mssql_perfmon__page_reads_total{S}[{rate}])',
                    'page reads/s'),
                   (f'rate(mssql_perfmon__page_writes_total{S}[{rate}])',
                    'page writes/s'),
                   (f'rate(mssql_perfmon__lazy_writes_total{S}[{rate}])',
                    'lazy writes/s')],
                  (0, y, 24, 17))); y += 17

    # 12. Memory Consumers (legacy)
    ps.append(row("Memory Consumers - sys.dm_os_memory_clerks", y)); y += 1
    ps.append(legacy_link_panel(
        "Memory Consumers", grid=(0, y, 24, 13),
        sql_dashboard=_LEGACY_UID,
        note="dm_os_memory_clerks snapshot is cached in the SQLMonitor "
             "memory_clerks table and is not exposed as a Prometheus metric.",
    )); y += 13

    # 13. "How is My Memory Being Used"
    ps.append(row("MSSQL Memory Breakdown Counters", y)); y += 1
    ps.append(_ts("SQLServer:Memory Manager - Connection/Lock/Opt",
                  [(f'mssql_perfmon__connection_memory_kb{S} * 1024',
                    'connection mem (B)'),
                   (f'mssql_perfmon__lock_memory_kb{S} * 1024',
                    'lock mem (B)'),
                   (f'mssql_perfmon__optimizer_memory_kb{S} * 1024',
                    'optimizer mem (B)')],
                  (0, y, 24, 9), unit="bytes")); y += 9
    ps.append(_ts("SQLServer:Memory Manager - Granted Workspace",
                  [(f'mssql_perfmon__granted_workspace_memory_kb{S} * 1024',
                    'granted workspace (B)'),
                   (f'mssql_perfmon__reserved_server_memory_kb{S} * 1024',
                    'reserved server mem (B)')],
                  (0, y, 24, 12), unit="bytes")); y += 12

    _extend_workload(ps, S, rate, y)


def _extend_workload(ps, S, rate, y):
    # 14. Workload
    ps.append(row("MSSQL Workload Performance Counters", y)); y += 1
    ps.append(_ts("SQLServer:SQL Statistics - CPU Stuff",
                  [(f'rate(mssql_perfmon__sql_compilations_total{S}[{rate}])',
                    'compilations/s'),
                   (f'rate(mssql_perfmon__sql_re_compilations_total{S}[{rate}])',
                    're-compilations/s')],
                  (0, y, 24, 6))); y += 6
    ps.append(_ts("SQLServer:SQL Statistics - Cursors & Errors",
                  [(f'rate(mssql_perfmon__errors_total{S}[{rate}])',
                    'errors/s')],
                  (0, y, 24, 8))); y += 8
    ps.append(_ts("SQLServer:SQL Errors",
                  [(f'rate(mssql_perfmon__errors_total{S}[{rate}])',
                    'errors/s')],
                  (0, y, 24, 7))); y += 7
    ps.append(legacy_link_panel(
        "SQLServer: Deprecated Features",
        grid=(0, y, 24, 7),
        sql_dashboard=_LEGACY_UID,
        note="Deprecated-features counter not currently published by "
             "mssql_standard.")); y += 7

    # 15. Plan Cache
    ps.append(row("SQL Server : Plan Cache : Cache Manager Instance", y))
    y += 1
    ps.append(_ts("SQLServer: Plan Cache - Totals",
                  [(f'mssql_perfmon__cache_pages{S}', 'cache pages'),
                   (f'mssql_perfmon__cache_object_counts{S}',
                    'cache object counts'),
                   (f'mssql_perfmon__cache_objects_in_use{S}',
                    'cache objects in use')],
                  (0, y, 24, 5))); y += 5
    ps.append(_ts("SQLServer: Plan Cache - cache object counts",
                  [(f'mssql_perfmon__cache_object_counts{S}',
                    '{{cache_type}}')],
                  (0, y, 24, 6))); y += 6
    ps.append(_ts("SQLServer: Plan Cache - cache pages",
                  [(f'mssql_perfmon__cache_pages{S}', '{{cache_type}}')],
                  (0, y, 24, 6))); y += 6
    ps.append(_ts("SQLServer: Plan Cache - cache objects in use",
                  [(f'mssql_perfmon__cache_objects_in_use{S}',
                    '{{cache_type}}')],
                  (0, y, 24, 6))); y += 6

    # 16. Transactions
    ps.append(row("SQLServer:Transactions", y)); y += 1
    ps.append(_ts("Longest Transaction Running Time",
                  [(f'mssql_perfmon__longest_transaction_running_time_seconds{S}',
                    'longest tx (s)')],
                  (0, y, 11, 5), unit="s"))
    ps.append(_ts("Free Space in tempdb (KB)",
                  [(f'mssql_perfmon__free_space_in_tempdb_kb{S}',
                    'free tempdb (KB)')],
                  (11, y, 13, 5), unit="kbytes")); y += 5
    ps.append(_ts("Transactions",
                  [(f'mssql_perfmon__transactions{S}', 'tx')],
                  (0, y, 11, 5)))
    ps.append(_ts("Version Store Size (KB)",
                  [(f'mssql_perfmon__version_store_size_kb{S}',
                    'version store (KB)')],
                  (11, y, 13, 5), unit="kbytes")); y += 5

    # 17. General Stats
    ps.append(row("SQLServer:General Statistics", y)); y += 1
    ps.append(_ts("Winsock BSP rejected connections/sec",
                  [(f'rate(windows_net_packets_outbound_errors_total{S}[{rate}])',
                    '{{nic}}')],
                  (0, y, 24, 8))); y += 8
    ps.append(_ts("SQLServer:General Statistics - Login/Logout",
                  [(f'rate(mssql_perfmon__logins_total{S}[{rate}])',
                    'logins/s'),
                   (f'rate(mssql_perfmon__logouts_total{S}[{rate}])',
                    'logouts/s')],
                  (0, y, 24, 7))); y += 7

    # 18. Locks
    ps.append(row("MSSQL Locks Performance Counters", y)); y += 1
    ps.append(_ts("SqlServer:Locks - Lock Wait Time (ms)",
                  [(f'rate(mssql_perfmon__lock_wait_time_ms_total{S}[{rate}])',
                    '{{resource_type}}')],
                  (0, y, 24, 8), unit="ms")); y += 8
    ps.append(_ts("SqlServer:Locks - Average Wait Time (ms)",
                  [(f'mssql_perfmon__average_wait_time_ms{S}',
                    '{{resource_type}}')],
                  (0, y, 24, 8), unit="ms")); y += 8
    ps.append(_ts("SqlServer:Locks - Waits/sec",
                  [(f'rate(mssql_perfmon__lock_waits_total{S}[{rate}])',
                    '{{resource_type}}')],
                  (0, y, 24, 8))); y += 8

    # 19. Latches
    ps.append(row("MSSQL Latches Performance Counters", y)); y += 1
    ps.append(_ts("Latch Waits/sec",
                  [(f'rate(mssql_perfmon__latch_waits_total{S}[{rate}])',
                    'latch waits/s')],
                  (0, y, 24, 6))); y += 6
    ps.append(_ts("Latch Wait Time (ms)",
                  [(f'rate(mssql_perfmon__latch_wait_time_ms_total{S}[{rate}])',
                    'latch wait ms/s')],
                  (0, y, 24, 8), unit="ms")); y += 8

    # 20. Replication
    ps.append(row("SQLServer:Replication", y)); y += 1
    ps.append(_ts("Replication - Latency",
                  [(f'mssql_perfmon__replication_latency_seconds{S}',
                    '{{publication}}')],
                  (0, y, 24, 8), unit="s")); y += 8
    ps.append(_ts("Replication - Transfer Rate",
                  [(f'rate(mssql_perfmon__replication_delivered_commands_total{S}[{rate}])',
                    '{{publication}}')],
                  (0, y, 24, 8))); y += 8

    # 21. SQLAgent:Jobs
    ps.append(row("SQLAgent:Jobs", y)); y += 1
    ps.append(_ts("SQLAgent: Jobs",
                  [(f'sum by (instance) (mssql_sqlagent_job__is_running{S})',
                    'jobs running'),
                   (f'sum by (instance) (mssql_sqlagent_job__enabled{S})',
                    'jobs enabled')],
                  (0, y, 24, 5))); y += 5

    # 22/23. Mirroring / Resource Pool — no metrics published
    ps.append(row("SQLServer:Database Mirroring", y)); y += 1
    ps.append(legacy_link_panel(
        "Database Mirroring", grid=(0, y, 24, 5),
        sql_dashboard=_LEGACY_UID,
        note="Mirroring counters are not currently exposed by "
             "mssql_standard; use the SQL dashboard.")); y += 5
    ps.append(row("SQLServer:Resource Pool Stats", y)); y += 1
    ps.append(legacy_link_panel(
        "Resource Pool Stats", grid=(0, y, 24, 5),
        sql_dashboard=_LEGACY_UID,
        note="Resource Governor pool counters are not currently exposed "
             "by mssql_standard."))
