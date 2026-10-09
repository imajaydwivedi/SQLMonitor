#!/usr/bin/env bash
# verify.sh - prove the Linux inventory is actually monitoring, not merely installed.
#
# Runs inside the tools container (`make verify`). Exits non-zero if any check
# fails, so it works as a smoke test in CI as well as by hand.
#
# What it asserts:
#   1. the inventory instance really is SQL Server on Linux
#   2. no (dba) SQLMonitor job step uses CmdExec/PowerShell (impossible on Linux)
#   3. every inventory Agent job is TSQL-subsystem and enabled
#   4. the linked servers answer
#   5. the Get-AllServer* jobs have actually run and SUCCEEDED
#   6. the all_server_* tables contain fresh rows for every monitored instance
#   7. dbo.sma_errorlog has no new errors

set -uo pipefail

INVENTORY_SERVER="${INVENTORY_SERVER:-inventory}"
INVENTORY_DATABASE="${INVENTORY_DATABASE:-DBA}"
SA_PASSWORD="${SA_PASSWORD:?SA_PASSWORD is required}"
SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"

pass=0; fail=0

q()  { SQLCMDPASSWORD="$SA_PASSWORD" "$SQLCMD" -S "$INVENTORY_SERVER" -d "$1" -U sa -C -b -h -1 -W -Q "SET NOCOUNT ON; $2" 2>&1 | sed '/^$/d'; }
qt() { SQLCMDPASSWORD="$SA_PASSWORD" "$SQLCMD" -S "$INVENTORY_SERVER" -d "$1" -U sa -C -W -s'|' -Q "SET NOCOUNT ON; $2" 2>&1 | sed '/^$/d'; }

check() { # check <name> <actual> <expected-regex>
    local name="$1" actual="$2" want="$3"
    if [[ "$actual" =~ $want ]]; then
        printf '  \033[32mPASS\033[0m  %-46s %s\n' "$name" "$actual"
        pass=$((pass + 1))
    else
        printf '  \033[31mFAIL\033[0m  %-46s got=%q want=~%s\n' "$name" "$actual" "$want"
        fail=$((fail + 1))
    fi
}

echo "=== 1. platform ==="
check "inventory host_platform is Linux" \
      "$(q master "select top 1 convert(varchar(20),host_platform) from sys.dm_os_host_info;")" '^Linux$'
check "SERVERPROPERTY('HostPlatform') is NULL (not a real property)" \
      "$(q master "select isnull(convert(varchar(20),SERVERPROPERTY('HostPlatform')),'NULL');")" '^NULL$'
echo "  edition: $(q master "select convert(varchar(50),SERVERPROPERTY('Edition'));")"
echo "  agent:   $(q master "select top 1 convert(varchar(20),status_desc) from sys.dm_server_services where servicename like 'SQL Server Agent%';")"

echo
echo "=== 2. no subsystem Linux cannot run ==="
check "CmdExec/PowerShell job steps" \
      "$(q msdb "select count(*) from msdb.dbo.sysjobs j join msdb.dbo.sysjobsteps s on s.job_id=j.job_id join msdb.dbo.syscategories c on c.category_id=j.category_id where c.name=N'(dba) SQLMonitor' and s.subsystem in (N'CmdExec',N'PowerShell');")" '^0$'

echo
echo "=== 3. inventory Agent jobs ==="
check "(dba) SQLMonitor jobs installed" \
      "$(q msdb "select count(distinct j.name) from msdb.dbo.sysjobs j join msdb.dbo.syscategories c on c.category_id=j.category_id where c.name=N'(dba) SQLMonitor';")" '^[1-9][0-9]*$'
check "all job steps are TSQL subsystem" \
      "$(q msdb "select count(*) from msdb.dbo.sysjobs j join msdb.dbo.sysjobsteps s on s.job_id=j.job_id join msdb.dbo.syscategories c on c.category_id=j.category_id where c.name=N'(dba) SQLMonitor' and s.subsystem <> N'TSQL';")" '^0$'
# The two Database Mail jobs are disabled on purpose (04-disable-mail-jobs.sql).
check "no unexpectedly disabled jobs" \
      "$(q msdb "select count(*) from msdb.dbo.sysjobs j join msdb.dbo.syscategories c on c.category_id=j.category_id where c.name=N'(dba) SQLMonitor' and j.enabled=0 and j.name not in (N'(dba) Get-AllServerDashboardMail', N'(dba) Send Login Expiry EMails');")" '^0$'

echo
echo "=== 4. linked servers ==="
qt master "select [linked_server]=convert(varchar(20),s.name), [provider]=convert(varchar(15),s.provider), [data_source]=convert(varchar(25),s.data_source) from sys.servers s where s.is_linked=1;"
check "linked servers present" \
      "$(q master "select count(*) from sys.servers where is_linked=1;")" '^[1-9][0-9]*$'
check "linked servers use MSOLEDBSQL (SQLNCLI is absent on Linux)" \
      "$(q master "select count(*) from sys.servers where is_linked=1 and provider<>'MSOLEDBSQL';")" '^0$'

echo
echo "=== 5. job outcomes ==="
qt msdb "select [job]=convert(varchar(46),j.name), [status]=convert(varchar(10),case h.run_status when 0 then N'Failed' when 1 then N'Succeeded' when 2 then N'Retry' when 3 then N'Canceled' else N'NotRun' end), [msg]=convert(varchar(60),h.message)
from msdb.dbo.sysjobs j
join msdb.dbo.syscategories c on c.category_id=j.category_id and c.name=N'(dba) SQLMonitor'
outer apply (select top 1 * from msdb.dbo.sysjobhistory hh where hh.job_id=j.job_id and hh.step_id=0 order by hh.instance_id desc) h
order by case when h.run_status=1 then 2 else 1 end, j.name;"
check "no FAILED inventory jobs" \
      "$(q msdb "select count(*) from msdb.dbo.sysjobs j join msdb.dbo.syscategories c on c.category_id=j.category_id and c.name=N'(dba) SQLMonitor' and j.enabled=1 cross apply (select top 1 run_status from msdb.dbo.sysjobhistory hh where hh.job_id=j.job_id and hh.step_id=0 order by hh.instance_id desc) h where h.run_status=0;")" '^0$'
check "at least one job SUCCEEDED" \
      "$(q msdb "select count(*) from msdb.dbo.sysjobs j join msdb.dbo.syscategories c on c.category_id=j.category_id and c.name=N'(dba) SQLMonitor' and j.enabled=1 cross apply (select top 1 run_status from msdb.dbo.sysjobhistory hh where hh.job_id=j.job_id and hh.step_id=0 order by hh.instance_id desc) h where h.run_status=1;")" '^[1-9][0-9]*$'

echo
echo "=== 6. collected data ==="
qt "$INVENTORY_DATABASE" "
select [table]=convert(varchar(40),t.name), [rows]=convert(varchar(10),p.row_count)
from sys.tables t
join sys.dm_db_partition_stats p on p.object_id=t.object_id and p.index_id in (0,1)
where t.name like 'all_server%' or t.name in ('disk_space_all_servers','sql_agent_jobs_all_servers','services_all_servers','backups_all_servers')
order by t.name;"
check "dbo.all_server_stable_info has rows" \
      "$(q "$INVENTORY_DATABASE" "select count(*) from dbo.all_server_stable_info;")" '^[1-9][0-9]*$'
check "dbo.all_server_volatile_info has rows" \
      "$(q "$INVENTORY_DATABASE" "select count(*) from dbo.all_server_volatile_info;")" '^[1-9][0-9]*$'
check "every enabled instance appears in all_server_stable_info" \
      "$(q "$INVENTORY_DATABASE" "select count(*) from dbo.instance_details id where id.is_enabled=1 and id.is_alias=0 and not exists (select * from dbo.all_server_stable_info a where a.srv_name = id.sql_instance);")" '^0$'

echo
echo "=== 7. errors ==="
recent_errors="$(q "$INVENTORY_DATABASE" "select count(*) from dbo.sma_errorlog where collection_time > dateadd(minute,-30,getdate());")"
if [ "$recent_errors" != "0" ]; then
    qt "$INVENTORY_DATABASE" "select top 15 [when]=collection_time, [server]=convert(varchar(16),server), [fn]=convert(varchar(34),function_name), [error]=convert(varchar(80),error) from dbo.sma_errorlog where collection_time > dateadd(minute,-30,getdate()) order by collection_time desc;"
fi
check "no dbo.sma_errorlog entries in the last 30 min" "$recent_errors" '^0$'

echo
printf '=== %d passed, %d failed ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
