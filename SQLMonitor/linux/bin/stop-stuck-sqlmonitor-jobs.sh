#!/usr/bin/env bash
# stop-stuck-sqlmonitor-jobs.sh
#
# Linux replacement for Stop-SQLMonitorJobs-On-AllServers-With-Issues.ps1 and
# the "(dba) Stop-StuckSQLMonitorJobs" SQL Agent job.
#
# Reads dbo.sql_agent_jobs_all_servers on the inventory server, then stops jobs
# that have overrun their threshold and starts jobs that have not succeeded
# recently enough. Failures land in dbo.sma_errorlog exactly as before.
#
# Usage:
#   stop-stuck-sqlmonitor-jobs.sh [--no-stop] [--no-start]
#                                 [--buffer-minutes N] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='stop-stuck-sqlmonitor-jobs.sh'
JOB_NAME='(dba) Stop-StuckSQLMonitorJobs'

DO_STOP=1
DO_START=1
BUFFER_MINUTES=30

while [ $# -gt 0 ]; do
    case "$1" in
        --no-stop)         DO_STOP=0; shift ;;
        --no-start)        DO_START=0; shift ;;
        --buffer-minutes)  BUFFER_MINUTES="$2"; shift 2 ;;
        --verbose)         SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)         sed -n '2,15p' "$0"; exit 0 ;;
        *)                 sm_die "Unknown argument '$1'." ;;
    esac
done

case "$BUFFER_MINUTES" in
    ''|*[!0-9]*) sm_die "--buffer-minutes must be an integer." ;;
esac

sm_init
sm_resolve_all_server_login

# Same predicate as the PowerShell version, expressed directly rather than
# through the sp_executesql / quoted_identifier dance it needed for its
# double-quoted heredoc.
read -r -d '' QRY_STUCK_JOBS <<SQL || true
declare @_buffer_time_minutes int = ${BUFFER_MINUTES};

select  [start_job_action] = case when (dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@_buffer_time_minutes),getutcdate()) > sj.Last_Successful_ExecutionTime
                                        or sj.Last_Successful_ExecutionTime is null)
                                  then 1 else 0 end,
        [stop_job_action] = case when sj.Running_Since_Min >= (sj.Successfull_Execution_ClockTime_Threshold_Minutes * 4)
                                  then 1 else 0 end,
        [sql_instance] = sj.sql_instance,
        [sql_instance_with_port] = id.sql_instance_with_port,
        [database] = id.[database],
        [JobName] = sj.JobName
from dbo.sql_agent_jobs_all_servers sj
cross apply (
        select top 1 sql_instance_with_port = coalesce(id.sql_instance +','+ id.sql_instance_port, id.sql_instance), id.[database]
        from dbo.instance_details id
        where id.sql_instance = sj.sql_instance and id.is_enabled = 1 and id.is_available = 1 and id.is_alias = 0
    ) id
where 1=1
and sj.JobCategory = '(dba) SQLMonitor'
and sj.JobName like '(dba) %'
and sj.IsDisabled = 0
and sj.Successfull_Execution_ClockTime_Threshold_Minutes <> -1
and (   sj.Last_Run_Outcome is null
     or sj.Last_Run_Outcome in ('Succeeded','Canceled')
     or sj.Running_Since_Min >= (sj.Successfull_Execution_ClockTime_Threshold_Minutes * 4)
    )
and (   dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@_buffer_time_minutes),getutcdate()) > sj.Last_Successful_ExecutionTime
     or sj.Last_Successful_ExecutionTime is null
    )
SQL

sm_info "Fetch stuck/stalled SQLMonitor jobs from [$INVENTORY_SERVER].[$INVENTORY_DATABASE].."
rows="$(sm_inv_tsv "$APP_NAME" "$QRY_STUCK_JOBS")" \
    || sm_die "Could not read dbo.sql_agent_jobs_all_servers."

if [ -z "$rows" ]; then
    sm_info "No action required to be taken."
    exit 0
fi

sm_info "$(printf '%s\n' "$rows" | wc -l | tr -d ' ') job(s) found that need start/stop action."

# Cache per-instance reachability so one dead server is probed once, not once
# per job. Bash 4 associative array.
declare -A instance_down=()
declare -A instance_checked=()
failures=0
actions=0

run_job_action() {
    local target="$1" database="$2" job_name="$3" action="$4" sql_instance="$5"
    local proc out rc=0

    case "$action" in
        stop)  proc='msdb.dbo.sp_stop_job' ;;
        start) proc='msdb.dbo.sp_start_job' ;;
        *)     sm_die "run_job_action: bad action '$action'." ;;
    esac

    out="$(sm_fleet_sql "$target" msdb "$JOB_NAME" exec \
            "exec ${proc} @job_name = N'$(sm_sql_escape "$job_name")';" 2>&1)" || rc=$?

    if [ "$rc" -eq 0 ]; then
        sm_info "  ${action^} job [$job_name] on [$sql_instance]: Success."
        return 0
    fi

    # These two are the "already in the desired state" cases the PowerShell
    # version deliberately swallowed.
    if [ "$action" = 'stop' ] && printf '%s' "$out" | grep -qi 'not currently running'; then
        sm_info "  Stop job [$job_name] on [$sql_instance]: Not running."
        return 0
    fi
    if [ "$action" = 'start' ] && printf '%s' "$out" | grep -qi 'already running'; then
        sm_info "  Start job [$job_name] on [$sql_instance]: Already running."
        return 0
    fi

    sm_error "  ${action^} job [$job_name] on [$sql_instance] failed: ${out//$'\n'/ }"
    sm_errorlog 'Stop-SQLMonitorJobs-On-AllServers-With-Issues' \
        "${action^} job [$job_name]" "$sql_instance" "${out//$'\n'/ }" "$JOB_NAME"
    return 1
}

while IFS=$'\t' read -r start_action stop_action sql_instance target database job_name; do
    [ -n "$sql_instance" ] || continue

    if [ -n "${instance_down[$target]:-}" ]; then
        continue
    fi

    # One cheap connectivity probe per instance, mirroring the single
    # Connect-DbaInstance the PowerShell version made per server.
    if [ -z "${instance_checked[$target]:-}" ]; then
        if ! err="$(sm_fleet_sql "$target" "$database" "$JOB_NAME" scalar 'select 1;' 2>&1)"; then
            instance_down[$target]=1
            failures=$((failures + 1))
            sm_error "Create connection to [$target] failed: ${err//$'\n'/ }"
            sm_errorlog 'Stop-SQLMonitorJobs-On-AllServers-With-Issues' \
                'Connect-DbaInstance' "$sql_instance" "${err//$'\n'/ }" "$JOB_NAME"
            continue
        fi
        instance_checked[$target]=1
    fi

    if [ "$DO_STOP" -eq 1 ] && [ "$stop_action" = '1' ]; then
        actions=$((actions + 1))
        run_job_action "$target" "$database" "$job_name" stop "$sql_instance" || failures=$((failures + 1))
        sleep 5
    fi

    if [ "$DO_START" -eq 1 ] && [ "$start_action" = '1' ]; then
        actions=$((actions + 1))
        run_job_action "$target" "$database" "$job_name" start "$sql_instance" || failures=$((failures + 1))
    fi
done <<< "$rows"

sm_info "Completed. $actions action(s) attempted, $failures failure(s)."
[ "$failures" -eq 0 ]
