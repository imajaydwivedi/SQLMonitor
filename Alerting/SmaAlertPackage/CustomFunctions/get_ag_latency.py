import pyodbc

def get_ag_latency(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    latency_minutes = kwargs['latency_minutes']
    redo_queue_size_gb = kwargs['redo_queue_size_gb']
    log_send_queue_size_gb = kwargs['log_send_queue_size_gb']

    sql_query = f"""
set nocount on;

declare @_sql nvarchar(max);
declare @_params nvarchar(max);

declare @latency_minutes int = {latency_minutes};
declare @redo_queue_size_gb int = {redo_queue_size_gb};
declare @log_send_queue_size_gb int = {log_send_queue_size_gb};

declare @filter_out_offline_sqlagent bit = 1;

set @_params = N'@latency_minutes int, @redo_queue_size_gb int, @log_send_queue_size_gb int';

set @_sql = '
if object_id(''tempdb..#replica_servers'') is not null
	drop table #replica_servers
select distinct ahs.replica_server_name
into #replica_servers
from dbo.ag_health_state_all_servers ahs
where 1=1;

select /* {__name__} */	sql_instance, [replica_database] = replica_server_name+'' || ''+database_name,
      ag_name, [is_primary] = is_primary_replica,
      ag_listener, is_local, [synchronization_state] = synchronization_state_desc, [synchronization_health] = synchronization_health_desc,
      [latency] = latency_seconds, log_send_queue_size, redo_queue_size, is_suspended,
      [state] = case	when ahs.synchronization_health_desc <> ''HEALTHY'' or ahs.synchronization_state_desc not in (''SYNCHRONIZED'',''SYNCHRONIZING'')
                      then ''Critical''
                      when (ahs.latency_seconds is not null and ahs.latency_seconds >= 2*@latency_minutes*60)
                      then ''Critical''
                      when (ahs.log_send_queue_size is not null and ahs.log_send_queue_size >= 2*@log_send_queue_size_gb*1024*1024)
                      then ''Critical''
                      when (ahs.redo_queue_size is not null and ahs.redo_queue_size >= 2*@redo_queue_size_gb*1024*1024)
                      then ''Critical''
                      else ''Warning''
                      end
      --,last_redone_time, log_send_rate, redo_rate, estimated_redo_completion_time_min, last_commit_time
      --,suspend_reason_desc, is_distributed, replica_server = rs.srv_name, updated_date_utc, collection_time_utc
from dbo.ag_health_state_all_servers ahs
left join (	select replica_server = rs.replica_server_name, srv_name = max(asi.srv_name)
		from #replica_servers rs
		join dbo.vw_all_server_info asi
			on rs.replica_server_name in (asi.machine_name, asi.server_name)
		group by rs.replica_server_name
	) rs
	on rs.replica_server = ahs.replica_server_name
where 1=1
and (	ahs.synchronization_health_desc <> ''HEALTHY''
	or	ahs.synchronization_state_desc not in (''SYNCHRONIZED'',''SYNCHRONIZING'')
	or	(ahs.latency_seconds is not null and ahs.latency_seconds >= @latency_minutes*60)
	or	(ahs.log_send_queue_size is not null and ahs.log_send_queue_size >= @log_send_queue_size_gb*1024*1024)
	or	(ahs.redo_queue_size is not null and ahs.redo_queue_size >= @redo_queue_size_gb*1024*1024)
	)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = ahs.sql_instance)
'+(case when @filter_out_offline_sqlagent = 0 then '--' else '' end)+'and exists (select 1/0 from dbo.services_all_servers sas where sas.sql_instance = ahs.sql_instance and sas.service_type = ''Agent''	and sas.status_desc = ''Running'');
';

exec sp_executesql @_sql, @_params, @latency_minutes, @redo_queue_size_gb, @log_send_queue_size_gb;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

