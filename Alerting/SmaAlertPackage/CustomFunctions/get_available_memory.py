import pyodbc

def get_available_memory(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    free_memory_ratio = kwargs['free_memory_ratio']
    low_memory_threshold_gb = kwargs['low_memory_threshold_gb']
    average_duration_minutes = kwargs['average_duration_minutes']

    sql_query = f"""
declare @free_memory_ratio int = 8;
declare @low_memory_threshold_gb int = 16;
declare @average_duration_minutes int = 10;

declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = N'@free_memory_ratio int, @low_memory_threshold_gb int, @average_duration_minutes int';

set quoted_identifier off;
set @_sql = "
;with cte_free_memory as (
	select	/* {__name__} */ [sql_instance] = vih.srv_name, --si.host_name,
			[free_memory] = avg(available_physical_memory_kb),
			[threshold] = max(ceiling(case when si.total_physical_memory_kb > (@low_memory_threshold_gb*1024*1024)
									then (4*1024*1024)+((si.total_physical_memory_kb-(@low_memory_threshold_gb*1024*1024))/@free_memory_ratio)
									else si.total_physical_memory_kb/ceiling(@free_memory_ratio/2.0)
									end)),
			[ram] = max(si.total_physical_memory_kb),
			[sql_ram] = ceiling(avg(vih.physical_memory_in_use_kb)),
			[grants_pending] = avg(vih.memory_grants_pending),
			[collection_time] = max(vih.collection_time)
	from dbo.all_server_volatile_info_history vih
	join dbo.all_server_stable_info si on si.srv_name = vih.srv_name
	where 1=1
	and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = vih.srv_name)
	and vih.collection_time >= dateadd(minute,-@average_duration_minutes,getdate())
	group by vih.srv_name
)
select  sql_instance, free_memory, threshold, ram, sql_ram, grants_pending,
		[state] = case when free_memory < (threshold*0.6) then 'Critical' else 'Warning' end,
        collection_time
from cte_free_memory
where 1=1
and free_memory < threshold
";
set quoted_identifier off;

exec sp_executesql @_sql, @_params, @free_memory_ratio, @low_memory_threshold_gb, @average_duration_minutes;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

