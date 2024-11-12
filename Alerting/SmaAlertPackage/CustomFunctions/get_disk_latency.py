import pyodbc

def get_disk_latency(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    disk_latency_ms_warning_threshold = kwargs['disk_latency_ms_warning_threshold']
    disk_latency_ms_critical_threshold = kwargs['disk_latency_ms_critical_threshold']
    average_duration_minutes = kwargs['average_duration_minutes']

    sql_query = f"""
declare @disk_latency_ms_warning_threshold int = {disk_latency_ms_warning_threshold};
declare @disk_latency_ms_critical_threshold int = {disk_latency_ms_critical_threshold};
declare @average_duration_minutes int = {average_duration_minutes};

declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = N'@disk_latency_ms_warning_threshold int, @disk_latency_ms_critical_threshold int, @average_duration_minutes int';

set quoted_identifier off;
set @_sql = "
;with cte_free_memory as (
	select	/* {__name__} */ [sql_instance] = vih.srv_name,
			[ram] = max(si.total_physical_memory_kb),
			[sql_ram] = ceiling(avg(vih.physical_memory_in_use_kb)),
			[avg_disk_latency_ms] = avg(avg_disk_latency_ms),
			[data_points] = count(*),
			[collection_time] = max(vih.collection_time)
	from dbo.all_server_volatile_info_history vih
	join dbo.all_server_stable_info si on si.srv_name = vih.srv_name
	where 1=1
	and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = vih.srv_name)
	and vih.collection_time >= dateadd(minute,-@average_duration_minutes,getdate())
	and vih.avg_disk_latency_ms >= @disk_latency_ms_warning_threshold
	group by vih.srv_name
)
select 	sql_instance, [disk_latency_ms] = avg_disk_latency_ms, ram, sql_ram,
		[state] = case when avg_disk_latency_ms > @disk_latency_ms_critical_threshold then 'Critical'
						else 'Warning'
						end,
        data_points, collection_time
from cte_free_memory
where 1=1
";
set quoted_identifier off;

exec sp_executesql @_sql, @_params, @disk_latency_ms_warning_threshold, @disk_latency_ms_critical_threshold, @average_duration_minutes ;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

