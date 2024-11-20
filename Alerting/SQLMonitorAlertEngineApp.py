#import pyodbc
import os
import subprocess
from threading import Thread
import argparse
import json
from datetime import datetime
import time
import hashlib
import hmac
import atexit
from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, Response, request, jsonify, redirect, make_response, abort
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
from slackeventsapi import SlackEventAdapter
from waitress import serve
from SmaAlertPackage.CommonFunctions.get_script_logger import get_script_logger
#import logging
import psutil
from SmaAlertPackage.CommonFunctions.connect_dba_instance import connect_dba_instance
from SmaAlertPackage.CommonFunctions.get_sma_params import get_sma_params
from SmaAlertPackage.CommonFunctions.get_sm_credential import get_sm_credential
#from SmaAlertPackage.SmaAlert import SmaAlert as sma
from SmaAlertPackage.SmaAlert import SmaAlert

# get Script Name
script_name = os.path.basename(__file__)
script_full_path = os.path.abspath(__file__)
script_directory = os.path.abspath(os.path.abspath(os.path.dirname(__file__)))
script_parent_directory = os.path.split(os.path.abspath(script_directory))[0]

parser = argparse.ArgumentParser(description="Script to run SQLMonitor Alert Engine Web Server", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("--credential_manager_database", type=str, required=False, action="store", default="DBA", help="Credential Manager Database")
parser.add_argument("--login_name", type=str, required=False, action="store", default="sa", help="Login name for sql authentication")
parser.add_argument("--login_password", type=str, required=False, action="store", default="", help="Login password for sql authentication")
parser.add_argument("--alert_name", type=str, required=False, action="store", default="SQLMonitorAlertEngineApp", help="Alert Name")
parser.add_argument("--alert_job_name", type=str, required=False, action="store", default="(dba) SQLMonitorAlertEngineApp", help="Script/Job calling this script")
parser.add_argument("--alert_owner_team", type=str, required=False, action="store", default="DBA", help="Default team who would own alert")
parser.add_argument("--frequency_multiplier", type=int, required=False, action="store", default=4, help="Alert resolve threshold minutes = frequency_multiplier x alert frequency_minutes")
parser.add_argument("--has_ssl_certificate", type=bool, required=False, action="store", default=True, help="Checks for SSL certificate if enabled")
parser.add_argument("--use_waitress_server", type=bool, required=False, action="store", default=True, help="Checks for SSL certificate if enabled")
#parser.add_argument("--frequency_minutes", type=int, required=False, action="store", default=30, help="Time gap between next execution for same alert")
parser.add_argument("--verbose", type=bool, required=False, action="store", default=False, help="Extra verbose messages when enabled")
#parser.add_argument('--verbose', type=bool, nargs='?', const=True, default=False, help="Extra verbose messages when enabled")
parser.add_argument("--debug", type=bool, required=False, action="store", default=False, help="Run web server in debug mode")
parser.add_argument("--log_server_startup", type=bool, required=False, action="store", default=False, help="Log server startup message in Slack Channel")
parser.add_argument("--echo_test", type=bool, required=False, action="store", default=False, help="Enable echo test")
parser.add_argument("--run_scheduled_jobs", type=bool, required=False, action="store", default=True, help="Enable echo test")



args=parser.parse_args()

if 'Retrieve Parameters' == 'Retrieve Parameters':
    inventory_server = args.inventory_server
    inventory_database = args.inventory_database
    credential_manager_database = args.credential_manager_database
    login_name = args.login_name
    login_password = args.login_password
    alert_name = args.alert_name
    alert_job_name = args.alert_job_name
    alert_owner_team = args.alert_owner_team
    frequency_multiplier = args.frequency_multiplier
    has_ssl_certificate = args.has_ssl_certificate
    debug = args.debug
    #frequency_minutes = args.frequency_minutes
    verbose:bool = args.verbose
    log_server_startup = args.log_server_startup
    run_scheduled_jobs = args.run_scheduled_jobs

# determine os
if os.name == 'nt':
    path_separator = '\\'
else:
    path_separator = '/'

# Identify caller
parent_process = psutil.Process().parent()
if parent_process is not None:
    parent_process_name = parent_process.name()
    print(f"\nScript '{script_name}' called by '{parent_process_name}' (PID: {parent_process.pid})")
else:
    parent_process_name = 'wsgi'
    print(f"\nScript '{script_name}' is being called by wsgi.")

# create logger
# if web server run manually for testing, then log to console
log_to_file:bool = False
if parent_process_name in ['powershell_ise.exe', 'powershell.exe', 'pwsh.exe']:
    logger = get_script_logger(alert_job_name)
    print(f"Webserver is being run manually by developer.\n")
else:
    log_to_file:bool = True
    log_file = f"{script_directory}{path_separator}Logs{path_separator}{alert_job_name}.log"
    logger = get_script_logger(alert_job_name, log_file)
    print(f"Webserver is running in production mode.\n")

# Log begging
logger.info(f"\n\n***** BEGIN:  {script_name}")

# ssl_certificate
logger.info(f"script_parent_directory = '{script_parent_directory}'")
logger.info(f"script_directory = '{script_directory}'")
if has_ssl_certificate:
    ssl_certificate = f"{script_parent_directory}{path_separator}Private{path_separator}ssl_certificates{path_separator}fullchain.pem"
    ssl_certificate_key = f"{script_parent_directory}{path_separator}Private{path_separator}ssl_certificates{path_separator}privkey.pem"

# Make inventory server connection
if verbose:
    logger.info(f"Create db connection using connect_dba_instance..")
cnxn = connect_dba_instance(inventory_server,inventory_database,login_name,login_password,logger=logger,verbose=verbose)
#cursor = cnxn.cursor()

# Create arugments for subprocess - https://www.datacamp.com/tutorial/python-subprocess
if verbose:
    logger.info(f"Verbose is True")
else:
    logger.info(f"Verbose is False")

script_arguments = ['--inventory_server',inventory_server, '--inventory_database',inventory_database, '--credential_manager_database', credential_manager_database]
if login_name != '' and login_password != '':
    script_arguments = script_arguments + ['--login_name',login_name, '--login_password',login_password]
if verbose:
    script_arguments = script_arguments + ['--verbose',f"{verbose}"]
if log_to_file:
    script_arguments = script_arguments + ['--log_file',log_file]

logger.info(f"Script arguments => \n{['YourLoginPasswordDesensitizedHere' if item == login_password else item for item in script_arguments]}")


# Get Bot OAuth Token
if 'Get Bot OAuth Token' == 'Get Bot OAuth Token':
    logger.info(f"Get bot oauth token from credential manager..")
    dba_slack_bot_token = get_sm_credential(cnxn, credential_manager_database, 'dba_slack_bot_token')
    dba_slack_bot_signing_secret = get_sm_credential(cnxn, credential_manager_database, 'dba_slack_bot_signing_secret')
    dba_slack_verification_token = get_sm_credential(cnxn, credential_manager_database, 'dba_slack_verification_token')
    dba_slack_channel_id = get_sma_params(cnxn, param_key='dba_slack_channel_id')[0].param_value
    dba_slack_bot = get_sma_params(cnxn, param_key='dba_slack_bot')[0].param_value

# Slack Event Adapter
app = Flask(__name__)

# Slack Event Adapter
SLACK_SIGNING_SECRET = dba_slack_bot_signing_secret # used for slack event subscription
slack_token = dba_slack_bot_token # used for slack WebClient
VERIFICATION_TOKEN = dba_slack_verification_token # used for slack challenge verification

slack_events_adapter = SlackEventAdapter(dba_slack_bot_signing_secret, '/slack/events', app)

# Instantiating slack client. Send Test Slack Message
logger.info(f"Create slack WebClient..")
client = WebClient(token=dba_slack_bot_token)
bot_user_details = client.auth_test()
bot_user_id = bot_user_details['user_id']
if verbose:
    logger.info(f"dba_slack_bot_token = '{dba_slack_bot_token}'")


# Main Page Route
@app.route("/", methods=['GET','POST'])
def greetings():
    logger.info("inside greetings()")

    return Response(f"Greetings from SQLMonitor Alert Engine!"), 200


def verify_slack_request(req):
    print(req)
    #timestamp = req.headers.get("X-Slack-Request-Timestamp")
    timestamp = req.headers['X-Slack-Request-Timestamp']
    if timestamp is None:
        timestamp = time.time() - 2
    #slack_signature = req.headers.get("X-Slack-Signature")
    slack_signature = req.headers['X-Slack-Signature']
    body = req.get_data(as_text=True)

    # Check if the request timestamp is within 5 minutes of the current time
    if abs(time.time() - int(timestamp)) > 300:
    #if absolute_value(time.time() - timestamp) > 60 * 5:
        return False, "Invalid request timestamp"

    # Create the basestring to verify the signature
    basestring = f"v0:{timestamp}:{body}"
    my_signature = "v0=" + hmac.new(
        key=dba_slack_bot_signing_secret.encode(),
        msg=basestring.encode(),
        digestmod=hashlib.sha256
    ).hexdigest()

    # Compare the signatures
    if not hmac.compare_digest(my_signature, slack_signature):
        return False, "Invalid signature"

    return True, None


@slack_events_adapter.on("app_mention")
def handle_message(event_data):
    def send_reply(value):
        event_data = value
        message = event_data["event"]
        if message.get("subtype") is None:
            command = message.get("text")
            channel_id = message["channel"]
            if any(item in command.lower() for item in greetings):
                message = (
                    "Hello <@%s>! :tada:"
                    % message["user"]  # noqa
                )
                client.chat_postMessage(channel=channel_id, text=message)
    thread = Thread(target=send_reply, kwargs={"value": event_data})
    thread.start()
    return Response(status=200)


@app.route("/verify", methods=["GET","POST"])
def verify_webserver():
    #return "Inside /verify", 200
    return (jsonify({"health": "server is up and running"}))


# Create an event listener for "reaction_added" events and print the emoji name
'''
@slack_events_adapter.on("reaction_added")
def reaction_added(event_data):
  emoji = event_data["event"]["reaction"]
  print(emoji)
'''

if log_server_startup:
    logger.info(f"Log Web Server startup on slack channel {dba_slack_channel_id}..")
    client.chat_postMessage(
              channel = dba_slack_channel_id,
              username = dba_slack_bot,
              blocks = [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": f"{datetime.now()} - Starting SQLMonitor Web Server.."
                  }
                }
              ]
              #text = f"{datetime.now()} - Starting SQLMonitor Web Server.."
          )

'''
@slack_events_adapter.on('message')
def message(payload):
    logger.info(f"Read slack message & echo back..")
    event = payload.get('event', {})
    channel_id = event.get('channel')
    user_id = event.get('user')
    text = event.get('text')
    if verbose:
        print(event)

    if bot_user_id != user_id and args.echo_test:
        client.chat_postMessage(
              channel = channel_id,
              #username = dba_slack_bot,
              blocks = [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": f"ECHO: {text}"
                  }
                }
              ]
              #text = f"Sure @{user_name}! Will come back with Active Alert!"
          )
'''

# Listen to slack commands
slack_command = '/alerts'
@app.route(slack_command, methods=['GET','POST'])
def get_alert():
    logger.info(f"Got request on endpoint: {slack_command}..")
    data = request.form
    if verbose:
        print(data)
    user_id = data.get('user_id')
    user_name = data.get('user_name')
    channel_id = data.get('channel_id')
    channel_name = data.get('channel_name')
    command_by_user = data.get('command')
    api_app_id = data.get('api_app_id')

    if bot_user_id != user_id:
        client.chat_postMessage(
              channel = channel_id,
              username = dba_slack_bot,
              blocks = [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": f"Sure @{user_name}! Will come back with Active Alert!"
                  }
                }
              ]
              #text = f"Sure @{user_name}! Will come back with Active Alert!"
          )

    return Response(), 200


# Handle Interactivity
slack_command = '/slack/interactive-endpoint'
@app.route(slack_command, methods=['GET','POST'])
def interactive_action():
    logger.info(f"Got request on endpoint: {slack_command}..")

    # Parse the request payload
    data = request.form["payload"]
    form_json = json.loads(data)
    user_name = form_json['user']['username']
    user_id = form_json['user']['id']
    token = form_json["token"]
    channel_id = form_json["channel"]["id"]
    action_to_take = form_json["actions"][0]["text"]["text"]
    alert_key = form_json["actions"][0]["value"]
    action_id = form_json["actions"][0]["action_id"]
    alert_id = int(action_id.replace(f"{action_to_take}-",""))
    action_ts = form_json["actions"][0]["action_ts"]

    # alert object
    alert_obj = SmaAlert()
    alert_obj.logger = logger
    alert_obj.logged_by = user_name
    alert_obj.alert_job_name = alert_job_name
    alert_obj.id = alert_id
    alert_obj.action_to_take = action_to_take
    alert_obj.verbose = verbose
    alert_obj.sql_connection = cnxn
    alert_obj.initialize_data_from_db()
    alert_obj.initialize_derived_attributes()
    #alert_obj.slack_ts_value = action_ts
    alert_obj.take_required_action()

    logger.info(f"{action_to_take} {alert_key} with id {alert_id}, and respond back on {action_ts}")
    if verbose:
        print(form_json)

    # Check to see what the user's selection was and update the message
    #select = form_json["action"][0]

    return make_response("", 200)


def auto_resolve_cleared_alerts():
    logger.info(f"Inside auto_resolve_cleared_alerts()")
    sql_query = f"""
declare @_rows_affected int;
exec @_rows_affected = dbo.usp_get_active_alert_by_state_severity @state = 'Cleared' --,@severity = 'Critical';
select [is_found] = isnull(@_rows_affected,0);
    """
    cursor = cnxn.cursor()
    cursor.execute(sql_query)
    query_resultset = cursor.fetchall()

    cursor.nextset()
    row_count = (cursor.fetchall())[0][0]

    #logger.info(f"{row_count} cleared alerts found.")
    #print(query_resultset)

    if row_count > 0:
        logger.info(f"{row_count} cleared alerts found.")

        col_names = [column[0] for column in query_resultset[0].cursor_description]
        col_value = lambda row,col: row[(lambda col: col_names.index(col))(col)]

        # loop through cleared alerts, and check if they should be cleared
        for row in query_resultset:
            alert_id = col_value(row,'id')
            alert_key = col_value(row,'alert_key')
            frequency_minutes = int(col_value(row,'frequency_minutes'))
            minutes_since_last_log = int(col_value(row,'minutes_since_last_log'))

            if minutes_since_last_log >= (frequency_minutes*frequency_multiplier):
                logger.info(f"Threshold met for {alert_key}. frequency_minutes = {frequency_minutes}, minutes_since_last_log = {minutes_since_last_log}, threshold = {frequency_minutes*frequency_multiplier}")

                # alert object
                alert_obj = SmaAlert()
                alert_obj.logger = logger
                alert_obj.logged_by = dba_slack_bot
                alert_obj.alert_job_name = alert_job_name
                alert_obj.id = alert_id
                alert_obj.action_to_take = 'Resolve'
                alert_obj.verbose = verbose
                alert_obj.sql_connection = cnxn
                alert_obj.initialize_data_from_db()
                alert_obj.initialize_derived_attributes()
                #alert_obj.slack_ts_value = action_ts
                alert_obj.take_required_action()
            else:
                logger.info(f"Threshold not met for {alert_key}. frequency_minutes = {frequency_minutes}, minutes_since_last_log = {minutes_since_last_log}, threshold = {frequency_minutes*frequency_multiplier}")
    else:
        logger.info(f"No cleared alert found.")

def call_5_minute_job_script():
    logger.info(f"Inside call_5_minute_job_script()")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-DiskSpace.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-SqlMonitorJobs.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-NonAgDbBackupIssue.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-AgDbBackupIssue.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

def call_2_minute_job_script():
    logger.info(f"Inside call_2_minute_job_script()")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-Cpu.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-SqlBlocking.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-AvailableMemory.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-DiskLatency.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-AgLatency.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

def call_1_minute_job_script():
    logger.info(f"Inside call_1_minute_job_script()")
    auto_resolve_cleared_alerts()

    try:
        alert_script_path = os.path.join(script_directory, "Alert-MemoryGrantsPending.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-OfflineAgent.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-OfflineServer.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-LogSpace.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

    try:
        alert_script_path = os.path.join(script_directory, "Alert-Tempdb.py")
        subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)
    except Exception as e:
        exception_name = type(e).__name__
        logger.error(f"Error exception [{exception_name}] occurred. \n{e}")

# execute scheduler
if run_scheduled_jobs:
    logger.info(f"Using WebServer for running Alert Jobs as run_scheduled_jobs is True.")
    scheduler = BackgroundScheduler()

    scheduler.add_job(func=call_5_minute_job_script, trigger="interval", minutes=5)
    scheduler.add_job(func=call_2_minute_job_script, trigger="interval", minutes=2)
    scheduler.add_job(func=call_1_minute_job_script, trigger="interval", minutes=1)

    scheduler.start()

    # Shut down the scheduler when exiting the app
    atexit.register(lambda: scheduler.shutdown())

if __name__ == "__main__":

    if args.use_waitress_server:
        logger.info(f"Running waitress web server.")
        serve(app, host='0.0.0.0', port=5000, threads=20)
    else:
        if has_ssl_certificate:
            logger.info(f"Running flask web server with SSL Certificate.")
            context = (ssl_certificate, ssl_certificate_key)
            app.run(host='0.0.0.0', debug=debug, ssl_context=context, port=5000)
        else:
            logger.info(f"Running flask web server without Certificate.")
            app.run(host='0.0.0.0', debug=debug, port=5000)

