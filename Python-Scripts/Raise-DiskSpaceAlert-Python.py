from pagerduty_api import Alert
import pyodbc
from prettytable import PrettyTable
from prettytable import from_db_cursor
import argparse
from datetime import datetime

parser = argparse.ArgumentParser(description="Script to Raise Disk Space Alert",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-s", "--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("-d", "--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("-k", "--service_key", type=str, required=True, action="store", default="afie5a643ff44a04d02b710591a33551", help="Pager Duty API Service Key", )
parser.add_argument("-n", "--alert_name", type=str, required=False, action="store", default="Disk Space Issue", help="PagerDuty Alert Name")
parser.add_argument("-j", "--alert_job_name", type=str, required=False, action="store", default="(dba) Raise-DiskSpaceAlert", help="Script/Job calling this script")
parser.add_argument("-u", "--dashboard_url", type=str, required=False, action="store", default="https://sqlmonitor.ajaydwivedi.com:3000/d/distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m'", help="All Server Dashboard URL")

parser.add_argument("--disk_used_warning_percentage", type=int, required=False, action="store", default=80, help="Percentage Used for Warning Alert")
parser.add_argument("--disk_used_warning_gb", type=int, required=False, action="store", default=200, help="Used gb size for alert")
parser.add_argument("--disk_used_critical_percentage", type=int, required=False, action="store", default=95, help="Percentage Used for Warning Alert")

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
disk_used_warning_percentage = args.disk_used_warning_percentage
disk_used_warning_gb = args.disk_used_warning_gb
disk_used_critical_percentage = args.disk_used_critical_percentage

# https://pagerduty-api.readthedocs.io/en/develop/ref/pagerduty_api.html
alert = Alert(service_key=service_key)


cnxn = pyodbc.connect("Driver={SQL Server Native Client 11.0};"
                      f"Server={inventory_server};"
                      f"Database={inventory_database};"
                      "Trusted_Connection=yes;")


cursor = cnxn.cursor()
sql_get_alert_data = f"""
select	ds.sql_instance, disk_drive = ds.host_name + ' (' + ds.disk_volume + ')', 
        [state] = case when (ds.free_mb*100.0/ds.capacity_mb) < 10.0 then 'Critical' else 'Warning' end,
        state_desc = convert(varchar,ds.free_mb) + ' mb ('+convert(varchar,convert(numeric(20,2),ds.free_mb*100.0/ds.capacity_mb))+' %) free of ' + convert(varchar,ds.capacity_mb) + ' mb'
from dbo.disk_space_all_servers ds
where ds.updated_date_utc >= dateadd(minute,-60,getutcdate())
and (	(	(ds.free_mb*100.0/ds.capacity_mb) < (100.0-{disk_used_warning_percentage}) -- free %
			and ds.free_mb < ({disk_used_warning_gb}*1024) -- 200 gb
	  	)
		or ( (ds.free_mb*100.0/ds.capacity_mb) < (100.0-{disk_used_critical_percentage}) -- free %
			)
		);
"""
cursor.execute(sql_get_alert_data)

#help(cursor )
mytable = from_db_cursor(cursor)
#help(mytable)

if(len(mytable._rows) > 0):
  print(f"{len(mytable._rows)} issue rows found for '{alert_name}'.")
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

PS C:\Windows\system32> cd C:\sqlmonitor\Work
PS C:\sqlmonitor\Work> pyinstaller.exe --onefile .\Raise-AgHealthStateAlert.py

C:\sqlmonitor\Work\dist\Raise-AgHealthStateAlert.exe 
'''