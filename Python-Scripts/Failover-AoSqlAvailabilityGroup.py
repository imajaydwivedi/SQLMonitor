import pyodbc
import argparse
from datetime import datetime
import os
import sys
import time

# Retrieve sma package path
current_directory = os.getcwd()
    # sma_package_path = "/Users/ajay.dwivedi/Documents/Github/SQLMonitor/Alerting"
sma_package_env = "SMA_PACKAGE_PATH"
sma_package_path = os.environ.get(sma_package_env)

# Add sma path to modules path
if sma_package_path:
    normalized_path = os.path.normpath(os.path.abspath(sma_package_path))
    sys.path.insert(0, normalized_path)
else:
    # Handle the case where the environment variable is not set
    raise Exception(f"Environment variable '{sma_package_env}' is not set. Skipping path addition.")

from SmaAlertPackage.CommonFunctions.connect_dba_instance import connect_dba_instance
from SmaAlertPackage.CommonFunctions.send_slack_incremental_notification import send_slack_incremental_notification
from SmaAlertPackage.AlertClasses.SmaAlert import SmaAlert
from SmaAlertPackage.CommonFunctions.get_script_logger import get_script_logger
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table

# get Script Name
script_name = os.path.basename(__file__)

parser = argparse.ArgumentParser(description="Script to perform sql server availability group failover", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-s", "--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("-d", "--inventory_database", type=str, required=False, action="store", default="DBA_Admin", help="Inventory Database")
parser.add_argument("--sql_instance", type=str, required=True, action="store", default="localhost", help="SqlInstance to become new Primary Replica")
parser.add_argument("--sql_instance_port", type=int, required=False, action="store", default=1433, help="SqlInstance Port")
parser.add_argument("--availability_group", type=str, required=True, action="store", default="SharePoint", help="Availability Group Name")
# parser.add_argument("--force", type=bool, required=False, action="store", default=False, help="Performs a forced failover that allows potential data loss by not waiting for transaction synchronization.")
parser.add_argument("--force", action="store_true", help="Performs a forced failover that allows potential data loss by not waiting for transaction synchronization.")
parser.add_argument("--login_name", type=str, required=False, action="store", default="sa", help="Login name for sql authentication")
# parser.add_argument("--verbose", type=bool, required=False, action="store", default=False, help="Extra debug message when enabled")
parser.add_argument("--verbose", action="store_true", help="Extra debug message when enabled")
parser.add_argument("--app_name", type=str, required=False, action="store", default="Failover-AoSqlAvailabilityGroup.py", help="App name used for Database Connection")
parser.add_argument("--alert_job_name", type=str, required=False, action="store", default="Failover-AoSqlAvailabilityGroup", help="Script display name for Notifications")
parser.add_argument("--log_file", type=str, required=False, action="store", default="", help="Log file path if logging should be done in files.")
parser.add_argument("--slack_token", type=str, required=False, action="store", default="", help="Slack Token for Sending Slack Alert")
parser.add_argument("--slack_channel", type=str, required=False, action="store", default="", help="Slack Channel ID for Sending Slack Alert")
parser.add_argument("--slack_bot", type=str, required=False, action="store", default="db-alerts", help="Slack bot name for Sending Slack Alert")
parser.add_argument("--post_failover_delay_seconds", type=int, required=False, action="store", default=5, help="Time delay in seconds to introduce after failover to give enough time for databases to recover")
parser.add_argument("--post_resume_delay_seconds", type=int, required=False, action="store", default=10, help="Time delay in seconds to introduce after resuming data movement to give enough time for databases to recover")

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
failover_event_occurred = False
data_movement_event_occurred = False

if 'Retrieve Parameters' == 'Retrieve Parameters':
    inventory_server = args.inventory_server
    inventory_database = args.inventory_database
    sql_instance = args.sql_instance
    sql_instance_port = args.sql_instance_port
    availability_group = args.availability_group
    force = args.force
    login_name = args.login_name
    login_password = os.environ.get(login_name)
    slack_token = args.slack_token
    slack_channel = args.slack_channel
    slack_bot = args.slack_bot
    app_name = args.app_name
    verbose = args.verbose
    alert_job_name = args.alert_job_name
    log_file = args.log_file
    post_failover_delay_seconds = args.post_failover_delay_seconds
    post_resume_delay_seconds = args.post_resume_delay_seconds

# create logger
if log_file != "":
    logger = get_script_logger(alert_job_name, log_file=log_file)
    if verbose:
        print(f"[{script_name}] => Logging to file '{log_file}'..")
else:
    logger = get_script_logger(alert_job_name)
    if verbose:
        print(f"[{script_name}] => Logging to console..")

slack_notification_required = False
if slack_token != "" and slack_channel != "":
    slack_notification_required = True

# Log begging
logger.info('***** BEGIN:  %s' % script_name)
if slack_notification_required:
    thread_header = f""":fire: *{alert_job_name}*
>*sql_instance*: {sql_instance},{sql_instance_port} || *availability_group*: {availability_group}
    """
    slack_ts_value = send_slack_incremental_notification(slack_token, slack_channel, thread_header, thread_messages=None, slack_ts_value=None, logger=logger, verbose=verbose)
    logger.info(f"slack_ts_value = {slack_ts_value}")

if 'Get New Primary Connection' == 'Get New Primary Connection':
    logger.info(f"Create new primary server connection using connect_dba_instance..")
    cnxn_srv_pri = connect_dba_instance(f"{sql_instance},{sql_instance_port}",'master',login_name,login_password,logger=logger,verbose=False)
    cursor_srv_pri = cnxn_srv_pri.cursor()

if 'Get Inventory Connection' == 'Get Inventory Connection':
    logger.info(f"Create inventory server connection using connect_dba_instance..")
    cnxn_inv = connect_dba_instance(inventory_server,inventory_database,login_name,login_password,logger=logger,verbose=False)
    cursor_inv = cnxn_inv.cursor()

# Get current "sql_instance" role in availability group
if 'Get-Ag-Replica-Role' == 'Get-Ag-Replica-Role':
    logger.info(f"Get role of sql_instance [{sql_instance}] in ag..")

    sql_is_primary_replica = f"""
if exists (select * from sys.dm_hadr_availability_replica_states where is_local = 1 and role = 1)
    select [is_primary] = cast(1 as bit);
else
    select [is_primary] = cast(0 as bit);
"""
    cursor_srv_pri.execute(sql_is_primary_replica)
    is_primary_replica = cursor_srv_pri.fetchall()[0][0]
    is_secondary_replica = not is_primary_replica
    # rs_get_replica_role = get_pretty_table(cursor_srv_pri.fetchall())

    if verbose:
        logger.info(f"is_primary_replica => {is_primary_replica}")
        # print(rs_get_replica_role)

if is_secondary_replica:
    thread_messages = f"[{sql_instance}] is NOT primary replica. So proceed for failover.."
else:
    thread_messages = f"[{sql_instance}] is already primary replica. So skipping failover.."
logger.info(thread_messages)
if slack_notification_required:
    slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

if is_secondary_replica and 'Perform Failover' == 'Perform Failover':
    sql_failover_ag = f"""
ALTER AVAILABILITY GROUP [{availability_group}]
    {'' if force else '--'}FORCE_FAILOVER_ALLOW_DATA_LOSS;
    {'--' if force else ''}FAILOVER;

select [is_successful] = cast(1 as bit);
"""
    if verbose:
        print(f"sql_failover_ag => \n{sql_failover_ag}")

    try:
        cursor_srv_pri.execute(sql_failover_ag)
        rs_failover_ag = cursor_srv_pri.fetchone()[0]
        cnxn_srv_pri.commit()

        if rs_failover_ag:
            failover_event_occurred = True
            thread_messages = f"Failover is initiated.."
            logger.info(thread_messages)
            if slack_notification_required:
                slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

            if post_failover_delay_seconds > 0:
                thread_messages = f"Wait for {post_failover_delay_seconds} seconds so that databases can recover post failover.."
                logger.info(thread_messages)
                if slack_notification_required:
                    slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
                # Pause the execution for post_failover_delay_seconds
                time.sleep(post_failover_delay_seconds)

    except pyodbc.ProgrammingError as e:
        exception_name = type(e).__name__
        logger.error(f"[{exception_name}] Exception occurred: \n{e}\n\n")
        thread_messages = f"[{exception_name}] Exception occurred: \n{e}\n\n"
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
        raise e
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"[{exception_name}] Exception occurred: \n{e}\n\n")
        thread_messages = f"[{exception_name}] Exception occurred: \n{e}\n\n"
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
        raise e


if 'Get Ag Databases' == 'Get Ag Databases':
    logger.info(f"Proceed to get ag database(s)..")

    sql_get_ag_databases = f"""
set nocount on;

if object_id('tempdb..#availability_databases') is not null
	drop table #availability_databases;

select	ar.replica_server_name,
		drs.is_primary_replica,
		adc.database_name,
		ag.name AS ag_name,
		drs.is_local,
		drs.synchronization_state_desc,
		drs.synchronization_health_desc,
		last_redone_time_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), drs.last_redone_time),
		drs.log_send_queue_size,
		drs.log_send_rate,
		drs.redo_queue_size,
		drs.redo_rate,
		[estimated_redo_completion_time_min] = case when drs.redo_rate <> 0 then (drs.redo_queue_size / drs.redo_rate) / 60.0 else (drs.redo_queue_size / 1) / 60.0 end,
		last_commit_time_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), drs.last_commit_time),
		drs.is_suspended,
		drs.suspend_reason_desc,
		ag.group_id
into #availability_databases
from sys.dm_hadr_database_replica_states as drs
inner join sys.availability_databases_cluster as adc on drs.group_id = adc.group_id
	and drs.group_database_id = adc.group_database_id
inner join sys.availability_groups as ag on ag.group_id = drs.group_id
inner join sys.availability_replicas as ar on drs.group_id = ar.group_id
	and drs.replica_id = ar.replica_id;

select	replica_server_name,
		is_primary_replica,
		database_name,
		ag_name,
		is_local,
		synchronization_state_desc,
		synchronization_health_desc,
		is_suspended,
		suspend_reason_desc
from #availability_databases as ag
left join sys.availability_group_listeners agl on agl.group_id = ag.group_id
left join sys.availability_group_listener_ip_addresses ia on ia.listener_id = agl.listener_id and ia.state_desc = 'ONLINE'
order by ag.ag_name, ag.replica_server_name, ag.database_name;
"""
    cursor_srv_pri.execute(sql_get_ag_databases)
    rs_get_ag_databases = cursor_srv_pri.fetchall()
    pt_get_ag_databases = get_pretty_table(rs_get_ag_databases)
    df_get_ag_databases = get_pandas_dataframe(rs_get_ag_databases)
    count_suspended_dbs = len(df_get_ag_databases[df_get_ag_databases['is_suspended'] == True])
    count_unhealthy_dbs = len(df_get_ag_databases[df_get_ag_databases['synchronization_health_desc'] != 'HEALTHY'])
    count_synchronized_dbs = len(df_get_ag_databases[df_get_ag_databases['synchronization_state_desc'] == 'SYNCHRONIZED'])
    count_synchronizing_dbs = len(df_get_ag_databases[df_get_ag_databases['synchronization_state_desc'] == 'SYNCHRONIZING'])

    cnxn_srv_pri.commit()

    if verbose:
        logger.info(f"pt_get_ag_databases => \n")
        print(pt_get_ag_databases)
        # logger.info(f"df_get_ag_databases => \n")
        # print(df_get_ag_databases)

    thread_messages=[]
    thread_messages.append(f":x: *{count_suspended_dbs}* databases are in SUSPENDED state.")
    thread_messages.append(f":x: *{count_unhealthy_dbs}* databases are in UNHEALTHY state.")
    thread_messages.append(f"*{count_synchronized_dbs}* databases are in SYNCHRONIZED state.")
    thread_messages.append(f"*{count_synchronizing_dbs}* databases are in SYNCHRONIZING state.")
    snippet = dict(type='snippet', filename=f"{availability_group}__ag_databases.txt", content=pt_get_ag_databases.get_string(), initial_comment="> :hourglass_flowing_sand: AG DBs and details")
    thread_messages.append(snippet)
    if slack_notification_required:
        slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

if 'Get Replica IPs From SQLMonitor' == 'Get Replica IPs From SQLMonitor':
    logger.info(f"Retrieve replicas IP from SQLMonitor by comparing @@servername..")

    # Extract distinct replica names
    replica_server_name_list = df_get_ag_databases['replica_server_name'].unique().tolist()
    replica_server_name__string = ', '.join([f"'{replica_name}'" for replica_name in replica_server_name_list])
    if verbose:
        logger.info(f"replica_server_name_list => ({', '.join(replica_server_name_list)})")
        logger.info(f"replica_server_name__string => {replica_server_name__string}")

    sql_get_replica_ips = f"""
select sql_instance = srv_name, sql_instance_port = coalesce(id.sql_instance_port, 1433), at_server_name, domain, host_distribution, product_version
from [dbo].[vw_all_server_info] asi
outer apply (select top 1 * from dbo.instance_details id where id.sql_instance = asi.srv_name and id.is_enabled = 1 and id.is_alias = 0) id
where asi.at_server_name in ({replica_server_name__string});
"""
    sql_get_replica_ips = f"""
select sql_instance = id.sql_instance, sql_instance_port = coalesce(id.sql_instance_port, 1433), ss.at_server_name --, domain, host_distribution, product_version
from dbo.sma_servers s join dbo.sma_sql_server_extended_info ss on ss.[server] = s.[server] and s.is_decommissioned = 0
outer apply (select top 1 * from dbo.instance_details id where id.sql_instance = ss.[server] and id.is_enabled = 1 and id.is_alias = 0) id
where ss.at_server_name in ({replica_server_name__string});
"""
    if verbose:
        print(f"\n{sql_get_replica_ips}\n")

    cursor_inv.execute(sql_get_replica_ips)
    rs_get_replica_ips = cursor_inv.fetchall()
    pt_get_replica_ips = get_pretty_table(rs_get_replica_ips)
    df_get_replica_ips = get_pandas_dataframe(rs_get_replica_ips)

    if verbose:
        logger.info(f"pt_get_replica_ips => \n")
        print(pt_get_replica_ips)
        # logger.info(f"df_get_replica_ips => \n")
        # print(df_get_replica_ips)

    thread_messages=[]
    snippet = dict(type='snippet', filename=f"AG_Replicas_and_details.txt", content=pt_get_replica_ips.get_string(), initial_comment="> :hourglass_flowing_sand: AG Replicas IPs and details")
    thread_messages.append(snippet)
    if slack_notification_required:
        slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

if 'Resume HADR Sync For DB' == 'Resume HADR Sync For DB':
    logger.info(f"Proceeding to resume data sync for secondary replicas..")
    cursor_replica = None

    replica_server_name_online_list = df_get_replica_ips['at_server_name'].unique().tolist()
    # replicas_offline = list(set(replica_server_name_list).difference(set(replica_server_name_online_list)))
    replicas_offline = [repl_name for repl_name in replica_server_name_list if repl_name not in replica_server_name_online_list]

    if len(replicas_offline) > 0:
        logger.warning(f"DB Services offline on {replicas_offline} as per inventory table dbo.vw_AllServerInfo.")
        thread_messages = ["> *──────────────────────────────*"]
        thread_messages.append(f":x: DB Services offline on {replicas_offline} as per inventory table dbo.vw_AllServerInfo.")
        thread_messages.append("> *──────────────────────────────*")
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
    else:
        logger.info(f"DB Services online on all replicas as per inventory table dbo.vw_AllServerInfo.")
        thread_messages = ["> *──────────────────────────────*"]
        thread_messages.append(f":white_check_mark: DB Services online on all replicas as per inventory table dbo.vw_AllServerInfo.")
        thread_messages.append("> *──────────────────────────────*")
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

    for repl_row in df_get_replica_ips.itertuples():
        # Initialize empty variables
        sql_instance_ip = None
        replica_name = None
        sql_conn_status = False

        sql_instance_ip = f"{repl_row.sql_instance},{repl_row.sql_instance_port}"
        replica_name = repl_row.at_server_name
        logger.info(f"Checking dbs on [{replica_name}] ({sql_instance_ip})")

        df_suspended_replica_dbs = df_get_ag_databases[
                (df_get_ag_databases['is_suspended'] == True) &
                (df_get_ag_databases['replica_server_name'] == replica_name)
            ]

        if not df_suspended_replica_dbs.empty:
            logger.info(f"  Create sql connection for [{sql_instance_ip}]({replica_name})..")

            # Create sql_instance connection
            try:
                cnxn_replica = connect_dba_instance(sql_instance_ip,'master',login_name,login_password,logger=logger,verbose=False)
                cursor_replica = cnxn_replica.cursor()
                sql_conn_status = True

                thread_messages = f"SQL Connection for *[{replica_name}] ({sql_instance})* made successfully. So proceeding to resume data movement."
                if slack_notification_required:
                    slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
            except Exception as e:
                    exception_name = type(e).__name__
                    logger.error(f"[{exception_name}] Exception occurred while making sql connection for [{sql_instance_ip}]({replica_name}): \n{e}\n\n")

                    thread_messages = ["> *──────────────────────────────*"]
                    thread_messages.append(f":x: [{exception_name}] Exception occurred while making sql connection for [{sql_instance_ip}]({replica_name}): \n{e}\n\n")
                    thread_messages.append("> *──────────────────────────────*")
                    if slack_notification_required:
                        slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

            # If sql_connection is present, then resume data movement
            if sql_conn_status:
                for db_row in df_suspended_replica_dbs.itertuples():
                    database_name = None
                    database_name = db_row.database_name
                    logger.info(f"  Resume data movement for [{repl_row.sql_instance}].[{database_name}]..")
                    sql_resume_data_movement = f"""
    ALTER DATABASE [{database_name}] SET HADR RESUME;

    select [is_successful] = cast(1 as bit);
    """
                    if verbose:
                        print(f"sql_resume_data_movement => \n{sql_resume_data_movement}")

                    try:
                        cursor_replica.execute(sql_resume_data_movement)
                        rs_resume_data_movement = cursor_replica.fetchone()[0]
                        cnxn_replica.commit()

                        if rs_resume_data_movement:
                            logger.info(f"  Data movement initiated..")
                            if not data_movement_event_occurred:
                                data_movement_event_occurred = True

                        thread_messages = f"Data movement initiated for *[{repl_row.sql_instance}].[{database_name}]* .."
                        if slack_notification_required:
                            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
                    except pyodbc.ProgrammingError as e:
                        exception_name = type(e).__name__
                        logger.error(f"[{exception_name}] Exception occurred: \n{e}\n\n")

                        thread_messages = ["> *──────────────────────────────*"]
                        thread_messages.append(f":x: [{exception_name}] Exception occurred while resuming data movement for [{database_name}] on [{sql_instance_ip}]({replica_name}): \n{e}\n\n")
                        thread_messages.append("> *──────────────────────────────*")
                        if slack_notification_required:
                            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
                        # raise e
                    except Exception as e:
                        exception_name = type(e).__name__
                        logger.error(f"[{exception_name}] Exception occurred: \n{e}\n\n")

                        thread_messages = ["> *──────────────────────────────*"]
                        thread_messages.append(f":x: [{exception_name}] Exception occurred while resuming data movement for [{database_name}] on [{sql_instance_ip}]({replica_name}): \n{e}\n\n")
                        thread_messages.append("> *──────────────────────────────*")
                        if slack_notification_required:
                            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
                        # raise e
            else:
                thread_messages = f":x: SQL Connection for *[{replica_name}] ({sql_instance_ip})* could not be made. So skipping all dbs for this replica."
                if slack_notification_required:
                    slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
        else:
            thread_messages = f"No suspended database on *[{replica_name}] ({sql_instance_ip})*"
            if slack_notification_required:
                slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

if 'Validate Ag Databases' == 'Validate Ag Databases':
    logger.info(f"Proceed to validate ag database(s) again..")

    sql_get_ag_databases = f"""
set nocount on;

if object_id('tempdb..#availability_databases') is not null
	drop table #availability_databases;

select	ar.replica_server_name,
		drs.is_primary_replica,
		adc.database_name,
		ag.name AS ag_name,
		drs.is_local,
		drs.synchronization_state_desc,
		drs.synchronization_health_desc,
		last_redone_time_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), drs.last_redone_time),
		drs.log_send_queue_size,
		drs.log_send_rate,
		drs.redo_queue_size,
		drs.redo_rate,
		[estimated_redo_completion_time_min] = case when drs.redo_rate <> 0 then (drs.redo_queue_size / drs.redo_rate) / 60.0 else (drs.redo_queue_size / 1) / 60.0 end,
		last_commit_time_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), drs.last_commit_time),
		drs.is_suspended,
		drs.suspend_reason_desc,
		ag.group_id
into #availability_databases
from sys.dm_hadr_database_replica_states as drs
inner join sys.availability_databases_cluster as adc on drs.group_id = adc.group_id
	and drs.group_database_id = adc.group_database_id
inner join sys.availability_groups as ag on ag.group_id = drs.group_id
inner join sys.availability_replicas as ar on drs.group_id = ar.group_id
	and drs.replica_id = ar.replica_id;

select	replica_server_name,
		is_primary_replica,
		database_name,
		ag_name,
		is_local,
		synchronization_state_desc,
		synchronization_health_desc,
		is_suspended,
		suspend_reason_desc
from #availability_databases as ag
left join sys.availability_group_listeners agl on agl.group_id = ag.group_id
left join sys.availability_group_listener_ip_addresses ia on ia.listener_id = agl.listener_id and ia.state_desc = 'ONLINE'
order by ag.ag_name, ag.replica_server_name, ag.database_name;
"""

    if data_movement_event_occurred and post_resume_delay_seconds > 0:
        thread_messages = f"Wait for {post_resume_delay_seconds} seconds so that databases can get in sync.."
        logger.info(thread_messages)
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
        # Pause the execution for post_resume_delay_seconds
        time.sleep(post_resume_delay_seconds)

    cursor_srv_pri.execute(sql_get_ag_databases)
    rs_get_ag_databases = cursor_srv_pri.fetchall()
    pt_get_ag_databases = get_pretty_table(rs_get_ag_databases)
    df_get_ag_databases = get_pandas_dataframe(rs_get_ag_databases)

    cnxn_srv_pri.commit()

    logger.info(f"pt_get_ag_databases => \n")
    print(pt_get_ag_databases)

    count_suspended_dbs = len(df_get_ag_databases[df_get_ag_databases['is_suspended'] == True])
    count_unhealthy_dbs = len(df_get_ag_databases[df_get_ag_databases['synchronization_health_desc'] != 'HEALTHY'])
    count_synchronized_dbs = len(df_get_ag_databases[df_get_ag_databases['synchronization_state_desc'] == 'SYNCHRONIZED'])
    count_synchronizing_dbs = len(df_get_ag_databases[df_get_ag_databases['synchronization_state_desc'] == 'SYNCHRONIZING'])

    thread_messages = []
    thread_messages.append("> *──────────────────────────────*")
    thread_messages.append("> *──────────────────────────────*")
    thread_messages.append("`Final Health of AG Databases -`")
    thread_messages.append("> *──────────────────────────────*")
    thread_messages.append(f":x: *{count_suspended_dbs}* databases are in SUSPENDED state.")
    thread_messages.append(f":x: *{count_unhealthy_dbs}* databases are in UNHEALTHY state.")
    thread_messages.append(f"*{count_synchronized_dbs}* databases are in SYNCHRONIZED state.")
    thread_messages.append(f"*{count_synchronizing_dbs}* databases are in SYNCHRONIZING state.")
    snippet = dict(type='snippet', filename=f"{availability_group}__ag_databases.txt", content=pt_get_ag_databases.get_string(), initial_comment="> :hourglass_flowing_sand: AG DBs and details")
    thread_messages.append(snippet)
    if slack_notification_required:
        slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)


# Cleanup
cursor_srv_pri.close()
cursor_inv.close()
if cursor_replica is not None:
    cursor_replica.close()
# cnxn.close()




