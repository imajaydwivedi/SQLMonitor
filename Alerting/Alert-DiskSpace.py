import pyodbc
from prettytable import PrettyTable
from prettytable import from_db_cursor
import argparse
from datetime import datetime
import os
from get_script_logger import get_script_logger
from connect_dba_instance import connect_dba_instance

# get Script Name
script_name = os.path.basename(__file__)

parser = argparse.ArgumentParser(description="Script to raise disk space alert", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("--credential_manager_database", type=str, required=False, action="store", default="DBA", help="Credential Manager Database")
parser.add_argument("--login_name", type=str, required=False, action="store", default="sa", help="Login name for sql authentication")
parser.add_argument("--login_password", type=str, required=False, action="store", default="", help="Login password for sql authentication")
parser.add_argument("--alert_name", type=str, required=False, action="store", default="Alert-DiskSpace", help="Alert Name")
parser.add_argument("--alert_job_name", type=str, required=False, action="store", default="(dba) Alert-DiskSpace", help="Script/Job calling this script")

parser.add_argument("--disk_warning_pct", type=float, required=False, action="store", default=65, help="Disk Warning Threshold %")
parser.add_argument("--disk_critical_pct", type=float, required=False, action="store", default=85, help="Disk Critical Threshold %")
parser.add_argument("--disk_threshold_gb", type=float, required=False, action="store", default=250, help="Large disk threshold gb")
parser.add_argument("--large_disk_threshold_pct", type=float, required=False, action="store", default=95, help="Large disk used %")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
inventory_server = args.inventory_server
inventory_database = args.inventory_database
credential_manager_database = args.credential_manager_database
login_name = args.login_name
login_password = args.login_password
alert_name = args.alert_name
alert_job_name = args.alert_job_name
disk_warning_pct = args.disk_warning_pct
disk_critical_pct = args.disk_critical_pct
disk_threshold_gb = args.disk_threshold_gb
large_disk_threshold_pct = args.large_disk_threshold_pct

# create logger
logger = get_script_logger(alert_job_name)

# Log begging
logger.info('***** BEGIN:  %s' % script_name)

# Print variables values
logger.info('Printing parameter values..')
logger.info(f"inventory_server = '{inventory_server}'")
logger.info(f"inventory_database = '{inventory_database}'")
logger.info(f"credential_manager_database = '{credential_manager_database}'")
logger.info(f"login_name = '{login_name}'")
logger.info(f"inventory_database = '{inventory_database}'")
logger.info(f"alert_name = '{alert_name}'")
logger.info(f"alert_job_name = '{alert_job_name}'")
logger.info(f"disk_warning_pct = '{disk_warning_pct}'")
logger.info(f"disk_critical_pct = '{disk_critical_pct}'")
logger.info(f"disk_threshold_gb = '{disk_threshold_gb}'")
logger.info(f"large_disk_threshold_pct = '{large_disk_threshold_pct}'")

# Make inventory server connection
logger.info(f"Create db connection using connect_dba_instance..")
cnxn = connect_dba_instance(inventory_server,inventory_database,login_name,login_password)
cursor = cnxn.cursor()

logger.info(f"Execute sql query..")
SQL_QUERY = 'select @@servername as [srv_name]'
cursor.execute(SQL_QUERY)

records = cursor.fetchall()
logger.info(f"Process query result..")
for r in records:
    print(r)

# Log end
logger.info('***** COMPLETED:  %s' % script_name)


'''
Logging in Python
    https://docs.python.org/3/howto/logging.html
'''

