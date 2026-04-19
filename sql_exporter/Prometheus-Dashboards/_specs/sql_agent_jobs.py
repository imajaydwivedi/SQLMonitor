"""Spec for ``SQL Agent Jobs`` Prometheus port (UID: prom_sql_agent_jobs).

SQL source dashboards:

    - Monitoring - Live - All Servers - Job Activity Monitor.json  (5 data)
    - Monitoring - Live - All Servers.json  (failed-jobs summary rows)

Backed by the new ``mssql_sqlagent_jobs.collector.yml``:

    mssql_sqlagent_job__enabled                        {job_name, job_id,
                                                        category_name, owner_name}
    mssql_sqlagent_job__last_run_outcome               {..., last_run_outcome_desc}
    mssql_sqlagent_job__last_run_duration_seconds      {job_name, job_id}
    mssql_sqlagent_job__last_run_end_time_utc          {job_name, job_id}
    mssql_sqlagent_job__next_run_time_utc              {job_name, job_id}
    mssql_sqlagent_job__is_running                     {job_name, job_id}
    mssql_sqlagent_job__step_failures_last_24h         {job_name, job_id}
"""
from prom_dashboard import Panel, Target, query_var, custom_var


UID = "prom_sql_agent_jobs"
TITLE = "SQL Agent Jobs"
TAGS = ["mssql", "sqlmonitor", "SQL Agent", "prometheus"]


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance", multi=True, include_all=True),
        query_var("job_category",
                  'label_values(mssql_sqlagent_job__enabled{instance=~"$Server"}, category_name)',
                  label="Category", multi=True, include_all=True),
        query_var("job_name",
                  'label_values(mssql_sqlagent_job__enabled{instance=~"$Server",category_name=~"$job_category"}, job_name)',
                  label="Job Name", multi=True, include_all=True),
        custom_var("enabled", ["__ALL__", "1", "0"], default="__ALL__",
                   label="Enabled"),
        custom_var("last_outcome",
                   ["__ALL__", "Succeeded", "Failed", "Retry",
                    "Canceled", "Unknown"],
                   default="__ALL__", label="Last Outcome"),
    ]


def panels():
    ps: list[Panel] = []
    I = ('{instance=~"$Server",category_name=~"$job_category",'
         'job_name=~"$job_name"}')
    # Selector for metrics that only carry the job_name/job_id pair.
    IJ = '{instance=~"$Server",job_name=~"$job_name"}'

    # 1 - Summary stats
    ps.append(Panel(
        title="Jobs - Total",
        description="Total number of SQL Agent jobs matching the filters.",
        type="stat", unit="short",
        grid=(0, 0, 6, 4),
        targets=[Target(f"count(mssql_sqlagent_job__enabled{I})",
                        legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Jobs - Enabled",
        description="Number of enabled jobs matching the filters.",
        type="stat", unit="short",
        grid=(6, 0, 6, 4),
        thresholds_steps=[{"color": "red", "value": None},
                            {"color": "green", "value": 1}],
        targets=[Target(f"sum(mssql_sqlagent_job__enabled{I})",
                        legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Jobs - Running Now",
        description="Jobs whose latest sysjobactivity row shows "
                     "start_execution_date set and stop_execution_date NULL.",
        type="stat", unit="short",
        grid=(12, 0, 6, 4),
        targets=[Target(f"sum(mssql_sqlagent_job__is_running{IJ})",
                        legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Jobs - Last Outcome = Failed",
        description="Jobs whose most recent completed run failed.",
        type="stat", unit="short",
        grid=(18, 0, 6, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target(
            f'count(mssql_sqlagent_job__last_run_outcome{I} == 0)',
            legend="", ref="A", instant=True)],
    ))

    # 2 - Main table: join everything by (instance, job_name)
    ps.append(Panel(
        title="SQL Agent Jobs - Status Detail - [$Server]",
        description=("Per-job roll-up of enabled/outcome/duration/next-run/"
                     "running/24h-step-failures, joined on (instance, job_name)."),
        type="table", unit="short",
        grid=(0, 4, 24, 18),
        targets=[
            Target(f"mssql_sqlagent_job__enabled{I}",
                   legend="", ref="Enabled", instant=True, format="table"),
            Target(
                f"mssql_sqlagent_job__last_run_outcome{I}",
                legend="", ref="Outcome", instant=True, format="table"),
            Target(f"mssql_sqlagent_job__last_run_duration_seconds{IJ}",
                   legend="", ref="Duration", instant=True, format="table"),
            Target(f"mssql_sqlagent_job__last_run_end_time_utc{IJ}",
                   legend="", ref="LastEnd", instant=True, format="table"),
            Target(f"mssql_sqlagent_job__next_run_time_utc{IJ}",
                   legend="", ref="NextRun", instant=True, format="table"),
            Target(f"mssql_sqlagent_job__is_running{IJ}",
                   legend="", ref="Running", instant=True, format="table"),
            Target(f"mssql_sqlagent_job__step_failures_last_24h{IJ}",
                   legend="", ref="Fails24h", instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "job": True, "target": True,
                                    "exported_job": True, "job_id": True},
                "renameByName": {
                    "instance": "Server",
                    "job_name": "Job",
                    "category_name": "Category",
                    "owner_name": "Owner",
                    "last_run_outcome_desc": "Last Outcome",
                    "Value #Enabled":  "Enabled",
                    "Value #Outcome":  "Outcome (code)",
                    "Value #Duration": "Duration (s)",
                    "Value #LastEnd":  "Last Run End (UTC)",
                    "Value #NextRun":  "Next Run (UTC)",
                    "Value #Running":  "Running",
                    "Value #Fails24h": "Step Failures (24h)",
                },
            }},
        ],
    ))

    # 3 - Trend: recent failed-job count
    ps.append(Panel(
        title="Failed Jobs - Trend",
        description="Number of jobs whose last completed run was Failed "
                     "(outcome=0), tracked across time.",
        type="timeseries", unit="short",
        grid=(0, 22, 24, 10),
        targets=[Target(
            f'count(mssql_sqlagent_job__last_run_outcome{I} == 0) '
            f'by (instance)',
            legend="{{instance}}", ref="A")],
    ))

    return ps
