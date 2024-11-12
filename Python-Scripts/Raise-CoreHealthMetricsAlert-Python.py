from pagerduty_api import Alert
import pyodbc
from prettytable import PrettyTable
from prettytable import from_db_cursor
import argparse
from datetime import datetime
import os
from slack_sdk import WebClient

parser = argparse.ArgumentParser(description="Script to Raise Alert for SQLMonitor Core Health Metrics",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-s", "--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("-d", "--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("-c", "--credential_manager_database", type=str, required=False, action="store", default="DBA", help="Credential Manager Database")
parser.add_argument("-t", "--slack_token", type=str, required=False, action="store", default="some-dummy-slack-token-here", help="API Bot Token", )
parser.add_argument("--slack_channel", type=str, required=False, action="store", default="sqlmonitor-alerts", help="Slack Channel Name", )
parser.add_argument("--slack_bot", type=str, required=False, action="store", default="SQLMonitor", help="Slack Bot name", )
parser.add_argument("-n", "--alert_name", type=str, required=False, action="store", default="Core Health Metrics Alert", help="Alert Name")
parser.add_argument("-j", "--alert_job_name", type=str, required=False, action="store", default="(dba) Raise-CoreHealthMetricsAlert", help="Script/Job calling this script")
parser.add_argument("-u", "--dashboard_url", type=str, required=False, action="store", default="https://sqlmonitor.ajaydwivedi.com:3000/d/distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m'", help="All Server Dashboard URL")

parser.add_argument("--latency_minutes", type=int, required=False, action="store", default=30, help="Latency in minutes for Alert")
parser.add_argument("--redo_queue_size_gb", type=int, required=False, action="store", default=10, help="Redo Queue size in gb for alert")
parser.add_argument("--log_send_queue_size_gb", type=int, required=False, action="store", default=10, help="Send Queue Size for Alert")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
inventory_server = args.inventory_server
inventory_database = args.inventory_database
alert_name = args.alert_name
alert_key = f"{alert_name} - {today_str}"
alert_job_name = args.alert_job_name
dashboard_url = args.dashboard_url
latency_minutes = args.latency_minutes
redo_queue_size_gb = args.redo_queue_size_gb
log_send_queue_size_gb = args.log_send_queue_size_gb
slack_token = args.slack_token
slack_channel = args.slack_channel
slack_bot = args.slack_bot

# Retrieve Slack Token from Environment variables if not provided
if slack_token:
  print ("Slack token provided.")
else:
  print ("Slack token not provided. Checking environment variables..")
  slack_token = os.environ["SLACK_TOKEN"]
  print(slack_token)

# https://pagerduty-api.readthedocs.io/en/develop/ref/pagerduty_api.html
# https://slack.dev/python-slack-sdk/
# https://www.datacamp.com/tutorial/how-to-send-slack-messages-with-python
# https://slack.dev/python-slack-sdk/web/index.html#messaging

# Set up a WebClient with the Slack OAuth token
client = WebClient(token=slack_token)

cnxn = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={inventory_server};"
                      f"Database={inventory_database};"
                      "Trusted_Connection=yes;")


cursor = cnxn.cursor()

sql_get_alert_data = f"""
declare @os_cpu_threshold decimal(20,2) = 70;
declare @sql_cpu_threshold decimal(20,2) = 65;
declare @blocked_counts_threshold int = 1;
declare @blocked_duration_max_seconds_threshold bigint = 60;
declare @available_physical_memory_kb_threshold bigint = (4*1024*1024);
declare @system_high_memory_signal_state_threshold varchar(20) = 'Low';
--declare @physical_memory_in_use_kb_threshold decimal(20,2);
declare @memory_grants_pending_threshold int = 1;
declare @connection_count_threshold int = 1000;
declare @waits_per_core_per_minute_threshold decimal(20,2) = 180;

declare @sql nvarchar(max);
declare @params nvarchar(max);

set @params = N'@os_cpu_threshold decimal(20,2), @sql_cpu_threshold decimal(20,2), @blocked_counts_threshold int, 
				@blocked_duration_max_seconds_threshold bigint, @available_physical_memory_kb_threshold bigint, 
				@system_high_memory_signal_state_threshold varchar(20), @memory_grants_pending_threshold int, 
				@connection_count_threshold int, @waits_per_core_per_minute_threshold decimal(20,2)';

set quoted_identifier off;
set @sql = "
;with t_cte as (
	select	srv_name, os_cpu, sql_cpu, blocked_counts, blocked_duration_max_seconds, available_physical_memory_kb, system_high_memory_signal_state, physical_memory_in_use_kb, memory_grants_pending, connection_count, waits_per_core_per_minute
	from dbo.vw_all_server_info
)
select  *
from t_cte cte
where 1=1
and (   os_cpu >= @os_cpu_threshold
    or  sql_cpu >= @sql_cpu_threshold 
    or  blocked_counts >= @blocked_counts_threshold
    or  blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold
    or  ( available_physical_memory_kb < @available_physical_memory_kb_threshold and system_high_memory_signal_state = @system_high_memory_signal_state_threshold )
    or  memory_grants_pending > @memory_grants_pending_threshold
    or  connection_count >= @connection_count_threshold
    or  waits_per_core_per_minute > @waits_per_core_per_minute_threshold
)
";
set quoted_identifier off;

--print @sql
exec dbo.sp_executesql @sql, @params, @os_cpu_threshold, @sql_cpu_threshold, @blocked_counts_threshold, @blocked_duration_max_seconds_threshold, @available_physical_memory_kb_threshold, @system_high_memory_signal_state_threshold, @memory_grants_pending_threshold, @connection_count_threshold, @waits_per_core_per_minute_threshold;
"""
cursor.execute(sql_get_alert_data)

#help(cursor )
mytable = from_db_cursor(cursor)
#help(mytable)

if(len(mytable._rows) > 0):
  print(f"{len(mytable._rows)} issue rows found for '{alert_name}'.")
  #result2print = mytable.get_string(fields=["sql_instance", "replica_database", "ag_name", "is_primary_replica", "ag_listener", "is_local", "synchronization_state_desc", "synchronization_health_desc", "latency_seconds", "collection_time_utc"])
  result2print = mytable.get_string()

  # Send a message
  client.chat_postMessage(
      channel=slack_channel, 
      text=result2print, 
      username=slack_bot
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