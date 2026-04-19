"""Spec for ``Wait Stats`` Prometheus port (UID: prom_wait_stats).

SQL source dashboard has 4 data panels:

    1. Table   "Wait Stats with ${sql_schedulers} CPUs since Startup"
       → top waits ranked by wait_percentage with resource/signal splits.
    2. Table   "Wait Stats Since Startup till ${__from}"
       → same as (1) but evaluated at the dashboard's start time.
    3. Table   "Wait Stats In Selected Time Duration"
       → deltas between ${__from} and ${__to}.
    4. Timeseries  "[${server}] - WaitStats"
       → per-wait_type wait_time_seconds rate over the range.

All panels port 1:1 using ``mssql_waits__*`` counter metrics which are
already produced by ``mssql_dba_cached.collector.yml``.
"""
from prom_dashboard import Panel, Target, query_var, constant_var


UID = "prom_wait_stats"
TITLE = "Wait Stats"
TAGS = ["mssql", "sqlmonitor", "Wait Stats", "prometheus"]


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance", multi=False, include_all=False),
        query_var("sql_schedulers",
                  'query_result(mssql_sqlserver_cpu_count{instance="$Server"})',
                  label="SQL Schedulers", hide=2),
        query_var("sqlserver_start_time_utc",
                  'query_result((time() - mssql_sqlserver_uptime_seconds{instance="$Server"}) * 1000)',
                  label="SQL Start Time UTC (ms)", hide=2),
        constant_var("top_n", "20", label="Top N Waits"),
    ]


def panels():
    ps: list[Panel] = []
    I = '{instance="$Server"}'

    # Panel 1 - table "Wait Stats with $sql_schedulers CPUs since Startup"
    # Uses the raw counter values (since startup = counter-to-date).
    ps.append(Panel(
        title=("Wait Stats with \"__${sql_schedulers} CPUs__\" since Startup"),
        description=("Top wait_types ranked by wait_time since SQL Server "
                     "last started. Matches the SQL dashboard's first table."),
        type="table", unit="s",
        grid=(0, 0, 24, 11),
        targets=[
            Target(f"topk($top_n, mssql_waits__wait_time_seconds{I})",
                   legend="{{wait_type}}", ref="WaitSec", instant=True,
                   format="table"),
            Target(f"mssql_waits__resource_time_seconds{I}",
                   legend="{{wait_type}}", ref="ResSec", instant=True,
                   format="table"),
            Target(f"mssql_waits__signal_time_seconds{I}",
                   legend="{{wait_type}}", ref="SigSec", instant=True,
                   format="table"),
            Target(f"mssql_waits__waiting_tasks_count{I}",
                   legend="{{wait_type}}", ref="Waiters", instant=True,
                   format="table"),
            Target(f"mssql_waits__wait_percentage{I}",
                   legend="{{wait_type}}", ref="Pct", instant=True,
                   format="table"),
            Target(f"mssql_waits__wait_rank_no{I}",
                   legend="{{wait_type}}", ref="Rank", instant=True,
                   format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "instance": True, "job": True,
                                    "exported_job": True, "target": True},
                "renameByName": {
                    "wait_type": "Wait Type",
                    "Value #Rank": "Rank",
                    "Value #WaitSec": "Wait (s)",
                    "Value #ResSec": "Resource (s)",
                    "Value #SigSec": "Signal (s)",
                    "Value #Waiters": "Waiting Tasks",
                    "Value #Pct": "Wait %",
                },
                "indexByName": {"Rank": 0, "Wait Type": 1, "Wait (s)": 2,
                                  "Resource (s)": 3, "Signal (s)": 4,
                                  "Waiting Tasks": 5, "Wait %": 6},
            }},
        ],
    ))

    # Panel 2 - Since Startup till $__from (historical snapshot)
    ps.append(Panel(
        title="Wait Stats ____Since Startup ___ till ___ ${__from:date:YYYY-MM-DD HH.mm}___",
        description=("Counter value at dashboard `from` time — "
                     "waits accumulated from SQL startup until the start of "
                     "the visible range."),
        type="table", unit="s",
        grid=(0, 11, 24, 7),
        targets=[Target(
            f"topk($top_n, mssql_waits__wait_time_seconds{I} @ end() offset ($__to - $__from))",
            legend="{{wait_type}}", ref="A", instant=True, format="table")],
    ))

    # Panel 3 - Delta over selected time duration
    ps.append(Panel(
        title=("Wait Stats ____In Selected Time Duration____Since____"
               "${__from:date:YYYY-MM-DD HH.mm}___till___"
               "${__to:date:YYYY-MM-DD HH.mm}____"),
        description=("Wait time accrued between `from` and `to`. "
                     "Uses increase() on the counter, so wait type = "
                     "additional seconds waited in the visible range."),
        type="table", unit="s",
        grid=(0, 18, 24, 7),
        targets=[Target(
            f"topk($top_n, sum by (wait_type) ("
            f"increase(mssql_waits__wait_time_seconds{I}[$__range])))",
            legend="{{wait_type}}", ref="A", instant=True, format="table")],
    ))

    # Panel 4 - Timeseries of wait_time rate per wait_type
    ps.append(Panel(
        title="[${Server}] - WaitStats",
        description=("rate(mssql_waits__wait_time_seconds) per wait_type — "
                     "top N by average rate over the visible range."),
        type="timeseries", unit="s",
        grid=(0, 25, 24, 19),
        targets=[Target(
            f"topk($top_n, sum by (wait_type) ("
            f"rate(mssql_waits__wait_time_seconds{I}[$__rate_interval])))",
            legend="{{wait_type}}", ref="A")],
    ))

    return ps
