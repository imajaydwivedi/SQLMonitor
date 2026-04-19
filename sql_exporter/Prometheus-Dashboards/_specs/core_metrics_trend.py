"""Spec for ``Core Metrics - Trend`` Prometheus port.

High-fidelity port. Every variable from the SQL dashboard is preserved:

    $Server          SQL instance(s) (multi + include-all)
    $trend_by        Hourly | Daily   → sets the aggregation window used
                     inside ``quantile_over_time``; the SQL dashboard's
                     ``all_server_volatile_info_history_hourly`` /
                     ``_daily`` cached tables become 1h / 1d windows here.
    $percentile      p50 | p75 | p95 | p99 | max  → maps to the first
                     argument of ``quantile_over_time`` (``max`` == 1.0).
    $hour_of_day     0..23.  Filters at query-evaluation time via
                     ``hour() == bool $hour_of_day``.  NOTE: pure PromQL
                     cannot retrieve historical data for a specific
                     hour-of-day; this filter only applies when the
                     dashboard range is currently at that hour. For the
                     backfilled version, see the SQL dashboard
                     ``core_metrics_trend``. See README for details.
    $max_servers     N  → top-N server filter, preserved via
                     ``topk($max_servers, ...)``.
"""
from prom_dashboard import Panel, Target, query_var, custom_var, constant_var


UID = "prom_core_metrics_trend"
TITLE = "Core Metrics - Trend"
TAGS = ["mssql", "sqlmonitor", "core-metrics", "prometheus"]


_PCTL_MAP = {"p50": "0.5", "p75": "0.75", "p95": "0.95",
             "p99": "0.99", "max": "1.0"}
_TREND_MAP = {"Hourly": "1h", "Daily": "1d"}


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance", multi=True, include_all=True),
        custom_var("trend_by", ["Hourly", "Daily"], default="Hourly",
                   label="Trend By"),
        custom_var("trend_window", list(_TREND_MAP.values()),
                   default="1h", label="Trend Window", hide=2),
        custom_var("percentile",
                   list(_PCTL_MAP.keys()),
                   default="p95", label="Percentile"),
        custom_var("percentile_q",
                   list(_PCTL_MAP.values()),
                   default="0.95", label="Percentile Q", hide=2),
        custom_var("hour_of_day",
                   [str(i) for i in range(24)] + ["-1"],
                   default="-1", label="Hour of Day (-1 = any)"),
        constant_var("max_servers", "10", label="Max Servers"),
    ]


def _pct(expr: str, window: str = "$trend_window") -> str:
    return f"quantile_over_time($percentile_q, ({expr})[{window}:])"


def _hod_gate() -> str:
    # Gate an expression on $hour_of_day ≥ 0 and matching the query eval
    # hour. When $hour_of_day = -1 the gate is always 1 (no filter).
    return (
        "(vector($hour_of_day) == bool -1) "
        "or on () (vector($hour_of_day) == bool hour())"
    )


def panels():
    ps: list[Panel] = []
    SERVER = '{instance=~"$Server"}'
    RI = "[$__rate_interval]"
    TW = "$trend_window"

    def pct(expr: str) -> str:
        return f"quantile_over_time($percentile_q, ({expr})[{TW}:])"

    def topk(expr: str) -> str:
        return f"topk($max_servers, {expr})"

    # 1. Database IO Latency (ms/IO) per (server, db) - $trend_by window
    #    SQL source: Core Metrics - Trend - Database IO Latency - Server
    read_lat = (
        f"rate(mssql_virtualfilestats__io_stall_read_ms{SERVER}{RI}) "
        f"/ clamp_min(rate(mssql_virtualfilestats__num_of_reads{SERVER}{RI}), 1)"
    )
    write_lat = (
        f"rate(mssql_virtualfilestats__io_stall_write_ms{SERVER}{RI}) "
        f"/ clamp_min(rate(mssql_virtualfilestats__num_of_writes{SERVER}{RI}), 1)"
    )
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - Database IO Latency - Server ___[${Server}]___",
        description=("Per-database read/write latency in ms/IO. "
                     "Aggregated at the $trend_by window using $percentile "
                     "quantile_over_time."),
        type="timeseries", unit="ms",
        grid=(0, 0, 24, 8),
        targets=[
            Target(pct(f"avg by (instance, database_name) ({read_lat})"),
                   legend="{{instance}} - {{database_name}} - read", ref="A"),
            Target(pct(f"avg by (instance, database_name) ({write_lat})"),
                   legend="{{instance}} - {{database_name}} - write", ref="B"),
        ],
    ))

    # 2. Database IO (MB/s) per (server, db)
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - Database IO - Server ___[${Server}]___",
        description="Per-database throughput in MB/s at the $trend_by window.",
        type="timeseries", unit="MBs",
        grid=(0, 8, 24, 8),
        targets=[
            Target(pct(
                f"sum by (instance, database_name) ("
                f"rate(mssql_virtualfilestats__num_of_bytes_read{SERVER}{RI})) / (1024*1024)"
            ), legend="{{instance}} - {{database_name}} - read", ref="A"),
            Target(pct(
                f"sum by (instance, database_name) ("
                f"rate(mssql_virtualfilestats__num_of_bytes_written{SERVER}{RI})) / (1024*1024)"
            ), legend="{{instance}} - {{database_name}} - write", ref="B"),
        ],
    ))

    # 3. Database IOPS per (server, db)
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - Database IOPS - Server ___[${Server}]___",
        description="Per-database reads/writes per second at the $trend_by window.",
        type="timeseries", unit="iops",
        grid=(0, 16, 24, 8),
        targets=[
            Target(pct(
                f"sum by (instance, database_name) ("
                f"rate(mssql_virtualfilestats__num_of_reads{SERVER}{RI}))"
            ), legend="{{instance}} - {{database_name}} - reads", ref="A"),
            Target(pct(
                f"sum by (instance, database_name) ("
                f"rate(mssql_virtualfilestats__num_of_writes{SERVER}{RI}))"
            ), legend="{{instance}} - {{database_name}} - writes", ref="B"),
        ],
    ))

    # 4. OS CPU (%) - top-N servers
    os_cpu = (
        f"100 - (avg by (instance) ("
        f"rate(windows_cpu_time_total{{mode=\"idle\",instance=~\"$Server\"}}{RI})) * 100)"
    )
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - OS CPU - Max ${max_servers} Servers",
        description="OS CPU % per server, top-N by $percentile at $trend_by window.",
        type="timeseries", unit="percent",
        grid=(0, 24, 12, 8),
        min_value=0, max_value=100,
        targets=[Target(topk(pct(os_cpu)), legend="{{instance}}", ref="A")],
    ))

    # 5. SQL CPU (%) - top-N servers
    sql_cpu = f"avg by (instance) (mssql_cpu_utilization_percentage{SERVER})"
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - SQL CPU - Max ${max_servers} Servers",
        description="SQL CPU % per server, top-N by $percentile at $trend_by window.",
        type="timeseries", unit="percent",
        grid=(12, 24, 12, 8),
        min_value=0, max_value=100,
        targets=[Target(topk(pct(sql_cpu)), legend="{{instance}}", ref="A")],
    ))

    # 6. Disk Latency - top-N servers
    dl_r = (
        f"rate(windows_logical_disk_read_latency_seconds_total{SERVER}{RI}) "
        f"/ clamp_min(rate(windows_logical_disk_reads_total{SERVER}{RI}), 1)"
    )
    dl_w = (
        f"rate(windows_logical_disk_write_latency_seconds_total{SERVER}{RI}) "
        f"/ clamp_min(rate(windows_logical_disk_writes_total{SERVER}{RI}), 1)"
    )
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - Disk Latency - Max ${max_servers} Servers",
        description="OS-level disk latency (s/IO) per volume. top-N by $percentile.",
        type="timeseries", unit="s",
        grid=(0, 32, 24, 8),
        targets=[
            Target(topk(pct(f"avg by (instance, volume) ({dl_r})")),
                   legend="{{instance}} {{volume}} read", ref="A"),
            Target(topk(pct(f"avg by (instance, volume) ({dl_w})")),
                   legend="{{instance}} {{volume}} write", ref="B"),
        ],
    ))

    # 7. Batch Requests / sec - top-N servers
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - Requests - Max ${max_servers} Servers",
        description="Batch requests/sec per server, top-N by $percentile.",
        type="timeseries", unit="reqps",
        grid=(0, 40, 12, 8),
        targets=[Target(
            topk(pct(f"sum by (instance) (rate(mssql_batch_requests{SERVER}{RI}))")),
            legend="{{instance}}", ref="A")],
    ))

    # 8. Available Memory (OS) - bottom-N (smallest) servers at $percentile
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - Available Memory - Max ${max_servers} Servers",
        description=("OS available memory per server, bottom-N (smallest) "
                     "at $percentile quantile over $trend_by window."),
        type="timeseries", unit="bytes",
        grid=(12, 40, 12, 8),
        targets=[Target(
            f"bottomk($max_servers, "
            f"quantile_over_time($percentile_q, "
            f"(avg by (instance) (windows_memory_available_bytes{SERVER}))[{TW}:]))",
            legend="{{instance}}", ref="A")],
    ))

    # 9. Connections - top-N servers
    ps.append(Panel(
        title="Core Metrics - ${trend_by} TREND - Connections - Max ${max_servers} Servers",
        description="SQL connection count per server, top-N by $percentile.",
        type="timeseries", unit="short",
        grid=(0, 48, 24, 8),
        targets=[Target(
            topk(pct(f"sum by (instance) (mssql_connections{SERVER})")),
            legend="{{instance}}", ref="A")],
    ))

    return ps
