import pyodbc

def call_usp_update_alert_slack_ts_value(sql_connection, alert_id:int, slack_ts_value:str, logger=None, verbose:bool=False):
    cursor = sql_connection.cursor()

    sql_query = f"""
SET NOCOUNT ON;
declare @_rows_affected int;
exec @_rows_affected = dbo.usp_update_alert_slack_ts_value @alert_id = ?, @slack_ts_value = ?;
select [is_found] = @_rows_affected
    """

    if verbose:
        logger.info(f"execute following query inside call_usp_update_alert_slack_ts_value() => ")
        print(f"______________")
        print(sql_query)
        print(f"______________")

    cursor.execute(sql_query, alert_id, slack_ts_value)
    query_resultset = cursor.fetchone()

    sql_connection.commit()
    cursor.close()

    return (True if query_resultset.is_found > 0 else False )

