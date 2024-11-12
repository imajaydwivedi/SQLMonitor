import pyodbc

def get_cpu(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    cpu_warning_pct = kwargs['cpu_warning_pct']
    cpu_critical_pct = kwargs['cpu_critical_pct']
    average_duration_minutes = kwargs['average_duration_minutes']

    sql_query = f"""
declare @_cpu_warning_pct decimal(20,2) = {cpu_warning_pct};
declare @_cpu_critical_pct decimal(20,2) = {cpu_critical_pct};
declare @_average_duration_minutes int = {average_duration_minutes};

declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = N'@cpu_warning_pct decimal(20,2), @cpu_critical_pct decimal(20,2), @average_duration_minutes int';

set quoted_identifier off;
set @_sql = "
select	/* {__name__} */ [sql_instance] = srv_name, collection_time_latest = max(collection_time),
		os_cpu_avg = avg(os_cpu), sql_cpu_avg = avg(sql_cpu),
		[state] = case when avg(os_cpu) >= @cpu_critical_pct or avg(sql_cpu) >= @cpu_critical_pct
						then 'Critical'
						else 'Warning'
						end,
		data_points = count(*)
from dbo.all_server_volatile_info_history vih
where 1=1
and vih.collection_time >= dateadd(minute,-@average_duration_minutes,getdate())
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = vih.srv_name)
group by srv_name
having avg(os_cpu) >= @cpu_warning_pct or avg(sql_cpu) >= @cpu_warning_pct
";
set quoted_identifier off;

exec sp_executesql @_sql, @_params, @_cpu_warning_pct, @_cpu_critical_pct, @_average_duration_minutes;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

