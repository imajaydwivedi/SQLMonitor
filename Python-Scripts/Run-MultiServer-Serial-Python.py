import pyodbc
from prettytable import PrettyTable
from prettytable import from_db_cursor
import argparse
from datetime import datetime
import os
from slack_sdk import WebClient

parser = argparse.ArgumentParser(description="Script to execute sql query on multiple SQLServer",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-s", "--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("-d", "--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
inventory_server = args.inventory_server
inventory_database = args.inventory_database

# Get list of servers from Inventory
invCon = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={inventory_server};"
                      f"Database={inventory_database};"
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

disk_result = []
ptable = PrettyTable()
iter_no = 0

for server_row in servers:
    iter_no += 1

    server = server_row.sql_instance
    port = server_row.sql_instance_port
    if port is None:
      port = 1433
    database = server_row.database
    print(f"Working on [{server}].[{database}]..")

    cnxn = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={server},{port};"
                      f"Database={database};"
                      "Trusted_Connection=yes;")
    
    sql_query = f"""
    set nocount on;

    select top 1 [sql_instance] = '{server}', *
    from dbo.disk_space ds
    """

    #print(sql_query)
    cursor = cnxn.cursor()
    cursor.execute(sql_query)

    if iter_no == 1:
      ptable.field_names = [column[0] for column in cursor.description]

    for row in cursor.fetchall():
      disk_result.append(row)
      ptable.add_row(row)
    #print(result)
    cursor.close()
    cnxn.close()

print(disk_result)
print(ptable)


