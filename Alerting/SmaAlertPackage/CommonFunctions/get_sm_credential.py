import pyodbc

def get_sm_credential(sql_connection, credential_manager_database:str, cred_name:str):
    cursor = sql_connection.cursor()

    sql_query = f"""
set nocount on;

declare @password varchar(256);
exec [{credential_manager_database}].dbo.usp_get_credential @server_ip = '*', @user_name = ?, @password = @password output;
select [cred_value] = @password;
"""
    cursor.execute(sql_query, cred_name)
    sql_query_resultset = cursor.fetchone()

    return sql_query_resultset.cred_value

