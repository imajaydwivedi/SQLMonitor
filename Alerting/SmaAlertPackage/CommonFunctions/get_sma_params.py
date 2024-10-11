import pyodbc

def get_sma_params(sql_connection, param_key = ''):
    cursor = sql_connection.cursor()

    if param_key == '':
        query_sma_params = 'select param_key, param_value from dbo.sma_params'
        cursor.execute(query_sma_params)
    else:
        query_sma_params = "select param_key, param_value from dbo.sma_params p where p.param_key = ?"
        cursor.execute(query_sma_params, param_key)

    sma_params_records = cursor.fetchall()

    return sma_params_records

