"""Spec for ``XEvent - Trend`` Prometheus port (UID: prom_xevent_trend).

SQL source dashboard ``XEvent - Trend.json`` has 3 data panels:

    1. Timeseries  CPU Trend by {grouping_key}
    2. Timeseries  Counts Trend by {grouping_key}
    3. Timeseries  Reads Trend by {grouping_key}

Backed by the new ``mssql_xevent.collector.yml``:

    mssql_xevent__events_last_5m          {event_name, database_name,
                                            result, client_app_name}
    mssql_xevent__cpu_time_ms_last_5m     (same labels)
    mssql_xevent__duration_seconds_last_5m
    mssql_xevent__logical_reads_last_5m
    mssql_xevent__physical_reads_last_5m
    mssql_xevent__writes_last_5m

The SQL dashboard lets the user toggle the grouping key (event / db /
login / program). Prometheus has no SUM(CASE ...) GROUP BY, so we ship
one variable ``$grouping_key`` and build the ``sum by (<key>)`` expr
with a templated label name.
"""
from prom_dashboard import Panel, Target, query_var, custom_var


UID = "prom_xevent_trend"
TITLE = "XEvent - Trend"
TAGS = ["mssql", "sqlmonitor", "XEvent", "prometheus"]


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance"),
        query_var("database",
                  'label_values(mssql_xevent__events_last_5m{instance="$Server"}, database_name)',
                  label="Database", multi=True, include_all=True),
        query_var("event_name",
                  'label_values(mssql_xevent__events_last_5m{instance="$Server"}, event_name)',
                  label="Event", multi=True, include_all=True),
        query_var("result",
                  'label_values(mssql_xevent__events_last_5m{instance="$Server"}, result)',
                  label="Result", multi=True, include_all=True),
        query_var("client_app",
                  'label_values(mssql_xevent__events_last_5m{instance="$Server"}, client_app_name)',
                  label="Client App", multi=True, include_all=True),
        custom_var("grouping_key",
                   ["event_name", "database_name",
                    "client_app_name", "result"],
                   default="event_name", label="Group by"),
        custom_var("top_n",
                   ["5", "10", "15", "20", "25"], default="10",
                   label="Top N series"),
    ]


def panels():
    ps: list[Panel] = []
    I = ('{instance="$Server",database_name=~"$database",'
         'event_name=~"$event_name",result=~"$result",'
         'client_app_name=~"$client_app"}')

    # 1 - CPU Trend (cpu_time_ms → seconds)
    ps.append(Panel(
        title="XEvent - CPU Trend - By - {${grouping_key}}",
        description=("CPU time (seconds) attributed to extended events, "
                     "summed per ${grouping_key}. Uses the 5-minute "
                     "aggregate gauge published by mssql_xevent; rendered "
                     "as a rate since the gauge resets each collection."),
        type="timeseries", unit="s",
        grid=(0, 0, 24, 11),
        targets=[Target(
            f"topk($top_n, sum by (${{grouping_key}}) ("
            f"mssql_xevent__cpu_time_ms_last_5m{I} / 1000))",
            legend="{{${grouping_key}}}", ref="A")],
    ))

    # 2 - Counts Trend
    ps.append(Panel(
        title="XEvent - Counts Trend - By - {${grouping_key}}",
        description=("Count of extended events in the most recent "
                     "5-minute window, summed per ${grouping_key}."),
        type="timeseries", unit="short",
        grid=(0, 11, 24, 11),
        targets=[Target(
            f"topk($top_n, sum by (${{grouping_key}}) ("
            f"mssql_xevent__events_last_5m{I}))",
            legend="{{${grouping_key}}}", ref="A")],
    ))

    # 3 - Reads Trend (logical + physical)
    ps.append(Panel(
        title="XEvent - Reads Trend - By - {${grouping_key}}",
        description=("Logical + physical reads attributed to extended "
                     "events, summed per ${grouping_key}."),
        type="timeseries", unit="short",
        grid=(0, 22, 24, 11),
        targets=[
            Target(
                f"topk($top_n, sum by (${{grouping_key}}) ("
                f"mssql_xevent__logical_reads_last_5m{I}))",
                legend="logical • {{${grouping_key}}}", ref="Logical"),
            Target(
                f"topk($top_n, sum by (${{grouping_key}}) ("
                f"mssql_xevent__physical_reads_last_5m{I}))",
                legend="physical • {{${grouping_key}}}", ref="Physical"),
        ],
    ))

    # 4 - Duration (bonus panel; useful complement to the SQL original)
    ps.append(Panel(
        title="XEvent - Duration Trend - By - {${grouping_key}}",
        description=("Sum of durations (seconds) for extended events in "
                     "the 5-minute window, per ${grouping_key}."),
        type="timeseries", unit="s",
        grid=(0, 33, 24, 11),
        targets=[Target(
            f"topk($top_n, sum by (${{grouping_key}}) ("
            f"mssql_xevent__duration_seconds_last_5m{I}))",
            legend="{{${grouping_key}}}", ref="A")],
    ))

    return ps
