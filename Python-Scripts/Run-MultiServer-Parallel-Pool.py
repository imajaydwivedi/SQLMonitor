import pyodbc
from prettytable import PrettyTable
from prettytable import from_db_cursor
import argparse
from datetime import datetime
import os
from slack_sdk import WebClient
from multiprocessing import Pool
import math

parser = argparse.ArgumentParser(description="Script to execute sql query on multiple SQLServer",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-s", "--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("-d", "--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("--app_name", type=str, required=False, action="store", default="(dba) Run-MultiServerQuery", help="Application Name")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
inventory_server = args.inventory_server
inventory_database = args.inventory_database
app_name = args.app_name

# Get list of servers from Inventory
invCon = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={inventory_server};"
                      f"Database={inventory_database};"
                      f"App={app_name};"
                      "Trusted_Connection=yes;")

invCursor = invCon.cursor()

sql_get_servers = f"""
set nocount on;

select id.sql_instance, id.sql_instance_port, id.[database]
from dbo.instance_details id
where id.is_enabled = 1 and id.is_available = 1
"""

invCursor.execute(sql_get_servers)
servers = invCursor.fetchall()
invCursor.close()
invCon.close()

def query_server(server_row):
    #app_name = "(dba) Run-MultiServerQuery"
    #app_config = {"app_name": app_name}
    server = server_row.sql_instance
    port = server_row.sql_instance_port
    if port is None:
      port = 1433
    database = server_row.database
    print(f"Working on [{server}].[{database}]..")
    
    connectionString = f'DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={server},{port};DATABASE={database};Trusted_Connection=yes;TrustServerCertificate=YES;App={app_name};'
    '''
    cnxn = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={server},{port};"
                      f"Database={database};"
                      f"App={app_name};"
                      "Trusted_Connection=yes;")
    '''

    cnxn = pyodbc.connect(connectionString)
    
    sql_query = f"""
    set nocount on;

    waitfor delay '00:00:10';

    select top 5 [sql_instance] = '{server}', *
    from dbo.disk_space ds
    where 1=1
    --and ds.collection_time_utc >= ?
    """

    collection_time = '2024-04-26 09:00'
    sql_query = f"""
    set nocount on;

    declare @sql nvarchar(max);
    declare @params nvarchar(max);

    waitfor delay '00:00:06';

    set @params = N'@sql_instance varchar(125), @collection_time_utc datetime2';
    set @sql = N'
    select top 5 [sql_instance] = @sql_instance, *
    from dbo.disk_space ds
    where 1=1
    and ds.collection_time_utc >= @collection_time_utc
    ';

    exec sp_executesql @sql, @params, '{server}', '{collection_time}'
    """

    #print(sql_query)
    cursor = cnxn.cursor()
    #cursor.execute(sql_query, '2024-04-26 09:00')
    cursor.execute(sql_query)
    result = cursor.fetchall()
    cursor.close()
    cnxn.close()
    return result
  
def pool_handler():
    threads = math.ceil((os.cpu_count())/2)
    p = Pool(threads)
    result_all = []
    disk_result = []
    ptable = PrettyTable()

    for allrows in p.map(query_server, servers):
        for row in allrows:
          disk_result.append(row)
    
    #print(disk_result)
    ptable.field_names = [column[0] for column in disk_result[0].cursor_description]
    ptable.add_rows(disk_result)
    
    print(ptable)

if __name__ == '__main__':
    pool_handler()

