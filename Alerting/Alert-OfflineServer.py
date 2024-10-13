import pyodbc
import argparse
from datetime import datetime
import os
from SmaAlertPackage.CommonFunctions.get_script_logger import get_script_logger
from SmaAlertPackage.CommonFunctions.connect_dba_instance import connect_dba_instance
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table
from SmaAlertPackage.CustomFunctions.get_disk_space import get_disk_space
import SmaAlertPackage.SmaDiskSpaceAlert as sma

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
parser.add_argument("--alert_owner_team", type=str, required=False, action="store", default="DBA", help="Default team who would own alert")
#parser.add_argument("--frequency_minutes", type=int, required=False, action="store", default=30, help="Time gap between next execution for same alert")
parser.add_argument("--verbose", type=bool, required=False, action="store", default=False, help="Extra debug message when enabled")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')

if 'Retrieve Parameters' == 'Retrieve Parameters':
    inventory_server = args.inventory_server
    inventory_database = args.inventory_database
    credential_manager_database = args.credential_manager_database
    login_name = args.login_name
    login_password = args.login_password
    alert_name = args.alert_name
    alert_job_name = args.alert_job_name
    alert_owner_team = args.alert_owner_team
    #frequency_minutes = args.frequency_minutes
    verbose = args.verbose

# create logger
logger = get_script_logger(alert_job_name)

# Log begging
logger.info('***** BEGIN:  %s' % script_name)

# Make inventory server connection
logger.info(f"Create db connection using connect_dba_instance..")
cnxn = connect_dba_instance(inventory_server,inventory_database,login_name,login_password)
cursor = cnxn.cursor()

# Create SmaDiskSpaceAlert object to retrieve defaults
logger.info(f"Create SmaDiskSpaceAlert class object with default values..")
disk_alert = sma.SmaDiskSpaceAlert()

if 'Retrieve Class Attribute Defaults' == 'Retrieve Class Attribute Defaults':
    disk_warning_pct = disk_alert.disk_warning_pct
    disk_critical_pct = disk_alert.disk_critical_pct
    disk_threshold_gb = disk_alert.disk_threshold_gb
    large_disk_threshold_pct = disk_alert.large_disk_threshold_pct
    frequency_minutes = disk_alert.frequency_minutes

# Print variables values
if 'Print Variables' == 'Print Variables':
    logger.info('Printing parameter values..')
    logger.info(f"inventory_server = '{inventory_server}'")
    logger.info(f"inventory_database = '{inventory_database}'")
    logger.info(f"credential_manager_database = '{credential_manager_database}'")
    logger.info(f"login_name = '{login_name}'")
    logger.info(f"inventory_database = '{inventory_database}'")
    logger.info(f"alert_name = '{alert_name}'")
    logger.info(f"alert_job_name = '{alert_job_name}'")
    logger.info(f"alert_owner_team = '{alert_owner_team}'")
    logger.info(f"frequency_minutes = '{frequency_minutes}'")
    logger.info(f"disk_warning_pct = '{disk_warning_pct}'")
    logger.info(f"disk_critical_pct = '{disk_critical_pct}'")
    logger.info(f"disk_threshold_gb = '{disk_threshold_gb}'")
    logger.info(f"large_disk_threshold_pct = '{large_disk_threshold_pct}'")
    logger.info(f"verbose = '{verbose}'")

# Get Disk Space Info
if 'Get Disk Space Info' == 'Get Disk Space Info':
    logger.info(f"Query table dbo.disk_space_all_servers..")
    query_params = dict(disk_warning_pct=disk_warning_pct,
                        disk_critical_pct=disk_critical_pct,
                        disk_threshold_gb=disk_threshold_gb,
                        large_disk_threshold_pct=large_disk_threshold_pct
                        )
    alert_pyodbc_resultset = get_disk_space(cnxn, **query_params)

    if len(alert_pyodbc_resultset) > 0:
        logger.info(f"Before creating pt & df on alert_pyodbc_resultset..")
        pt_alert_pyodbc_resultset = get_pretty_table(alert_pyodbc_resultset)
        df_alert_pyodbc_resultset = get_pandas_dataframe(alert_pyodbc_resultset)

        if verbose:
            logger.info(f"Alert data..")
            print(pt_alert_pyodbc_resultset)

# Generate Alert & Notify
if 'Generate Alert & Notify' == 'Generate Alert & Notify':
    alert_key = f"{alert_name}"
    disk_alert.alert_key = alert_key
    disk_alert.alert_owner_team = alert_owner_team
    disk_alert.logger = logger
    disk_alert.verbose = verbose
    disk_alert.alert_job_name = alert_job_name
    disk_alert.sql_connection = cnxn

    # set flag if alert related action is required
    disk_alert.generate_alert = (True if len(alert_pyodbc_resultset)>0 else False)
    disk_alert.alert_pyodbc_resultset = alert_pyodbc_resultset

    # fetch existing alert if any & set flag if alert creation is required
    if disk_alert.initialize_data_from_db():
        logger.info(f"Overwrite variables from db retrieved data..")
        alert_owner_team = disk_alert.alert_owner_team

    logger.info(f"disk_alert.exists = '{disk_alert.exists}'")
    logger.info(f"disk_alert.generate_alert = '{disk_alert.generate_alert}'")
    logger.info(f"disk_alert.action_to_take = '{disk_alert.action_to_take}'")
    logger.info(f"disk_alert.state = '{disk_alert.state}'")

    if disk_alert.action_to_take != 'No Action':
        # compute derived attributes from raw data
        disk_alert.initialize_derived_attributes()

        # Take required action now
        disk_alert.take_required_action()

# Log end
logger.info('***** COMPLETED:  %s' % script_name)


'''
Logging in Python
    https://docs.python.org/3/howto/logging.html

Pyodbc named parameter binding
    https://www.ckhang.com/blog/2019/pyodbc-named-parameter-binding/
'''

