import pyodbc

def get_log_space(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    log_used_warning_pct = kwargs['log_used_warning_pct']
    log_used_critical_pct = kwargs['log_used_critical_pct']
    log_used_threshold_gb = kwargs['log_used_threshold_gb']
    only_threshold_validated = kwargs['only_threshold_validated']

    sql_query = f"""
declare @_log_used_warning_pct float = {log_used_warning_pct};
declare @_log_used_critical_pct float = {log_used_critical_pct};
declare @_log_used_threshold_gb float = {log_used_threshold_gb};
declare @_only_threshold_validated bit = ?;
/* When @_only_threshold_validated = 1, then @_log_used_pct & @_log_used_gb are not used */

declare @_sqltext nvarchar(max);
declare @_params nvarchar(max);

set @_params = '@only_threshold_validated bit, @log_used_warning_pct float, @log_used_critical_pct float, @log_used_threshold_gb float';
set @_sqltext = '
select	/* {__name__} */ [collection_time_utc] = [updated_date_utc], [sql_instance], [database_name], [log_reuse_wait_desc],
		[log_size_mb], [log_used_pct], [pre_validated] = @only_threshold_validated,
		[state] = case when ls.log_used_pct > @log_used_critical_pct then ''Critical'' else ''Warning'' end
from dbo.log_space_consumers_all_servers ls
where 1=1
'+(case when @_only_threshold_validated = 1 then '' else '--' end)+'and ls.thresholds_validated = @only_threshold_validated
'+(case when @_only_threshold_validated = 1 then '--' else '' end)+'and ( (ls.log_used_pct > @log_used_warning_pct)	or (ls.log_used_mb > (@log_used_threshold_gb*1024)) )
and (ls.updated_date_utc >= dateadd(minute,-60,getutcdate()) -- capture time remote machine
  and ls.collection_time_utc >= dateadd(minute,-20,getutcdate()) -- capture time on inventory
		)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = ls.sql_instance)
';

exec sp_executesql @_sqltext, @_params, @_only_threshold_validated, @_log_used_warning_pct, @_log_used_critical_pct, @_log_used_threshold_gb;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query, only_threshold_validated)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

