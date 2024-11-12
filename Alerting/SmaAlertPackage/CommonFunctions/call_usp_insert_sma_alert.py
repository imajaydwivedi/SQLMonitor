import pyodbc

def call_usp_insert_sma_alert(sql_connection, logger=None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    sql_query = f"""
SET NOCOUNT ON;
declare @_alert_id bigint;
declare @_alert_id_RETURN bigint;
declare @_is_pre_existing bit;
declare @_affected_servers as affected_servers_type;
declare @_description nvarchar(max);

set @_description = ?;

--insert @_affected_servers
--values ('21L-LTPABL-1187',NULL);

exec @_alert_id_RETURN = dbo.usp_insert_sma_alert
    @alert_id_OUTPUT = @_alert_id output,
    @is_pre_existing_OUTPUT = @_is_pre_existing output,
    @alert_key = '{kwargs['alert_key']}',
    @frequency_minutes = {kwargs['frequency_minutes']},
    @alert_owner_team = '{kwargs['alert_owner_team']}',
    @state = '{kwargs['state']}',
    @action_to_take = '{kwargs['action_to_take']}',
    @severity = '{kwargs['severity']}',
    @logged_by = '{kwargs['logged_by']}',
    @header = '{kwargs['header']}',
    @description = @_description,
    @affected_servers = @_affected_servers,
    @verbose = 0;

select [result_alert_id] = @_alert_id_RETURN, [alert_id] = @_alert_id, [is_pre_existing] = @_is_pre_existing;
    """

    if verbose:
        logger.info(f"execute following query inside call_usp_insert_sma_alert() => ")
        print(f"______________")
        print(sql_query)
        print(f"______________")

    cursor.execute(sql_query, kwargs['description'])
    #cursor.execute(sql_query)
    #query_resultset = cursor.fetchall()
    query_resultset = cursor.fetchone()

    sql_connection.commit()
    cursor.close()

    return query_resultset

