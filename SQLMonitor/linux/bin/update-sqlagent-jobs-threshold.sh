#!/usr/bin/env bash
# update-sqlagent-jobs-threshold.sh
#
# Linux replacement for Wrapper-UpdateSQLAgentJobsThreshold.ps1.
#
# Finds every instance whose SQLMonitor jobs are behind their threshold and
# whose last run still reported "Succeeded" (i.e. the threshold is wrong, not
# the job), then applies DDLs/QRY-UPDATE-[SQLAgentJobsThreshold].sql there.
#
# The PowerShell version pointed at a hardcoded D:\GitHub-Personal\... path.
# Here the file defaults to the copy inside this checkout and can be overridden.
#
# It also folds in PowerShell-Scripts-Miscellaneous/Wrapper-UpdateSQLAgentJobsThreshold.ps1,
# a near-duplicate whose only real difference was also picking up jobs whose
# threshold was never set (Successfull_Execution_ClockTime_Threshold_Minutes = -1).
# That behaviour is behind --include-unset-thresholds.
#
# Usage:
#   update-sqlagent-jobs-threshold.sh [--file F] [--buffer-minutes N]
#                                     [--include-unset-thresholds]
#                                     [--dry-run] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='update-sqlagent-jobs-threshold.sh'

THRESHOLD_FILE=''  # resolved after the config is loaded
BUFFER_MINUTES=30
DRY_RUN=0
INCLUDE_UNSET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --file)           THRESHOLD_FILE="$2"; shift 2 ;;
        --buffer-minutes) BUFFER_MINUTES="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=1; shift ;;
        --include-unset-thresholds) INCLUDE_UNSET=1; shift ;;
        --verbose)        SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)        sed -n '2,16p' "$0"; exit 0 ;;
        *)                sm_die "Unknown argument '$1'." ;;
    esac
done

case "$BUFFER_MINUTES" in
    ''|*[!0-9]*) sm_die "--buffer-minutes must be an integer." ;;
esac

sm_init

# Default to the copy the installer laid down, else the one in this checkout.
if [ -z "$THRESHOLD_FILE" ]; then
    for candidate in \
        "${SQLMONITOR_HOME}/DDLs/QRY-UPDATE-[SQLAgentJobsThreshold].sql" \
        "${SCRIPT_DIR}/../../../DDLs/QRY-UPDATE-[SQLAgentJobsThreshold].sql"; do
        if [ -r "$candidate" ]; then
            THRESHOLD_FILE="$candidate"
            break
        fi
    done
fi
[ -n "$THRESHOLD_FILE" ] && [ -r "$THRESHOLD_FILE" ] \
    || sm_die "Threshold script not found. Pass --file explicitly."

overdue_predicate="(   dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@_buffer_time_minutes),getutcdate()) > sj.Last_Successful_ExecutionTime
     or sj.Last_Successful_ExecutionTime is null
    )"
if [ "$INCLUDE_UNSET" -eq 1 ]; then
    overdue_predicate="(   sj.Successfull_Execution_ClockTime_Threshold_Minutes = -1
     or ${overdue_predicate}
    )"
fi

read -r -d '' QRY_JOBS_NEEDING_ATTENTION <<SQL || true
declare @_buffer_time_minutes int = ${BUFFER_MINUTES};

select distinct sj.sql_instance,
       [sql_instance_port] = isnull(id.sql_instance_port,''),
       id.[database]
from dbo.sql_agent_jobs_all_servers sj
cross apply (
        select top 1 id.sql_instance_port, id.[database]
        from dbo.instance_details id
        where id.sql_instance = sj.sql_instance and id.is_enabled = 1 and id.is_available = 1 and id.is_alias = 0
    ) id
where 1=1
and sj.JobCategory = '(dba) SQLMonitor'
and sj.JobName like '(dba) %'
and sj.IsDisabled = 0
and sj.Last_Run_Outcome = 'Succeeded'
and ${overdue_predicate}
SQL

sm_info "Find SQLAgent jobs that need threshold attention.."
targets="$(sm_inv_tsv "$APP_NAME" "$QRY_JOBS_NEEDING_ATTENTION")" \
    || sm_die "Could not read dbo.sql_agent_jobs_all_servers."

if [ -z "$targets" ]; then
    sm_info "No instance needs a threshold update."
    exit 0
fi

server_list="$(printf '%s\n' "$targets" | cut -f1 | paste -sd, -)"
sm_info "Instances to update: $server_list"

if [ "$DRY_RUN" -eq 1 ]; then
    sm_info "--dry-run given; not applying '$THRESHOLD_FILE'."
    exit 0
fi

runner_args=(--servers "$server_list" --file "$THRESHOLD_FILE")
[ "$SQLMONITOR_VERBOSE" != "0" ] && runner_args+=(--verbose)

exec "${SCRIPT_DIR}/run-on-all-servers.sh" "${runner_args[@]}"
