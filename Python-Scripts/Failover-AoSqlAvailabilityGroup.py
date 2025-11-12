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
parser.add_argument("--post_sync_mode_update_delay_seconds", type=int, required=False, action="store", default=0, help="Time delay in seconds to introduce after change of Sync Mode for new Primary")
parser.add_argument("--sync_wait_timeout_seconds", type=int, required=False, action="store", default=120, help="Time delay in seconds to wait for new primary to get in sync state")
parser.add_argument("--post_failover_delay_seconds", type=int, required=False, action="store", default=5, help="Time delay in seconds to introduce after failover to give enough time for databases to recover")
parser.add_argument("--post_resume_delay_seconds", type=int, required=False, action="store", default=10, help="Time delay in seconds to introduce after resuming data movement to give enough time for databases to recover")
parser.add_argument("--wait_timeout_seconds", type=int, required=False, action="store", default=120, help="Wait timeout in seconds for sync the data from old primary to next primary after sync mode change")

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
    post_sync_mode_update_delay_seconds = args.post_sync_mode_update_delay_seconds
    sync_wait_timeout_seconds = args.sync_wait_timeout_seconds
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
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Create new primary server connection using connect_dba_instance..")
    cnxn_srv_pri = connect_dba_instance(f"{sql_instance},{sql_instance_port}",'master',login_name,login_password,logger=logger,verbose=False)
    cursor_srv_pri = cnxn_srv_pri.cursor()

if 'Get Inventory Connection' == 'Get Inventory Connection':
    logger.info(f"Create inventory server connection using connect_dba_instance..")
    cnxn_inv = connect_dba_instance(inventory_server,inventory_database,login_name,login_password,logger=logger,verbose=False)
    cursor_inv = cnxn_inv.cursor()

# Get current "sql_instance" role in availability group
if 'Get-Ag-Replica-Role' == 'Get-Ag-Replica-Role':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Get role of sql_instance [{sql_instance}] in ag..")

    sql_get_replica_role = f"""
set nocount on;
select  [at_server_name] = @@SERVERNAME,
        ars.replica_server_name,
        [ag_name] = ag.name,
        [primary_replica] = ags.primary_replica,
        [is_primary] = case when ars.role = 1 then cast(1 as bit) else cast(0 as bit) end,
        ars.role, ars.role_desc
from sys.dm_hadr_availability_group_states as ags
join sys.availability_groups as ag on ags.group_id = ag.group_id
outer apply (
    select ars.role_desc, ars.role, ar.replica_server_name
    from sys.dm_hadr_availability_replica_states ars
    join sys.availability_replicas as ar on ar.group_id = ars.group_id and ar.replica_id = ars.replica_id
    where ars.is_local = 1 --and ars.role = 1
    and ars.group_id = ags.group_id
) ars
where 1=1
and ag.name = '{availability_group}'
"""
    cursor_srv_pri.execute(sql_get_replica_role)
    rows = cursor_srv_pri.fetchall()
    pt_get_replica_role = get_pretty_table(rows)
    row = rows[0]
    is_primary_replica = row.is_primary
    is_secondary_replica = not is_primary_replica
    new_primary_replica = row.replica_server_name
    existing_primary_replica = row.primary_replica

    if verbose:
        logger.info(f"is_primary_replica => {is_primary_replica}")
        logger.info(f"existing_primary_replica => {existing_primary_replica}")
        logger.info(f"new_primary_replica => {new_primary_replica}")
        # print(rs_get_replica_role)
        logger.info(f"pt_get_replica_role => \n{pt_get_replica_role}\n")

if is_secondary_replica:
    thread_messages = f"[{sql_instance}] is NOT primary replica. So proceed for failover.."
else:
    thread_messages = f"[{sql_instance}] is already primary replica. So skipping failover.."
logger.info(thread_messages)
if slack_notification_required:
    slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)


if 'Get All Replicas Names' == 'Get All Replicas Names':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Get replica names..")
    rows = None

    sql_get_replicas = f"""
set nocount on;
select  [availability_group] = ag.name,
        [replica_server_name] = ar.replica_server_name,
        [replica_role] = ars.role_desc,
        [sync_mode] = ar.availability_mode_desc,
        [failover_mode] = ar.failover_mode_desc
from sys.availability_groups as ag
join sys.availability_replicas as ar
    on ag.group_id = ar.group_id
left join sys.dm_hadr_availability_replica_states as ars
    on ar.replica_id = ars.replica_id
where 1=1
and ag.name = '{availability_group}'
order by ag.name, ar.replica_server_name;
"""
    cursor_srv_pri.execute(sql_get_replicas)
    rs_get_replicas = cursor_srv_pri.fetchall()
    pt_get_replicas = get_pretty_table(rs_get_replicas)
    df_get_replicas = get_pandas_dataframe(rs_get_replicas)

    if verbose:
        logger.info(f"pt_get_replicas => \n{pt_get_replicas}\n")


if 'Get Replica IPs From SQLMonitor' == 'Get Replica IPs From SQLMonitor':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Retrieve replicas IP from SQLMonitor by comparing @@servername..")

    # Extract distinct replica names
    replica_server_name_list = df_get_replicas['replica_server_name'].unique().tolist()
    replica_server_name__string = ', '.join([f"'{replica_name}'" for replica_name in replica_server_name_list])
    if verbose:
        logger.info(f"replica_server_name_list => ({', '.join(replica_server_name_list)})")
        logger.info(f"replica_server_name__string => {replica_server_name__string}")

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


if 'Get Existing Primary Connection' == 'Get Existing Primary Connection':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Get old primary sql_instance connection..")

    existing_primary_row = df_get_replica_ips.loc[
        df_get_replica_ips['at_server_name']==existing_primary_replica,
        ['sql_instance','sql_instance_port']
    ]

    sql_instance_ip = None
    existing_primary_conn_status = False

    if not existing_primary_row.empty:
        existing_primary_ip = existing_primary_row.iloc[0]['sql_instance']
        existing_primary_port = existing_primary_row.iloc[0]['sql_instance_port']
        existing_primary_instance = f"{existing_primary_ip},{existing_primary_port}"

        logger.info(f"existing_primary_instance: {existing_primary_instance}")
    else:
        logger.error(f"Existing Primary replica {existing_primary_replica} ip could not be fetched.")
        raise Exception(f"Existing Primary replica {existing_primary_replica} ip could not be fetched from Inventory.")

    # Create sql_instance connection for existing primary
    try:
        cnxn_existing_primary = connect_dba_instance(existing_primary_instance,'master',login_name,login_password,logger=logger,verbose=False)
        cursor_existing_primary = cnxn_existing_primary.cursor()
        existing_primary_conn_status = True

        thread_messages = f"SQL Connection for *[{existing_primary_replica}] ({existing_primary_instance})* made successfully."
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"[{exception_name}] Exception occurred while making sql connection for [{existing_primary_instance}]({existing_primary_replica}): \n{e}\n\n")

        thread_messages = ["> *──────────────────────────────*"]
        thread_messages.append(f":x: [{exception_name}] Exception occurred while making sql connection for [{existing_primary_instance}]({existing_primary_replica}): \n{e}\n\n")
        thread_messages.append("> *──────────────────────────────*")
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

        # If force failover is NOT allowed, then throw error on primary connection failure
        if force is False:
            raise e


if is_secondary_replica and (force is False) and 'Set Sync Mode for new Primary' == 'Set Sync Mode for new Primary':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Connect existing primary, and set synchronous mode for new primary replica..")

    row = None
    new_primary_sync_mode_set = False
    new_primary_sync_mode = None

    logger.info(f"Proceeding to set sync mode for new primary {sql_instance} to synchronous from existing primary {existing_primary_ip}.")

    sql_set_sync_commit_mode = f"""
set nocount on;

ALTER AVAILABILITY GROUP [{availability_group}]
MODIFY REPLICA ON N'{new_primary_replica}'
WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);

select  [availability_group] = ag.name,
        [replica_server] = ar.replica_server_name,
        [replica_role] = ars.role_desc,
        [sync_mode] = ar.availability_mode_desc,
        [failover_mode] = ar.failover_mode_desc,
        [is_successful] = case when ar.availability_mode_desc = 'SYNCHRONOUS_COMMIT' then cast(1 as bit) else cast(0 as bit) end
from sys.availability_groups as ag
join sys.availability_replicas as ar
    on ag.group_id = ar.group_id
left join sys.dm_hadr_availability_replica_states as ars
    on ar.replica_id = ars.replica_id
where 1=1
and ag.name = '{availability_group}'
and ar.replica_server_name = '{new_primary_replica}'
--order by ag.name, ar.replica_server_name;
"""
    if verbose:
        print(f"sql_set_sync_commit_mode => \n{sql_set_sync_commit_mode}")

    try:
        cursor_existing_primary.execute(sql_set_sync_commit_mode)
        rs_set_sync_commit_mode = cursor_existing_primary.fetchall()
        cnxn_existing_primary.commit()

        pt_new_primary_sync_mode = get_pretty_table(rs_set_sync_commit_mode)
        row = rs_set_sync_commit_mode[0]
        new_primary_sync_mode = row.sync_mode
        new_primary_sync_mode_set = row.is_successful

        if verbose:
            logger.info(f"pt_new_primary_sync_mode => \n{pt_new_primary_sync_mode}\n")
            logger.info(f"Sync mode for {new_primary_replica}: {new_primary_sync_mode}")

        if new_primary_sync_mode_set:
            thread_messages = f"Sync Mode change initiated.."
            logger.info(thread_messages)
            if slack_notification_required:
                slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

            if post_sync_mode_update_delay_seconds > 0:
                thread_messages = f"Wait for {post_sync_mode_update_delay_seconds} seconds so that new primary replica can get in sync.."
                logger.info(thread_messages)
                if slack_notification_required:
                    slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
                # Pause the execution for post_failover_delay_seconds
                time.sleep(post_sync_mode_update_delay_seconds)
        else:
            thread_messages = f"Sync Mode change did not happen correctly."
            logger.warning(thread_messages)
            if slack_notification_required:
                slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"[{exception_name}] Exception occurred: \n{e}\n\n")
        thread_messages = f"[{exception_name}] Exception occurred: \n{e}\n\n"
        if slack_notification_required:
            slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)
        raise e


if is_secondary_replica and (force is False) and 'Validate AG Health' == 'Validate AG Health':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Validate AG Latency..")

    sql_new_primary_health = f"""
    set nocount on;

    -- Check latency metrics for Availability Group replicas
    SELECT  ag.name AS [AG_Name],
            ar.replica_server_name AS [Replica_Server],
            drs.is_local, drs.is_primary_replica, drs.[database],
            drs.synchronization_health_desc, drs.synchronization_state_desc,
            drs.last_commit_time, drs.commit_lag_sec
    FROM sys.availability_replicas AS ar
    INNER JOIN sys.availability_groups AS ag
        ON ag.group_id = ar.group_id
    OUTER APPLY (
        SELECT  top 1
                drs.is_local, drs.is_primary_replica,
                DB_NAME(drs.database_id) as [database],
                drs.synchronization_health_desc,
                drs.synchronization_state_desc,
                drs.last_commit_time,
                [commit_lag_sec] = datediff(second, max(drs.last_commit_time) over (partition by drs.database_id),  drs.last_commit_time)
                -- max(last_commit_time) would give latest commit time on primary
        FROM sys.dm_hadr_database_replica_states AS drs
        WHERE drs.replica_id = ar.replica_id and drs.group_id = ar.group_id
        ORDER BY commit_lag_sec DESC
    ) drs
    WHERE 1=1
    and ag.name = '{availability_group}'
    and ar.replica_server_name = '{new_primary_replica}';
    """

    cursor_existing_primary.execute(sql_new_primary_health)
    rs_new_primary_health = cursor_existing_primary.fetchall()
    # cnxn_existing_primary.commit()

    pt_new_primary_health = get_pretty_table(rs_new_primary_health)
    row = rs_new_primary_health[0]
    new_primary_sync_health = row.synchronization_health_desc
    new_primary_sync_state = row.synchronization_state_desc
    new_primary_commit_lag_sec = row.commit_lag_sec

    # if verbose:
    logger.info(f"pt_new_primary_health => \n{pt_new_primary_health}\n")
    logger.info(f"Sync health for [{new_primary_replica}]: {new_primary_sync_health}")
    logger.info(f"Sync state for [{new_primary_replica}]: {new_primary_sync_state}")
    logger.info(f"new_primary_commit_lag_sec: {new_primary_commit_lag_sec}")
    # sync_wait_timeout_seconds

    wait_counter_seconds = 0
    wait_step_time_seconds = 5

    if new_primary_commit_lag_sec < 2:
        logger.info(f"AG log latency is less than 2 seconds. Proceed for failover..")
    else:
        while (new_primary_commit_lag_sec > 2) and (wait_counter_seconds < sync_wait_timeout_seconds):
            if verbose:
                logger.info(f"Sleep for another {wait_step_time_seconds} seconds..")

            time.sleep(wait_step_time_seconds)
            wait_counter_seconds += wait_step_time_seconds

            # Recheck latency after waiting
            cursor_existing_primary.execute(sql_new_primary_health)
            rs_new_primary_health = cursor_existing_primary.fetchall()
            # cnxn_existing_primary.commit()

            pt_new_primary_health = get_pretty_table(rs_new_primary_health)
            row = rs_new_primary_health[0]
            new_primary_sync_health = row.synchronization_health_desc
            new_primary_sync_state = row.synchronization_state_desc
            new_primary_commit_lag_sec = row.commit_lag_sec

            if new_primary_commit_lag_sec <= 2:
                logger.info(f"new_primary_commit_lag_sec: {new_primary_commit_lag_sec}")

    if (new_primary_commit_lag_sec > 2) and (wait_counter_seconds >= sync_wait_timeout_seconds):
        logger.warning(f"Wait timeout happened while waiting for new primary to get in sync with old primary.")


# If sync mode change happened, then wait for latency to become zero

if is_secondary_replica and 'Perform Failover' == 'Perform Failover':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Failover AG [{availability_group}] to replica [{new_primary_replica}]..")

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
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
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

if 'Resume HADR Sync For DB' == 'Resume HADR Sync For DB':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
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


if 'Get All Replicas Sync Mode' == 'Get All Replicas Sync Mode':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Get replica names and sync modes..")
    rows = None

    sql_get_replicas = f"""
set nocount on;
select  [availability_group] = ag.name,
        [replica_server_name] = ar.replica_server_name,
        [replica_role] = ars.role_desc,
        [sync_mode] = ar.availability_mode_desc,
        [failover_mode] = ar.failover_mode_desc
from sys.availability_groups as ag
join sys.availability_replicas as ar
    on ag.group_id = ar.group_id
left join sys.dm_hadr_availability_replica_states as ars
    on ar.replica_id = ars.replica_id
where 1=1
and ag.name = '{availability_group}'
order by ag.name, ar.replica_server_name;
"""
    cursor_srv_pri.execute(sql_get_replicas)
    rs_get_replicas = cursor_srv_pri.fetchall()
    pt_get_replicas = get_pretty_table(rs_get_replicas)
    df_get_replicas = get_pandas_dataframe(rs_get_replicas)

    if verbose:
        logger.info(f"pt_get_replicas => \n{pt_get_replicas}\n")


if 'Set Sync Mode for All Replicas' == 'Set Sync Mode for All Replicas':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
    logger.info(f"Set proper Sync Mode for all replicas as per new primary replica..")

    primary_replica_subnet = '.'.join(sql_instance.split('.')[:2])
    logger.info(f"primary_replica_subnet: {primary_replica_subnet}")

    for row in df_get_replica_ips.itertuples():
        replica_instance = row.sql_instance
        replica_instance_port = row.sql_instance_port
        replica_server_name = row.at_server_name

        replica_row = df_get_replicas[df_get_replicas.replica_server_name==replica_server_name].iloc[0]
        replica_role = replica_row.replica_role
        replica_sync_mode = replica_row.sync_mode
        replica_failover_mode = replica_row.failover_mode
        replica_subnet = '.'.join(replica_instance.split('.')[:2])

        replica_sync_mode_target = None

        if replica_server_name != new_primary_replica:
            # for same subnet servers, set sync commit
            if primary_replica_subnet == replica_subnet:
                if replica_sync_mode == 'SYNCHRONOUS_COMMIT':
                    logger.info(f"Sync mode of [{replica_server_name}] is already set to Synchronous Commit.")
                else:
                    replica_sync_mode_target = 'SYNCHRONOUS_COMMIT'
                    logger.info(f"Change sync mode of [{replica_server_name}] to {replica_sync_mode_target}..")
            # for different subnet servers, set async commit
            else:
                if replica_sync_mode == 'ASYNCHRONOUS_COMMIT':
                    logger.info(f"Sync mode of [{replica_server_name}] is already set to Asynchronous Commit.")
                else:
                    replica_sync_mode_target = 'ASYNCHRONOUS_COMMIT'
                    logger.info(f"Change sync mode of [{replica_server_name}] to {replica_sync_mode_target}..")

        if replica_sync_mode_target is not None:
        #     logger.info(f"No action needed for [{replica_server_name}].")
        # else:
            sql_set_replica_commit_mode = f"""
            set nocount on;

            ALTER AVAILABILITY GROUP [{availability_group}]
            MODIFY REPLICA ON N'{replica_server_name}'
            WITH (AVAILABILITY_MODE = {replica_sync_mode_target});

            waitfor delay '00:00:02';

            select  [availability_group] = ag.name,
                    [replica_server] = ar.replica_server_name,
                    [replica_role] = ars.role_desc,
                    [sync_mode] = ar.availability_mode_desc,
                    [failover_mode] = ar.failover_mode_desc,
                    [is_successful] = case when ar.availability_mode_desc = 'SYNCHRONOUS_COMMIT' then cast(1 as bit) else cast(0 as bit) end
            from sys.availability_groups as ag
            join sys.availability_replicas as ar
                on ag.group_id = ar.group_id
            left join sys.dm_hadr_availability_replica_states as ars
                on ar.replica_id = ars.replica_id
            where 1=1
            and ag.name = '{availability_group}'
            and ar.replica_server_name = '{replica_server_name}'
            --order by ag.name, ar.replica_server_name;
            """
        # if verbose:
        #     print(f"sql_set_replica_commit_mode => \n{sql_set_replica_commit_mode}")

        try:
            cursor_srv_pri.execute(sql_set_replica_commit_mode)
            rs_set_replica_commit_mode = cursor_srv_pri.fetchall()
            cnxn_srv_pri.commit()

            pt_set_replica_commit_mode = get_pretty_table(rs_set_replica_commit_mode)
            row = rs_set_replica_commit_mode[0]
            replica_sync_mode = row.sync_mode
            replica_failover_mode = row.failover_mode
            replica_commit_mode_set = row.is_successful

            if verbose:
                logger.info(f"  pt_set_replica_commit_mode => \n{pt_set_replica_commit_mode}\n")
                logger.info(f"  New sync mode for [{replica_server_name}]: {replica_sync_mode} is set")
                logger.info(f"  New failover mode for [{replica_server_name}]: {replica_failover_mode} is set")

            thread_messages = []
            thread_messages.append(f"New sync mode for {replica_server_name}: {replica_sync_mode} is set")
            # thread_messages.append(f"New failover mode for {replica_server_name}: {replica_failover_mode} is set")

            if slack_notification_required:
                slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

        except Exception as e:
            exception_name = type(e).__name__
            logger.error(f"[{exception_name}] Exception occurred while setting commit mode on replica [{replica_server_name}]: \n{e}\n\n")
            thread_messages = f"[{exception_name}] Exception occurred while setting commit mode on replica [{replica_server_name}]: \n{e}\n\n"
            if slack_notification_required:
                slack_result = send_slack_incremental_notification(slack_token, slack_channel, thread_header=None, thread_messages=thread_messages, slack_ts_value=slack_ts_value, logger=logger, verbose=False)

            # If Normal Failover, then fail on connectivity error
            if not force:
                raise e


if 'Validate Ag Databases' == 'Validate Ag Databases':
    logger.info(f"*────────────────────────────────────────────────────────────────────────────*")
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




