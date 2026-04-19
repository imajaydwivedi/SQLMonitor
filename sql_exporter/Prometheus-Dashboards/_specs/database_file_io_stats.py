"""Spec for ``Database File IO Stats`` Prometheus port
(UID: prom_database_file_io_stats).

SQL source dashboard has 16 data panels grouped into nine rows:

    File IO Stats    - Since Startup  (table)
    File IO Stats    - Selective      (2 tables: @from, @range)
    File IO Stats    - Reads/Writes histogram - Data (timeseries)
    File IO Stats    - Reads/Writes histogram - Counts (timeseries)
    Database IO Stats - Trend         (timeseries)
    Database IO Stats - Since Startup (table)
    Database IO Stats - Selective     (2 tables)
    Database IO Stats - Comparison    (2 tables, with prior day)
    Disk IO Stats    - Since Startup  (table)
    Disk IO Stats    - Selective      (2 tables)
    Disk IO Stats    - Comparison     (2 tables)

Metric source:
    mssql_virtualfilestats__{num_of_reads,num_of_writes,
                              num_of_bytes_read,num_of_bytes_written,
                              io_stall_read_ms,io_stall_write_ms}
    are counter-style gauges published by mssql_dba_cached on every scrape.

PromQL equivalents:
    since-startup tables      → the raw counter (instant, last-over-range).
    selective / range tables  → increase(metric[$__range]).
    comparison "prior day"    → the same increase() but anchored with
                                 @ end() offset $__range so the window is
                                 shifted back one dashboard-range.
    trend timeseries          → rate(metric[$__rate_interval]).
"""
from prom_dashboard import Panel, Target, query_var, constant_var


UID = "prom_database_file_io_stats"
TITLE = "Database File IO Stats"
TAGS = ["mssql", "sqlmonitor", "IO Stats", "prometheus"]


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance"),
        query_var("database",
                  'label_values(mssql_virtualfilestats__num_of_reads{instance="$Server"}, database_name)',
                  label="Database", multi=True, include_all=True),
        query_var("disk_drive",
                  'label_values(mssql_virtualfilestats__num_of_reads{instance="$Server"}, disk_volume)',
                  label="Disk", multi=True, include_all=True),
        constant_var("top_n", "25", label="Top N Rows"),
    ]


I = ('{instance="$Server",database_name=~"$database",'
     'disk_volume=~"$disk_drive"}')


def panels():
    ps: list[Panel] = []
    # ---- File IO Stats — Since Startup (table) ----
    ps.append(Panel(
        title="File IO Stats ___ Since Startup",
        description=("Per-file counters since SQL Server start, straight "
                     "off mssql_virtualfilestats__*: bytes read/written, "
                     "IO counts and cumulative stall time (ms)."),
        type="table", unit="short",
        grid=(0, 0, 24, 10),
        targets=[
            Target(f"mssql_virtualfilestats__num_of_bytes_read{I}",
                   legend="", ref="BR", instant=True, format="table"),
            Target(f"mssql_virtualfilestats__num_of_bytes_written{I}",
                   legend="", ref="BW", instant=True, format="table"),
            Target(f"mssql_virtualfilestats__num_of_reads{I}",
                   legend="", ref="NR", instant=True, format="table"),
            Target(f"mssql_virtualfilestats__num_of_writes{I}",
                   legend="", ref="NW", instant=True, format="table"),
            Target(f"mssql_virtualfilestats__io_stall_read_ms{I}",
                   legend="", ref="SR", instant=True, format="table"),
            Target(f"mssql_virtualfilestats__io_stall_write_ms{I}",
                   legend="", ref="SW", instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "job": True, "target": True,
                                    "exported_job": True},
                "renameByName": {
                    "database_name": "Database",
                    "file_logical_name": "File",
                    "disk_volume": "Volume",
                    "Value #BR": "Bytes Read",
                    "Value #BW": "Bytes Written",
                    "Value #NR": "# Reads",
                    "Value #NW": "# Writes",
                    "Value #SR": "Stall Read (ms)",
                    "Value #SW": "Stall Write (ms)",
                },
            }},
        ],
    ))

    # ---- File IO Stats — Since Startup till $__from ----
    ps.append(Panel(
        title="File IO Stats ___ Since Startup till ${__from:date:YYYY-MM-DD HH.mm}",
        description=("Counter values at the dashboard's `from` time — "
                     "accumulated IO from SQL startup until the start of "
                     "the visible range."),
        type="table", unit="short",
        grid=(0, 10, 24, 10),
        targets=[Target(
            f"mssql_virtualfilestats__num_of_bytes_read{I} "
            f"@ end() offset ($__to - $__from)",
            legend="", ref="A", instant=True, format="table")],
    ))

    # ---- File IO Stats — In Selected Time Duration ----
    ps.append(Panel(
        title=("File IO Stats ___ In Selected Time Duration ___"
               "${__from:date:YYYY-MM-DD HH.mm} → "
               "${__to:date:YYYY-MM-DD HH.mm}"),
        description=("Delta of each virtualfilestats counter over the "
                     "dashboard's visible range (increase())."),
        type="table", unit="short",
        grid=(0, 20, 24, 10),
        targets=[
            Target(f"increase(mssql_virtualfilestats__num_of_bytes_read{I}[$__range])",
                   legend="", ref="BR", instant=True, format="table"),
            Target(f"increase(mssql_virtualfilestats__num_of_bytes_written{I}[$__range])",
                   legend="", ref="BW", instant=True, format="table"),
            Target(f"increase(mssql_virtualfilestats__num_of_reads{I}[$__range])",
                   legend="", ref="NR", instant=True, format="table"),
            Target(f"increase(mssql_virtualfilestats__num_of_writes{I}[$__range])",
                   legend="", ref="NW", instant=True, format="table"),
            Target(f"increase(mssql_virtualfilestats__io_stall_read_ms{I}[$__range])",
                   legend="", ref="SR", instant=True, format="table"),
            Target(f"increase(mssql_virtualfilestats__io_stall_write_ms{I}[$__range])",
                   legend="", ref="SW", instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "job": True, "target": True,
                                    "exported_job": True},
            }},
        ],
    ))

    # ---- File IO Stats Reads/Writes (Data - bytes) Histogram ----
    ps.append(Panel(
        title="[${Server}] - Db File IO Stats - Read/Writes Data",
        description=("Per-file bytes-read and bytes-written rates "
                     "(bytes/sec), derived from the two underlying "
                     "counters."),
        type="timeseries", unit="Bps",
        grid=(0, 30, 24, 12),
        targets=[
            Target(
                f"rate(mssql_virtualfilestats__num_of_bytes_read{I}[$__rate_interval])",
                legend="read • {{database_name}} / {{file_logical_name}}",
                ref="Reads"),
            Target(
                f"rate(mssql_virtualfilestats__num_of_bytes_written{I}[$__rate_interval])",
                legend="write • {{database_name}} / {{file_logical_name}}",
                ref="Writes"),
        ],
    ))

    # ---- File IO Stats Reads/Writes (#) Histogram ----
    ps.append(Panel(
        title="[${Server}] - Db File IO Stats - # Read/Writes",
        description=("Per-file IO operations per second "
                     "(reads + writes), derived from the operation "
                     "counters."),
        type="timeseries", unit="ops",
        grid=(0, 42, 24, 12),
        targets=[
            Target(
                f"rate(mssql_virtualfilestats__num_of_reads{I}[$__rate_interval])",
                legend="reads/s • {{database_name}} / {{file_logical_name}}",
                ref="Reads"),
            Target(
                f"rate(mssql_virtualfilestats__num_of_writes{I}[$__rate_interval])",
                legend="writes/s • {{database_name}} / {{file_logical_name}}",
                ref="Writes"),
        ],
    ))

    # ---- Database IO Stats — Trend ----
    ps.append(Panel(
        title="[${Server}] - Db IO Stats - Read/Writes Data",
        description=("Aggregated per-database read/write throughput "
                     "(Bps), summed across files."),
        type="timeseries", unit="Bps",
        grid=(0, 54, 24, 12),
        targets=[
            Target(
                f"sum by (database_name) ("
                f"rate(mssql_virtualfilestats__num_of_bytes_read{I}[$__rate_interval]))",
                legend="read • {{database_name}}", ref="R"),
            Target(
                f"sum by (database_name) ("
                f"rate(mssql_virtualfilestats__num_of_bytes_written{I}[$__rate_interval]))",
                legend="write • {{database_name}}", ref="W"),
        ],
    ))

    # ---- Database IO Stats — Since Startup (aggregated) ----
    ps.append(Panel(
        title="Database IO Stats ___ Since Startup",
        description="Per-database aggregates of the filestats counters "
                     "from SQL Server startup.",
        type="table", unit="short",
        grid=(0, 66, 24, 10),
        targets=[
            Target(
                f"sum by (instance, database_name) ("
                f"mssql_virtualfilestats__num_of_bytes_read{I})",
                legend="", ref="BR", instant=True, format="table"),
            Target(
                f"sum by (instance, database_name) ("
                f"mssql_virtualfilestats__num_of_bytes_written{I})",
                legend="", ref="BW", instant=True, format="table"),
            Target(
                f"sum by (instance, database_name) ("
                f"mssql_virtualfilestats__io_stall_read_ms{I})",
                legend="", ref="SR", instant=True, format="table"),
            Target(
                f"sum by (instance, database_name) ("
                f"mssql_virtualfilestats__io_stall_write_ms{I})",
                legend="", ref="SW", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ---- Database IO Stats — In Selected Time Duration ----
    ps.append(Panel(
        title="Database IO Stats ___ In Selected Time Duration",
        description="Per-database delta over the dashboard range.",
        type="table", unit="short",
        grid=(0, 76, 24, 10),
        targets=[
            Target(
                f"sum by (instance, database_name) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_read{I}[$__range]))",
                legend="", ref="BR", instant=True, format="table"),
            Target(
                f"sum by (instance, database_name) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_written{I}[$__range]))",
                legend="", ref="BW", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ---- Database IO Stats — Comparison (prior window) ----
    ps.append(Panel(
        title="Database IO Stats ___ Prior Window ___ DAY(+/-)",
        description=("Same aggregate delta as above but over the time "
                     "window immediately *before* the dashboard range. "
                     "Use side-by-side with the previous panel for "
                     "day-over-day comparison."),
        type="table", unit="short",
        grid=(0, 86, 24, 10),
        targets=[
            Target(
                f"sum by (instance, database_name) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_read{I}[$__range] "
                f"@ end() offset $__range))",
                legend="", ref="BR", instant=True, format="table"),
            Target(
                f"sum by (instance, database_name) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_written{I}[$__range] "
                f"@ end() offset $__range))",
                legend="", ref="BW", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ---- Disk IO Stats — Since Startup (by disk_volume) ----
    ps.append(Panel(
        title="Disk IO Stats ___ Since Startup",
        description="Per-volume aggregates of the filestats counters.",
        type="table", unit="short",
        grid=(0, 96, 24, 10),
        targets=[
            Target(
                f"sum by (instance, disk_volume) ("
                f"mssql_virtualfilestats__num_of_bytes_read{I})",
                legend="", ref="BR", instant=True, format="table"),
            Target(
                f"sum by (instance, disk_volume) ("
                f"mssql_virtualfilestats__num_of_bytes_written{I})",
                legend="", ref="BW", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ---- Disk IO Stats — In Selected Time Duration ----
    ps.append(Panel(
        title="Disk IO Stats ___ In Selected Time Duration",
        description="Per-volume delta over the dashboard range.",
        type="table", unit="short",
        grid=(0, 106, 24, 10),
        targets=[
            Target(
                f"sum by (instance, disk_volume) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_read{I}[$__range]))",
                legend="", ref="BR", instant=True, format="table"),
            Target(
                f"sum by (instance, disk_volume) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_written{I}[$__range]))",
                legend="", ref="BW", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    # ---- Disk IO Stats — Prior window comparison ----
    ps.append(Panel(
        title="Disk IO Stats ___ Prior Window",
        description="Per-volume delta over the window immediately before "
                     "the dashboard range.",
        type="table", unit="short",
        grid=(0, 116, 24, 10),
        targets=[
            Target(
                f"sum by (instance, disk_volume) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_read{I}[$__range] "
                f"@ end() offset $__range))",
                legend="", ref="BR", instant=True, format="table"),
            Target(
                f"sum by (instance, disk_volume) ("
                f"increase(mssql_virtualfilestats__num_of_bytes_written{I}[$__range] "
                f"@ end() offset $__range))",
                legend="", ref="BW", instant=True, format="table"),
        ],
        transformations=[{"id": "merge", "options": {}}],
    ))

    return ps
