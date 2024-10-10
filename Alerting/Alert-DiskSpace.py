import pyodbc
import argparse
from datetime import datetime
import os
from get_script_logger import get_script_logger
from connect_dba_instance import connect_dba_instance
from get_pandas_dataframe import get_pandas_dataframe
from get_pretty_table import get_pretty_table
from get_sma_params import get_sma_params
from get_disk_space import get_disk_space
from get_oncall_teams import get_oncall_teams

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

parser.add_argument("--disk_warning_pct", type=float, required=False, action="store", default=65, help="Disk Warning Threshold %")
parser.add_argument("--disk_critical_pct", type=float, required=False, action="store", default=85, help="Disk Critical Threshold %")
parser.add_argument("--disk_threshold_gb", type=float, required=False, action="store", default=250, help="Large disk threshold gb")
parser.add_argument("--large_disk_threshold_pct", type=float, required=False, action="store", default=95, help="Large disk used %")

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
    disk_warning_pct = args.disk_warning_pct
    disk_critical_pct = args.disk_critical_pct
    disk_threshold_gb = args.disk_threshold_gb
    large_disk_threshold_pct = args.large_disk_threshold_pct

if 'Initiate Local Variables' == 'Initiate Local Variables':
    dba_slack_channel_id = ''

# create logger
logger = get_script_logger(alert_job_name)

# Log begging
logger.info('***** BEGIN:  %s' % script_name)

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
    logger.info(f"disk_warning_pct = '{disk_warning_pct}'")
    logger.info(f"disk_critical_pct = '{disk_critical_pct}'")
    logger.info(f"disk_threshold_gb = '{disk_threshold_gb}'")
    logger.info(f"large_disk_threshold_pct = '{large_disk_threshold_pct}'")

# Make inventory server connection
logger.info(f"Create db connection using connect_dba_instance..")
cnxn = connect_dba_instance(inventory_server,inventory_database,login_name,login_password)
cursor = cnxn.cursor()

# Get DBA Params
if 'Get DBA Params' == 'Get DBA Params':
    logger.info(f"Query table dbo.sma_params..")
    sma_params_records = get_sma_params(sql_connection=cnxn, param_key='dba_slack_channel_id')

    #logger.info(f"get PrettyTable..")
    pt = get_pretty_table(sma_params_records)
    #logger.info(f"get pandas dataframe..")
    #df = get_pandas_dataframe(sma_params_records, index_col='param_key')

    # Extract dynamic parameters from inventory
    #logger.info(f"Get parameters from dbo.sma_params..")
    #dba_slack_channel_id = df[df.param_key=='dba_slack_channel_id'].iloc[0]['param_value']
    #dba_slack_channel_id = df.loc['dba_slack_channel_id','param_value']
    #dba_slack_channel_id = df.at['dba_slack_channel_id','param_value']

    #logger.info(f"dba_slack_channel_id = '{dba_slack_channel_id}'")

    #print(pt)
    #print(df)
    #print(f'dba_slack_channel_id => {dba_slack_channel_id}')

# Get Alert Owner Team Details
if 'Get Alert Owner Team Details' == 'Get Alert Owner Team Details':
    logger.info(f"Query table dbo.sma_oncall_teams..")
    oncall_teams_records = get_oncall_teams(sql_connection=cnxn, team_name='DBA')

    #logger.info(f"get PrettyTable..")
    pt = get_pretty_table(oncall_teams_records)
    #logger.info(f"get pandas dataframe..")
    df = get_pandas_dataframe(oncall_teams_records, index_col='team_name')

    # Extract dynamic parameters from inventory
    #logger.info(f"Get parameters from dbo.sma_params..")
    #dba_slack_channel_id = df[df.param_key=='dba_slack_channel_id'].iloc[0]['param_value']
    #dba_slack_channel_id = df.loc['dba_slack_channel_id','param_value']
    oncall_team_slack_channel_id = df.at[alert_owner_team,'team_slack_channel']

    logger.info(f"oncall_team_slack_channel_id = '{oncall_team_slack_channel_id}'")

    print(pt)
    #print(df)

# Get Disk Space Info
if 'Get Disk Space Info' == 'Get Disk Space Info':
    logger.info(f"Query table dbo.disk_space_all_servers..")
    alert_data = get_disk_space(cnxn, disk_warning_pct=disk_warning_pct, disk_critical_pct=disk_critical_pct, disk_threshold_gb=disk_threshold_gb, large_disk_threshold_pct=large_disk_threshold_pct)

    #logger.info(f"get PrettyTable for alert_data..")
    pt = get_pretty_table(alert_data)
    #logger.info(f"get pandas dataframe for alert_data..")
    df = get_pandas_dataframe(alert_data)

    logger.info(f"Alert data..")
    print(pt)


#if(len(mytable._rows) > 0):
  #print(f"{len(mytable._rows)} issue rows found for '{alert_name}'.")

# Log end
logger.info('***** COMPLETED:  %s' % script_name)


'''
Logging in Python
    https://docs.python.org/3/howto/logging.html
'''

