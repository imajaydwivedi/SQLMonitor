import pyodbc

def get_sql_blocking(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    blocked_counts_threshold = kwargs['blocked_counts_threshold']
    blocked_duration_max_seconds_threshold = kwargs['blocked_duration_max_seconds_threshold']

    sql_query = f"""
declare @blocked_counts_threshold int = {blocked_counts_threshold};
declare @blocked_duration_max_seconds_threshold bigint = {blocked_duration_max_seconds_threshold};
declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = N'@blocked_counts_threshold int, @blocked_duration_max_seconds_threshold bigint';
set @_sql = N'
select [sql_instance] = vi.srv_name, blocked_counts, blocked_duration_max_seconds,
		[state] = case when blocked_counts >= @blocked_counts_threshold*3 then ''Critical''
						when blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold*2 then ''Critical''
						when (blocked_counts >= @blocked_counts_threshold*2) and (blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold*2) then ''Critical''
						else ''Warning''
						end,
		vi.collection_time
from dbo.all_server_volatile_info vi
where 1=1
and (	blocked_counts >= @blocked_counts_threshold
    or  blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold
	)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = vi.srv_name)
';

exec sp_executesql @_sql, @_params, @blocked_counts_threshold, @blocked_duration_max_seconds_threshold;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

