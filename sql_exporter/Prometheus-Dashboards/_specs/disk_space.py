"""Spec for ``Disk Space`` Prometheus port (UID: prom_disk_space).

SQL source dashboard has 5 data panels:

    1. Table       Disk Space - [$server] - [$perfmon_host_name]
       → latest free/used/capacity per volume.
    2. Timeseries  Used Disk Space - [$server]
       → GB used per volume over time.
    3. Timeseries  % Used Disk Space - [$server]
       → percent used per volume over time.
    4. Table       Db File Space Usage - [$server] - [$host_name]
       → per database file: size, used, free (all MB).
    5. Timeseries  Db File Size - Trend - [$server] - [$host_name]
       → per database file size over time.

Metric sources:
    windows_logical_disk_{size,free}_bytes         (1, 2, 3)
    mssql_virtualfilestats__disk_{capacity,free,used}_mb    (fallback for 1-3
                                                 when windows_exporter is
                                                 unavailable on the host)
    mssql_virtualfilestats__size_on_disk_bytes  (4, 5)
    mssql_database_file_size_bytes              (4 - reported size)
"""
from prom_dashboard import Panel, Target, query_var


UID = "prom_disk_space"
TITLE = "Disk Space"
TAGS = ["mssql", "sqlmonitor", "Disk Space", "prometheus"]


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance"),
        query_var("perfmon_host_name",
                  'label_values(mssql_service_info{instance="$Server"}, host_name)',
                  label="Perfmon Host Name", hide=2),
    ]


def panels():
    ps: list[Panel] = []
    I = '{instance="$Server"}'
    WI = '{instance="$Server"}'

    # 1. Latest Disk Space table (volume, capacity, free, used, % used)
    ps.append(Panel(
        title="Disk Space - [$Server] - [$perfmon_host_name]",
        description=("Current capacity / free / used / % used per volume "
                     "from windows_exporter. Uses logical_disk metrics."),
        type="table", unit="bytes",
        grid=(0, 0, 24, 10),
        targets=[
            Target(f"windows_logical_disk_size_bytes{WI}",
                   legend="{{volume}}", ref="Size", instant=True, format="table"),
            Target(f"windows_logical_disk_free_bytes{WI}",
                   legend="{{volume}}", ref="Free", instant=True, format="table"),
            Target(
                f"windows_logical_disk_size_bytes{WI} "
                f"- windows_logical_disk_free_bytes{WI}",
                legend="{{volume}}", ref="Used", instant=True, format="table"),
            Target(
                f"100 * (windows_logical_disk_size_bytes{WI} "
                f"- windows_logical_disk_free_bytes{WI}) "
                f"/ clamp_min(windows_logical_disk_size_bytes{WI}, 1)",
                legend="{{volume}}", ref="PctUsed", instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "job": True, "target": True},
                "renameByName": {
                    "volume": "Volume",
                    "instance": "Host",
                    "Value #Size": "Size (bytes)",
                    "Value #Free": "Free (bytes)",
                    "Value #Used": "Used (bytes)",
                    "Value #PctUsed": "% Used",
                },
            }},
        ],
    ))

    # 2. Used Disk Space over time (per volume)
    ps.append(Panel(
        title="Used Disk Space - [$Server] - [$perfmon_host_name]",
        description="Used bytes per logical volume over time.",
        type="timeseries", unit="bytes",
        grid=(0, 10, 24, 12),
        targets=[Target(
            f"windows_logical_disk_size_bytes{WI} "
            f"- windows_logical_disk_free_bytes{WI}",
            legend="{{volume}}", ref="A")],
    ))

    # 3. % Used Disk Space over time (per volume)
    ps.append(Panel(
        title="% Used Disk Space - [$Server] - [$perfmon_host_name]",
        description="Percent used per logical volume over time.",
        type="timeseries", unit="percent",
        grid=(0, 22, 24, 12),
        min_value=0, max_value=100,
        targets=[Target(
            f"100 * (windows_logical_disk_size_bytes{WI} "
            f"- windows_logical_disk_free_bytes{WI}) "
            f"/ clamp_min(windows_logical_disk_size_bytes{WI}, 1)",
            legend="{{volume}}", ref="A")],
    ))

    # 4. Db File Space Usage (per file: size, used, free MB)
    ps.append(Panel(
        title="Db File Space Usage - [$Server] - [$perfmon_host_name]",
        description=("Per database file: allocated size, size on disk, "
                     "and computed free space. From "
                     "mssql_virtualfilestats__* and mssql_database_file_size_bytes."),
        type="table", unit="bytes",
        grid=(0, 34, 24, 16),
        targets=[
            Target(f"mssql_database_file_size_bytes{I}",
                   legend="{{database}}/{{file_id}}", ref="Size", instant=True,
                   format="table"),
            Target(f"mssql_virtualfilestats__size_on_disk_bytes{I}",
                   legend="{{database_name}}/{{file_logical_name}}", ref="OnDisk",
                   instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "job": True, "target": True},
                "renameByName": {
                    "database_name": "Database",
                    "file_logical_name": "Logical Name",
                    "file_location": "Physical Name",
                    "disk_volume": "Volume",
                    "Value #Size": "Allocated (bytes)",
                    "Value #OnDisk": "Size on Disk (bytes)",
                },
            }},
        ],
    ))

    # 5. Db File Size Trend (per file, over time)
    ps.append(Panel(
        title="Db File Size - Trend - [$Server] - [$perfmon_host_name]",
        description="Per database file size_on_disk over time.",
        type="timeseries", unit="bytes",
        grid=(0, 50, 24, 16),
        targets=[Target(
            f"mssql_virtualfilestats__size_on_disk_bytes{I}",
            legend="{{database_name}} / {{file_logical_name}}", ref="A")],
    ))

    return ps
