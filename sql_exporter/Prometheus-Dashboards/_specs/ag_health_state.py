"""Spec for ``Ag Health State`` Prometheus port (UID: prom_ag_health_state).

SQL source dashboard has 3 data panels and one dashlist:

    1. Table       LIVE - AlwaysOn Availability Group Health Metrics - [$server]
       -> latest synchronization_health / state / queue sizes / rates.
    2. Table       Latest - AlwaysOn Availability Groups - Status - FILTERED
                   @ ${ag_health_state_collection_time_utc}
       -> same columns as (1); SQL version resolves the anchor timestamp to
          an exact cached snapshot. Under Prometheus we serve the latest
          value within the visible range instead (documented in the panel
          description).
    3. Timeseries  Trend - AlwaysOn Latency
       -> mssql_aghealth__latency_seconds per (replica, database).

All metrics come from ``mssql_dba_aghealth.collector.yml`` which is
already shipped with the exporter.
"""
from prom_dashboard import Panel, Target, query_var, custom_var


UID = "prom_ag_health_state"
TITLE = "Ag Health State"
TAGS = ["mssql", "sqlmonitor", "Ag Health State", "prometheus"]


_SYNC_STATE_ALL = ".*"
_SYNC_HEALTH_ALL = ".*"


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance", multi=True, include_all=True),
        query_var("ag_name",
                  'label_values(mssql_aghealth__synchronization_health{instance=~"$Server"}, ag_name)',
                  label="AG Name", multi=True, include_all=True),
        query_var("ag_listener",
                  'label_values(mssql_aghealth__synchronization_health{instance=~"$Server"}, ag_listener)',
                  label="AG Listener", multi=True, include_all=True),
        query_var("replica_server_name",
                  'label_values(mssql_aghealth__synchronization_health{instance=~"$Server"}, replica_server_name)',
                  label="Replica Server", multi=True, include_all=True),
        query_var("database_name",
                  'label_values(mssql_aghealth__synchronization_health{instance=~"$Server"}, database_name)',
                  label="Database", multi=True, include_all=True),
        query_var("sync_state_desc",
                  'label_values(mssql_aghealth__synchronization_health{instance=~"$Server"}, synchronization_state_desc)',
                  label="Sync State", multi=True, include_all=True),
        query_var("sync_health_desc",
                  'label_values(mssql_aghealth__synchronization_health{instance=~"$Server"}, synchronization_health_desc)',
                  label="Sync Health", multi=True, include_all=True),
        custom_var("replica_type", ["__ALL__", "Primary", "Secondary", "Local"],
                   default="__ALL__", label="Replica Type"),
        custom_var("latency_minutes",
                   ["-1", "0", "1", "5", "15", "30", "60"],
                   default="-1", label="Min Latency (min, -1=off)"),
    ]


def panels():
    ps: list[Panel] = []

    # Selector string shared by every panel: honours all the filter vars.
    sel = (
        '{instance=~"$Server",ag_name=~"$ag_name",'
        'ag_listener=~"$ag_listener",'
        'replica_server_name=~"$replica_server_name",'
        'database_name=~"$database_name",'
        'synchronization_state_desc=~"$sync_state_desc",'
        'synchronization_health_desc=~"$sync_health_desc"}'
    )
    # unique_key-only selector for metrics that only carry unique_key labels.
    uksel = '{instance=~"$Server"}'

    # ---- Panel 1: LIVE table (multi-metric merge by unique_key + tags) ----
    def t(metric: str, ref: str, has_tags: bool = False) -> Target:
        s = sel if has_tags else uksel
        return Target(f"{metric}{s}", legend="", ref=ref,
                      instant=True, format="table")

    ps.append(Panel(
        title="LIVE - AlwaysOn Availability Group Health Metrics - [$Server]",
        description=("Latest AG replica health joined by unique_key. "
                     "Sync state / health / queue sizes / rates / latency "
                     "from mssql_aghealth__*."),
        type="table", unit="short",
        grid=(0, 0, 24, 14),
        targets=[
            t("mssql_aghealth__synchronization_health", "Health", has_tags=True),
            t("mssql_aghealth__synchronization_state", "State"),
            t("mssql_aghealth__is_primary_replica", "Primary"),
            t("mssql_aghealth__is_local", "Local"),
            t("mssql_aghealth__is_suspended", "Suspended"),
            t("mssql_aghealth__latency_seconds", "Latency"),
            t("mssql_aghealth__log_send_queue_size", "LogSendQ"),
            t("mssql_aghealth__redo_queue_size", "RedoQ"),
            t("mssql_aghealth__log_send_rate", "LogRate"),
            t("mssql_aghealth__redo_rate", "RedoRate"),
            t("mssql_aghealth__estimated_redo_completion_time_min", "RedoEtaMin"),
            t("mssql_aghealth__last_redone_time", "LastRedone"),
            t("mssql_aghealth__last_commit_time", "LastCommit"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True, "job": True,
                                    "target": True, "exported_job": True},
                "renameByName": {
                    "replica_server_name": "Replica",
                    "database_name": "Database",
                    "ag_name": "AG",
                    "ag_listener": "Listener",
                    "synchronization_state_desc": "Sync State",
                    "synchronization_health_desc": "Sync Health",
                    "suspend_reason_desc": "Suspend Reason",
                    "Value #Health": "Health (code)",
                    "Value #State": "State (code)",
                    "Value #Primary": "Is Primary",
                    "Value #Local": "Is Local",
                    "Value #Suspended": "Is Suspended",
                    "Value #Latency": "Latency (s)",
                    "Value #LogSendQ": "Log Send Queue",
                    "Value #RedoQ": "Redo Queue",
                    "Value #LogRate": "Log Send Rate",
                    "Value #RedoRate": "Redo Rate",
                    "Value #RedoEtaMin": "Est. Redo (min)",
                    "Value #LastRedone": "Last Redone (epoch s)",
                    "Value #LastCommit": "Last Commit (epoch s)",
                },
            }},
        ],
    ))

    # ---- Panel 2: "Latest at anchor" table (best-effort under Prometheus) ---
    ps.append(Panel(
        title=("Latest - AlwaysOn Availability Groups - Status - FILTERED "
               "@ dashboard end"),
        description=("SQL version anchors this at a cached collection "
                     "timestamp. Prometheus serves the latest sample within "
                     "the visible range instead."),
        type="table", unit="short",
        grid=(0, 14, 24, 11),
        targets=[Target(
            f"last_over_time(mssql_aghealth__latency_seconds{sel}[$__range])",
            legend="", ref="A", instant=True, format="table")],
    ))

    # ---- Panel 3: Latency trend timeseries ----
    ps.append(Panel(
        title="Trend - AlwaysOn Latency (seconds)",
        description=("Per (replica, database) commit latency vs the primary, "
                     "from mssql_aghealth__latency_seconds. "
                     "-1 latency means the probe could not be evaluated."),
        type="timeseries", unit="s",
        grid=(0, 25, 24, 16),
        targets=[Target(
            f"mssql_aghealth__latency_seconds{sel}",
            legend="{{replica_server_name}} || {{database_name}}", ref="A")],
    ))

    return ps
