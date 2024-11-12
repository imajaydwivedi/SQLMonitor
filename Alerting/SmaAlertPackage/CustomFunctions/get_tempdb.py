import pyodbc

def get_tempdb(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    data_used_warning_pct = kwargs['data_used_warning_pct']
    data_used_critical_pct = kwargs['data_used_critical_pct']
    data_used_threshold_gb = kwargs['data_used_threshold_gb']

    sql_query = f"""
declare @_data_used_warning_pct float = {data_used_warning_pct};
declare @_data_used_critical_pct float = {data_used_critical_pct};
declare @_data_used_threshold_gb float = {data_used_threshold_gb};

declare @_sqltext nvarchar(max);
declare @_params nvarchar(max);

set @_params = '@data_used_warning_pct float, @data_used_critical_pct float, @data_used_threshold_gb float';
set @_sqltext = '
select	/* {__name__} */ [sql_instance], [data_size_mb], [data_used_pct],
		[version_store_mb], [version_store_pct],
		[state] = case when su.data_used_pct > @data_used_critical_pct then ''Critical'' else ''Warning'' end,
		[collection_time_utc] = [updated_date_utc]
from dbo.tempdb_space_usage_all_servers su
where (su.data_used_pct > @data_used_warning_pct
	or su.data_used_mb > (@data_used_threshold_gb*1024)
	)
and (su.updated_date_utc >= dateadd(minute,-60,getutcdate())
  and su.collection_time_utc >= dateadd(minute,-20,getutcdate())
	)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = su.sql_instance)
'
exec sp_executesql @_sqltext, @_params, @_data_used_warning_pct, @_data_used_critical_pct, @_data_used_threshold_gb;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

