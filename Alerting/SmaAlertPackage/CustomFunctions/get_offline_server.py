import pyodbc

def get_offline_server(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    sql_query = f"""
declare @sql nvarchar(max);

set quoted_identifier off;
set @sql = "
select /* {__name__} */ sql_instance, port = sql_instance_port, [host_name], online = is_available,
			link_active = case when is_available = 0 then null else is_linked_server_working end,
			--[tsql jobs server] = collector_tsql_jobs_server,
		--[powershell jobs server] = collector_powershell_jobs_server,
		--[perfmon data server] = data_destination_sql_instance,
		--is_alias,
		 [last_online] = last_unavailability_time_utc
from dbo.instance_details id
where is_enabled = 1 and is_alias = 0
and (is_available = 0 or is_linked_server_working = 0)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = id.sql_instance)
";
set quoted_identifier off;

exec dbo.sp_executesql @sql;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

