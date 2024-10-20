import pyodbc

def get_disk_space(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    disk_warning_pct = kwargs['disk_warning_pct']
    disk_critical_pct = kwargs['disk_critical_pct']
    disk_threshold_gb = kwargs['disk_threshold_gb']
    large_disk_threshold_pct = kwargs['large_disk_threshold_pct']

    sql_query = f"""
declare @_disk_warning_pct decimal(20,2) = {disk_warning_pct};
declare @_disk_critical_pct decimal(20,2) = {disk_critical_pct};
declare @_disk_threshold_gb decimal(20,2) = {disk_threshold_gb};
declare @_large_disk_threshold_pct decimal(20,2) = {large_disk_threshold_pct};;

declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = '@disk_warning_pct decimal(20,2), @disk_critical_pct decimal(20,2), @disk_threshold_gb decimal(20,2), @large_disk_threshold_pct decimal(20,2)';

set quoted_identifier off;
set @_sql = "
select	/* {__name__} */ ds.updated_date_utc, ds.sql_instance, ds.host_name, ds.disk_volume, ds.label, ds.capacity_mb, ds.free_mb,
		[state] = case when (ds.free_mb*100.0/ds.capacity_mb) < (100.0-@disk_critical_pct) then 'Critical' else 'Warning' end,
		--[free_pct] = convert(numeric(20,2),ds.free_mb*100.0/ds.capacity_mb),
		[used_pct] = 100.0-convert(numeric(20,2),ds.free_mb*100.0/ds.capacity_mb)
		--ds.block_size, ds.filesystem,
    --, ds.collection_time_utc
from dbo.disk_space_all_servers ds
where ds.updated_date_utc >= dateadd(minute,-60,getutcdate())
and (	(	(ds.free_mb*100.0/ds.capacity_mb) < (100-@disk_warning_pct)
			and ds.free_mb < (@disk_threshold_gb)*1024
	  	)
		or ( (ds.free_mb*100.0/ds.capacity_mb) < (100-@large_disk_threshold_pct)) -- free %
		)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = ds.sql_instance)
";
set quoted_identifier off;

exec sp_executesql @_sql, @_params, @_disk_warning_pct, @_disk_critical_pct, @_disk_threshold_gb , @_large_disk_threshold_pct;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

