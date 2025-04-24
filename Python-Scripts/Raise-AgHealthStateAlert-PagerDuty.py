from pagerduty_api import Alert
import pyodbc
from prettytable import PrettyTable
from prettytable import from_db_cursor
import argparse
from datetime import datetime

parser = argparse.ArgumentParser(description="Script to Raise AlwaysOn Availability Group Health Alert",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-s", "--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("-d", "--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("-k", "--service_key", type=str, required=True, action="store", default="afie5a643ff44a04d02b710591a33551", help="Pager Duty API Service Key", )
parser.add_argument("-n", "--alert_name", type=str, required=False, action="store", default="AG Health State Alert", help="PagerDuty Alert Name")
parser.add_argument("-j", "--alert_job_name", type=str, required=False, action="store", default="(dba) Raise-AgHealthStateAlert", help="Script/Job calling this script")
parser.add_argument("-u", "--dashboard_url", type=str, required=False, action="store", default="https://sqlmonitor.ajaydwivedi.com:3000/d/distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m'", help="All Server Dashboard URL")

parser.add_argument("--latency_minutes", type=int, required=False, action="store", default=30, help="Latency in minutes for Alert")
parser.add_argument("--redo_queue_size_gb", type=int, required=False, action="store", default=10, help="Redo Queue size in gb for alert")
parser.add_argument("--log_send_queue_size_gb", type=int, required=False, action="store", default=10, help="Send Queue Size for Alert")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
inventory_server = args.inventory_server
inventory_database = args.inventory_database
service_key = args.service_key
alert_name = args.alert_name
alert_key = f"{alert_name} - {today_str}"
alert_job_name = args.alert_job_name
dashboard_url = args.dashboard_url
latency_minutes = args.latency_minutes
redo_queue_size_gb = args.redo_queue_size_gb
log_send_queue_size_gb = args.log_send_queue_size_gb

# https://pagerduty-api.readthedocs.io/en/develop/ref/pagerduty_api.html
alert = Alert(service_key=service_key)

cnxn = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={inventory_server};"
                      f"Database={inventory_database};"
                      "Trusted_Connection=yes;")


cursor = cnxn.cursor()

sql_get_alert_data = f"""
set nocount on;

declare @_sql nvarchar(max);
declare @_params nvarchar(max);

declare @_latency_minutes int;
declare @_redo_queue_size_gb int;
declare @_log_send_queue_size_gb int;
declare @_filter_out_offline_sqlagent bit = 1;

set @_latency_minutes = {latency_minutes};
set @_redo_queue_size_gb = {redo_queue_size_gb};
set @_log_send_queue_size_gb = {log_send_queue_size_gb};

set @_params = N'@_latency_minutes int, @_redo_queue_size_gb int, @_log_send_queue_size_gb int';

set @_sql = '
if object_id(''tempdb..#replica_servers'') is not null
	drop table #replica_servers
select distinct ahs.replica_server_name
into #replica_servers
from dbo.ag_health_state_all_servers ahs
where 1=1;

select	sql_instance, [___replica__ | *ag_name* | __database_name__] = replica_server_name+'' | ''+ag_name+'' | ''+database_name,
		[sync state | sync health] = synchronization_state_desc + '' | '' + synchronization_health_desc, 
        is_local, latency_seconds, 
		--replica_server = rs.srv_name,
        --log_send_queue_size, redo_queue_size, last_redone_time, log_send_rate, 
        --redo_rate, estimated_redo_completion_time_min, last_commit_time, is_suspended, 
        --suspend_reason_desc, is_distributed, updated_date_utc, 
        collection_time_utc
from dbo.ag_health_state_all_servers ahs
left join (	select replica_server = rs.replica_server_name, srv_name = max(asi.srv_name)
		from #replica_servers rs
		join dbo.vw_all_server_info asi
			on rs.replica_server_name in (asi.machine_name, asi.server_name)
		group by rs.replica_server_name
	) rs
	on rs.replica_server = ahs.replica_server_name
where 1=1
and (	ahs.synchronization_health_desc <> ''HEALTHY''
	or	ahs.synchronization_state_desc not in (''SYNCHRONIZED'',''SYNCHRONIZING'')
	or	(ahs.latency_seconds is not null and ahs.latency_seconds >= @_latency_minutes*60)
	or	(ahs.log_send_queue_size is not null and ahs.log_send_queue_size >= @_log_send_queue_size_gb*1024*1024)
	or	(ahs.redo_queue_size is not null and ahs.redo_queue_size >= @_redo_queue_size_gb*1024*1024)
	)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = ahs.sql_instance)
'+(case when @_filter_out_offline_sqlagent = 0 then '--' else '' end)+'and exists (select 1/0 from dbo.services_all_servers sas where sas.sql_instance = ahs.sql_instance and sas.service_type = ''Agent''	and sas.status_desc = ''Running'');
';

exec sp_executesql @_sql, @_params, @_latency_minutes, @_redo_queue_size_gb, @_log_send_queue_size_gb;
"""
cursor.execute(sql_get_alert_data)

#help(cursor )
mytable = from_db_cursor(cursor)
#help(mytable)

if(len(mytable._rows) > 0):
  print(f"{len(mytable._rows)} issue rows found for '{alert_name}'.")
  #result2print = mytable.get_string(fields=["sql_instance", "replica_database", "ag_name", "is_primary_replica", "ag_listener", "is_local", "synchronization_state_desc", "synchronization_health_desc", "latency_seconds", "collection_time_utc"])
  result2print = mytable.get_string()

  alert.trigger(
      description=alert_key,
      incident_key=alert_key,
      client=alert_job_name,
      client_url=dashboard_url,
      details={"":result2print}
  )
else:
  print(f"No rows found for '{alert_name}'.")


'''
# https://www.analyticsvidhya.com/blog/2024/01/ways-to-convert-python-scripts-to-exe-files/

pip install pyinstaller

PS C:\Windows\system32> cd C:\sqlmonitor\Work\
PS C:\sqlmonitor\Work> pyinstaller.exe --onefile .\Raise-AgHealthStateAlert.py

C:\sqlmonitor\Work\dist\Raise-AgHealthStateAlert.exe
'''