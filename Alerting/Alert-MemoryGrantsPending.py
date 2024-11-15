import pyodbc
import argparse
from datetime import datetime
import os
from SmaAlertPackage.CommonFunctions.get_script_logger import get_script_logger
from SmaAlertPackage.CommonFunctions.connect_dba_instance import connect_dba_instance
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table
from SmaAlertPackage.CustomFunctions.get_memory_grants_pending import get_memory_grants_pending
import SmaAlertPackage.SmaMemoryGrantsPendingAlert as sma

# get Script Name
script_name = os.path.basename(__file__)

parser = argparse.ArgumentParser(description="Script to raise memory grants pending alert", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("--credential_manager_database", type=str, required=False, action="store", default="DBA", help="Credential Manager Database")
parser.add_argument("--login_name", type=str, required=False, action="store", default="sa", help="Login name for sql authentication")
parser.add_argument("--login_password", type=str, required=False, action="store", default="", help="Login password for sql authentication")
parser.add_argument("--alert_name", type=str, required=False, action="store", default="Alert-MemoryGrantsPending", help="Alert Name")
parser.add_argument("--alert_job_name", type=str, required=False, action="store", default="(dba) Alert-MemoryGrantsPending", help="Script/Job calling this script")
parser.add_argument("--alert_owner_team", type=str, required=False, action="store", default="DBA", help="Default team who would own alert")
parser.add_argument("--verbose", type=bool, required=False, action="store", default=False, help="Extra debug message when enabled")
parser.add_argument("--log_file", type=str, required=False, action="store", default="", help="Log file path if logging should be done in files.")

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
    verbose = args.verbose
    log_file = args.log_file

# create logger
if log_file != "":
    logger = get_script_logger(alert_job_name, log_file=log_file)
    if verbose:
        print(f"[{script_name}] => Logging to file '{log_file}'..")
else:
    logger = get_script_logger(alert_job_name)
    if verbose:
        print(f"[{script_name}] => Logging to console..")

# Log begging
logger.info('***** BEGIN:  %s' % script_name)

# Make inventory server connection
logger.info(f"Create db connection using connect_dba_instance..")
cnxn = connect_dba_instance(inventory_server,inventory_database,login_name,login_password,logger=logger,verbose=verbose)
cursor = cnxn.cursor()

# Create SmaAlert object to retrieve defaults
logger.info(f"Create SmaAlert child class object with default values..")
alert_obj = sma.SmaMemoryGrantsPendingAlert()

if 'Retrieve Class Attribute Defaults' == 'Retrieve Class Attribute Defaults':
    frequency_minutes = alert_obj.frequency_minutes
    grants_pending_threshold = alert_obj.grants_pending_threshold
    average_duration_minutes = alert_obj.average_duration_minutes

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
    logger.info(f"grants_pending_threshold = '{grants_pending_threshold}'")
    logger.info(f"average_duration_minutes = '{average_duration_minutes}'")
    logger.info(f"verbose = '{verbose}'")

# Get Alert Raw Data
if 'Get Alert Raw Data' == 'Get Alert Raw Data':
    logger.info(f"Query table dbo.all_server_volatile_info_history..")
    query_params = dict(logger = logger,
                        verbose = verbose,
                        grants_pending_threshold = grants_pending_threshold,
                        average_duration_minutes = average_duration_minutes
                        )
    alert_pyodbc_resultset = get_memory_grants_pending(cnxn, **query_params)

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
    alert_obj.alert_key = alert_key
    alert_obj.alert_owner_team = alert_owner_team
    alert_obj.logger = logger
    alert_obj.verbose = verbose
    alert_obj.alert_job_name = alert_job_name
    alert_obj.sql_connection = cnxn

    # set flag if alert related action is required
    alert_obj.generate_alert = (True if len(alert_pyodbc_resultset)>0 else False)
    alert_obj.alert_pyodbc_resultset = alert_pyodbc_resultset

    # fetch existing alert if any & set flag if alert creation is required
    if alert_obj.initialize_data_from_db():
        logger.info(f"Overwrite variables from db retrieved data..")
        alert_owner_team = alert_obj.alert_owner_team

    logger.info(f"alert_obj.exists = '{alert_obj.exists}'")
    logger.info(f"alert_obj.generate_alert = '{alert_obj.generate_alert}'")
    logger.info(f"alert_obj.action_to_take = '{alert_obj.action_to_take}'")
    logger.info(f"alert_obj.state = '{alert_obj.state}'")

    if alert_obj.action_to_take != 'No Action':
        # compute derived attributes from raw data
        logger.info(f"calling alert_obj.initialize_derived_attributes()..")
        alert_obj.initialize_derived_attributes()

        # Take required action now
        logger.info(f"calling alert_obj.take_required_action()..")
        alert_obj.take_required_action()

# Log end
logger.info('***** COMPLETED:  %s' % script_name)


'''
Logging in Python
    https://docs.python.org/3/howto/logging.html

Pyodbc named parameter binding
    https://www.ckhang.com/blog/2019/pyodbc-named-parameter-binding/
'''

