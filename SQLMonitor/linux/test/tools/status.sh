#!/usr/bin/env bash
# status.sh - operator queries against the test rig's inventory instance.
#
# The SQL lives here rather than inline in the Makefile: nesting T-SQL string
# literals inside `docker compose exec bash -c '...'` inside a make recipe means
# three layers of quoting, and it breaks the moment a query needs an N'' string.
#
# Usage:
#   status.sh jobs      start every (dba) SQLMonitor job once, then show status
#   status.sh status    last outcome of every (dba) SQLMonitor job
#   status.sh errors    most recent dbo.sma_errorlog entries
#   status.sh data      row counts in the all_server_* tables

set -uo pipefail

INVENTORY_SERVER="${INVENTORY_SERVER:-inventory}"
INVENTORY_DATABASE="${INVENTORY_DATABASE:-DBA}"
SA_PASSWORD="${SA_PASSWORD:?SA_PASSWORD is required}"
SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"

run() { # run <database> <query> [extra sqlcmd args...]
    local db="$1" query="$2"; shift 2
    SQLCMDPASSWORD="$SA_PASSWORD" "$SQLCMD" -S "$INVENTORY_SERVER" -d "$db" -U sa -C \
        -W -s'|' "$@" -Q "SET NOCOUNT ON; $query"
}

JOB_STATUS_SQL="
select [job]      = convert(varchar(46), j.name),
       [on]       = j.enabled,
       [last_run] = msdb.dbo.agent_datetime(h.run_date, h.run_time),
       [secs]     = h.run_duration,
       [status]   = convert(varchar(10), case h.run_status
                        when 0 then N'Failed' when 1 then N'Succeeded'
                        when 2 then N'Retry'  when 3 then N'Canceled'
                        else N'NotRun' end),
       [message]  = convert(varchar(70), h.message)
from msdb.dbo.sysjobs j
join msdb.dbo.syscategories c on c.category_id = j.category_id and c.name = N'(dba) SQLMonitor'
outer apply (select top 1 * from msdb.dbo.sysjobhistory hh
             where hh.job_id = j.job_id and hh.step_id = 0
             order by hh.instance_id desc) h
order by case when h.run_status = 1 then 2 else 1 end, j.name;"

case "${1:-status}" in
    jobs)
        mapfile -t jobs < <(
            SQLCMDPASSWORD="$SA_PASSWORD" "$SQLCMD" -S "$INVENTORY_SERVER" -d msdb -U sa -C -h -1 -W \
                -Q "SET NOCOUNT ON; select j.name from msdb.dbo.sysjobs j join msdb.dbo.syscategories c on c.category_id = j.category_id where c.name = N'(dba) SQLMonitor' and j.enabled = 1 order by j.name;" \
            | sed '/^$/d'
        )
        [ "${#jobs[@]}" -gt 0 ] || { echo "No (dba) SQLMonitor jobs found - run 'make install' first."; exit 1; }
        for j in "${jobs[@]}"; do
            printf 'start %s\n' "$j"
            run msdb "exec msdb.dbo.sp_start_job @job_name = N'${j//\'/\'\'}';" >/dev/null 2>&1 || true
        done
        echo "waiting 30s for the jobs to finish.."
        sleep 30
        run msdb "$JOB_STATUS_SQL"
        ;;
    status)
        run msdb "$JOB_STATUS_SQL"
        ;;
    errors)
        run "$INVENTORY_DATABASE" "
        select top 30 [when]    = collection_time,
               [server]  = convert(varchar(16), server),
               [fn]      = convert(varchar(34), function_name),
               [program] = convert(varchar(34), executor_program_name),
               [error]   = convert(varchar(100), error)
        from dbo.sma_errorlog order by collection_time desc;"
        ;;
    data)
        run "$INVENTORY_DATABASE" "
        select [table] = convert(varchar(46), t.name),
               [rows]  = convert(varchar(12), p.row_count)
        from sys.tables t
        join sys.dm_db_partition_stats p on p.object_id = t.object_id and p.index_id in (0,1)
        where t.name like 'all_server%' or t.name like '%_all_servers'
        order by t.name;"
        ;;
    *)
        sed -n '2,15p' "$0"; exit 1 ;;
esac
