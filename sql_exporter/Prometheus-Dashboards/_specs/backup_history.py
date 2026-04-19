"""Spec for ``Backup History`` Prometheus port (UID: prom_backup_history).

SQL source dashboard ``t___Backup_History.json`` has 2 data panels:

    1. Table       Backup History - [$server] - [$database]
       → most recent Full/Diff/Log backup per database with size + duration
         and age-since-completion.
    2. Timeseries  Backup Size Trend - [$server] - [$database]
       → size_bytes over time, grouped by backup_type.

Backed by the new ``mssql_backup_history.collector.yml``:

    mssql_backup__last_time_utc                 {database_name, backup_type,
                                                  backup_type_desc, recovery_model}
    mssql_backup__last_duration_seconds         {database_name, backup_type}
    mssql_backup__last_size_bytes               {database_name, backup_type}
    mssql_backup__last_compressed_size_bytes    {database_name, backup_type}
    mssql_backup__age_seconds                   {database_name, backup_type}
    mssql_backup__count_last_24h                {database_name, backup_type}
"""
from prom_dashboard import Panel, Target, query_var, custom_var


UID = "prom_backup_history"
TITLE = "Backup History"
TAGS = ["mssql", "sqlmonitor", "Backup", "prometheus"]


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance", multi=True, include_all=True),
        query_var("database_name",
                  'label_values(mssql_backup__last_time_utc{instance=~"$Server"}, database_name)',
                  label="Database", multi=True, include_all=True),
        custom_var("backup_type",
                   ["__ALL__", "D", "I", "L", "F", "G", "P", "Q"],
                   default="__ALL__",
                   label="Backup Type (D=Full, I=Diff, L=Log)"),
        custom_var("full_threshold_days",
                   ["1", "2", "3", "7", "14", "30"], default="7",
                   label="Full age warn (days)"),
        custom_var("diff_threshold_hours",
                   ["4", "8", "12", "24", "48"], default="24",
                   label="Diff age warn (hours)"),
        custom_var("tlog_threshold_minutes",
                   ["5", "15", "30", "60", "120", "240"], default="30",
                   label="Log age warn (minutes)"),
    ]


def panels():
    ps: list[Panel] = []
    I = ('{instance=~"$Server",database_name=~"$database_name",'
         'backup_type=~"$backup_type"}')

    # Summary stats
    ps.append(Panel(
        title="Databases - Covered",
        description="Number of databases reporting backup history.",
        type="stat", unit="short",
        grid=(0, 0, 6, 4),
        targets=[Target(
            f'count(count by (instance, database_name) '
            f'(mssql_backup__last_time_utc{I}))',
            legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Full Backups older than $full_threshold_days days",
        description="Databases whose most recent Full (D) backup is older "
                     "than the configured threshold.",
        type="stat", unit="short",
        grid=(6, 0, 6, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(
            f'count(mssql_backup__age_seconds{{instance=~"$Server",'
            f'database_name=~"$database_name",backup_type="D"}} '
            f'> ($full_threshold_days * 86400))',
            legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Diff Backups older than $diff_threshold_hours hours",
        description="Databases whose most recent Differential (I) backup is "
                     "older than the configured threshold.",
        type="stat", unit="short",
        grid=(12, 0, 6, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(
            f'count(mssql_backup__age_seconds{{instance=~"$Server",'
            f'database_name=~"$database_name",backup_type="I"}} '
            f'> ($diff_threshold_hours * 3600))',
            legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Log Backups older than $tlog_threshold_minutes minutes",
        description="Databases whose most recent Log (L) backup is older "
                     "than the configured threshold.",
        type="stat", unit="short",
        grid=(18, 0, 6, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(
            f'count(mssql_backup__age_seconds{{instance=~"$Server",'
            f'database_name=~"$database_name",backup_type="L"}} '
            f'> ($tlog_threshold_minutes * 60))',
            legend="", ref="A", instant=True)],
    ))

    # Main detail table
    ps.append(Panel(
        title="Backup History - [$Server] - [$database_name]",
        description=("Latest backup per (database, type): age / duration / "
                     "size / compressed size / 24h count, joined by the "
                     "backup_type label."),
        type="table", unit="short",
        grid=(0, 4, 24, 16),
        targets=[
            Target(f"mssql_backup__last_time_utc{I}",
                   legend="", ref="When", instant=True, format="table"),
            Target(f"mssql_backup__age_seconds{I}",
                   legend="", ref="AgeS", instant=True, format="table"),
            Target(f"mssql_backup__last_duration_seconds{I}",
                   legend="", ref="DurS", instant=True, format="table"),
            Target(f"mssql_backup__last_size_bytes{I}",
                   legend="", ref="Size", instant=True, format="table"),
            Target(f"mssql_backup__last_compressed_size_bytes{I}",
                   legend="", ref="CompSize", instant=True, format="table"),
            Target(f"mssql_backup__count_last_24h{I}",
                   legend="", ref="Cnt24h", instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "job": True, "target": True,
                                    "exported_job": True},
                "renameByName": {
                    "instance": "Server",
                    "database_name": "Database",
                    "backup_type": "Type",
                    "backup_type_desc": "Type Description",
                    "recovery_model": "Recovery Model",
                    "Value #When":     "Last Backup (UTC epoch)",
                    "Value #AgeS":     "Age (s)",
                    "Value #DurS":     "Duration (s)",
                    "Value #Size":     "Size (bytes)",
                    "Value #CompSize": "Compressed (bytes)",
                    "Value #Cnt24h":   "Count (24h)",
                },
            }},
        ],
    ))

    # Size trend
    ps.append(Panel(
        title="Backup Size Trend - [$Server] - [$database_name]",
        description="Per-(database, backup_type) backup size over time.",
        type="timeseries", unit="bytes",
        grid=(0, 20, 24, 12),
        targets=[Target(
            f"mssql_backup__last_size_bytes{I}",
            legend="{{database_name}} / {{backup_type}}", ref="A")],
    ))

    return ps
