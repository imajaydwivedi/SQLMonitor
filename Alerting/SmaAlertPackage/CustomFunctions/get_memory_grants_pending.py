import pyodbc

def get_memory_grants_pending(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    grants_pending_threshold = kwargs['grants_pending_threshold']
    average_duration_minutes = kwargs['average_duration_minutes']

    sql_query = f"""
declare @grants_pending_threshold int = {grants_pending_threshold};
declare @average_duration_minutes int = {average_duration_minutes};

declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = N'@grants_pending_threshold int, @average_duration_minutes int';

set quoted_identifier off;
set @_sql = "
;with cte_free_memory as (
	select	/* {__name__} */ [sql_instance] = vih.srv_name, --si.host_name,
			[grants_pending] = avg(vih.memory_grants_pending),
			--[free_memory] = avg(available_physical_memory_kb),
			[ram] = max(si.total_physical_memory_kb),
			[sql_ram] = ceiling(avg(vih.physical_memory_in_use_kb)),
      [memory_consumers] = avg(memory_consumers),
			[collection_time] = max(vih.collection_time)
	from dbo.all_server_volatile_info_history vih
	join dbo.all_server_stable_info si on si.srv_name = vih.srv_name
	where 1=1
	and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = vih.srv_name)
	and vih.collection_time >= dateadd(minute,-@average_duration_minutes,getdate())
	group by vih.srv_name
)
select 	sql_instance, grants_pending, ram, sql_ram, memory_consumers,
		[state] = case when grants_pending > (@grants_pending_threshold*3) then 'Critical'
						when grants_pending > (@grants_pending_threshold*2) then 'High'
						else 'Warning'
						end,
        collection_time
from cte_free_memory
where 1=1
and grants_pending >= @grants_pending_threshold
";
set quoted_identifier off;

exec sp_executesql @_sql, @_params, @grants_pending_threshold, @average_duration_minutes ;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

