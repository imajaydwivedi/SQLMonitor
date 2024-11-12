import pyodbc

def get_offline_agent(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    sql_query = f"""
declare @sql nvarchar(max);

set quoted_identifier off;
set @sql = "
select /* {__name__} */ sas.sql_instance, sas.startup_type_desc, sas.status_desc,
		sas.servicename, sas.service_account, state = 'Critical'
from dbo.services_all_servers sas
where 1=1
and sas.service_type = 'Agent'
and sas.status_desc <> 'Running'
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = sas.sql_instance)
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

