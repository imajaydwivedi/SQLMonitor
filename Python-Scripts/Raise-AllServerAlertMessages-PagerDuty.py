from pagerduty_api import Alert
import pyodbc
from prettytable import PrettyTable
from prettytable import from_db_cursor
import argparse
from datetime import datetime

parser = argparse.ArgumentParser(description="Script to Raise Alert for Error Messages",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-s", "--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("-d", "--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("-k", "--service_key", type=str, required=False, action="store", default="afie5a643ff44a04d02b710591a33551", help="Pager Duty API Service Key", )
parser.add_argument("-j", "--alert_job_name", type=str, required=False, action="store", default="(dba) Raise-AllServerAlertMessages", help="Script/Job calling this script")
parser.add_argument("-u", "--dashboard_url", type=str, required=False, action="store", default="https://sqlmonitor.ajaydwivedi.com:3000/d/distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m'", help="All Server Dashboard URL")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
inventory_server = args.inventory_server
inventory_database = args.inventory_database
service_key = args.service_key
alert_job_name = args.alert_job_name
dashboard_url = args.dashboard_url

# https://pagerduty-api.readthedocs.io/en/develop/ref/pagerduty_api.html
alert = Alert(service_key=service_key)


cnxn = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={inventory_server};"
                      f"Database={inventory_database};"
                      "Trusted_Connection=yes;")


cursor = cnxn.cursor()

sql_get_alert_data = f"""
set nocount on;

declare @_last_updated_time_utc datetime2;
declare @_sql nvarchar(max);
declare @_params nvarchar(max);

select @_last_updated_time_utc = updated_time_utc 
from dbo.alert_history_all_servers_last_actioned;

if @_last_updated_time_utc is null
  set @_last_updated_time_utc = DATEADD(minute,-120,sysutcdatetime());

set @_params = N'@_last_updated_time_utc datetime2';
set @_sql = N'
if object_id(''tempdb..#alert_history_all_servers'') is not null
  drop table #alert_history_all_servers;
select	ahas.sql_instance, 
      [category] = ag.category + coalesce(''-''+ag.sub_category,''''),
      [start_time] = min(ahas.collection_time_utc),
      [end_time] = max(ahas.collection_time_utc),
      [error_count] = count(*),
      [max_updated_time_utc] = convert(varchar,max(updated_time_utc),121)
      /* ahas.collection_time_utc, ahas.sql_instance, ahas.server_name, ahas.database_name,
      ahas.error_number, ahas.error_severity, ahas.error_message, ahas.host_instance, 
      ahas.updated_time_utc, ag.category, ag.sub_category, ag.alert_name,
      ag.remarks */
into #alert_history_all_servers
from [dbo].[alert_history_all_servers] ahas
join dbo.alert_categories ag
  on exists (select ag.error_number intersect select ahas.error_number)
where ahas.updated_time_utc > @_last_updated_time_utc
group by ahas.sql_instance, ag.category, ag.sub_category;

select ah.sql_instance, ah.category, ah.start_time, ah.end_time, 
  ah.error_count, max_updated_time_utc = max(ah.max_updated_time_utc) over ()
from #alert_history_all_servers ah;
';

--print @_sql;
exec sp_executesql @_sql, @_params, @_last_updated_time_utc;
"""

cursor.execute(sql_get_alert_data)
all_rows = cursor.fetchall()

row_count = len(all_rows)

if row_count > 0:
  print(f"{row_count} category issues rows found for alerting.")

  last_updated_time_utc = all_rows[0].max_updated_time_utc
  print(f"Latest updated time: {last_updated_time_utc}")

  for row in all_rows:
    sql_instance = row.sql_instance
    category = row.category
    start_time = row.start_time
    end_time = row.end_time
    error_count = row.error_count
    
    alert_details = f"Alerts triggred for category [{category}] on server {[sql_instance]} between {start_time} UTC to {end_time} UTC. \nA total of {error_count} errors received."

    alert_key = f"Alert - [{sql_instance}] - Category [{category}] - {today_str}"

    print('*****************************************************************')
    print(alert_key)
    print(alert_details)
    print('*****************************************************************')

    alert.trigger(
        description=alert_key,
        incident_key=alert_key,
        client=alert_job_name,
        client_url=dashboard_url,
        details=alert_details
    )

  print(f"Alerts sent.")

  print(f"Update dbo.alert_history_all_servers_last_actioned with updated_time_utc = {last_updated_time_utc}.")

  sql_update_inventory_table = f"""
  declare @updated_time_utc datetime2;
  set @updated_time_utc = ?;

  update dbo.alert_history_all_servers_last_actioned
  set updated_time_utc = @updated_time_utc;

  if @@ROWCOUNT = 0 
    insert dbo.alert_history_all_servers_last_actioned values (@updated_time_utc);
  """

  cursor.execute(sql_update_inventory_table, last_updated_time_utc)
  cnxn.commit()

  cursor.close()
  cnxn.close()

else:
  print(f"no rows found for alerting.")


