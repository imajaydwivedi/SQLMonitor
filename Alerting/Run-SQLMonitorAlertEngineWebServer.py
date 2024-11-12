import pyodbc
import os
import subprocess
import argparse
import json
from datetime import datetime
import time
import atexit
from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, Response, request, jsonify, redirect, make_response
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
from slackeventsapi import SlackEventAdapter
#from waitress import serve
from SmaAlertPackage.CommonFunctions.get_script_logger import get_script_logger
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
parser.add_argument("--alert_name", type=str, required=False, action="store", default="Run-SQLMonitorAlertEngineWebServer", help="Alert Name")
parser.add_argument("--alert_job_name", type=str, required=False, action="store", default="(dba) Run-SQLMonitorAlertEngineWebServer", help="Script/Job calling this script")
parser.add_argument("--alert_owner_team", type=str, required=False, action="store", default="DBA", help="Default team who would own alert")
parser.add_argument("--frequency_multiplier", type=int, required=False, action="store", default=4, help="Alert resolve threshold minutes = frequency_multiplier x alert frequency_minutes")
parser.add_argument("--has_ssl_certificate", type=bool, required=False, action="store", default=False, help="Checks for SSL certificate if enabled")
#parser.add_argument("--frequency_minutes", type=int, required=False, action="store", default=30, help="Time gap between next execution for same alert")
parser.add_argument("--verbose", type=bool, required=False, action="store", default=False, help="Extra verbose messages when enabled")
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
    verbose = args.verbose
    log_server_startup = args.log_server_startup
    run_scheduled_jobs = args.run_scheduled_jobs

# create logger
logger = get_script_logger(alert_job_name)

# Log begging
logger.info('***** BEGIN:  %s' % script_name)

# determine os
if os.name == 'nt':
    path_separator = '\\'
else:
    path_separator = '/'

# ssl_certificate
logger.info(f"script_parent_directory = '{script_parent_directory}'")
logger.info(f"script_directory = '{script_directory}'")
if has_ssl_certificate:
    ssl_certificate = f"{script_parent_directory}{path_separator}Private{path_separator}ssl_certificates{path_separator}fullchain.pem"
    ssl_certificate_key = f"{script_parent_directory}{path_separator}Private{path_separator}ssl_certificates{path_separator}privkey.pem"

# Make inventory server connection
logger.info(f"Create db connection using connect_dba_instance..")
cnxn = connect_dba_instance(inventory_server,inventory_database,login_name,login_password,logger=logger,verbose=verbose)
#cursor = cnxn.cursor()

# Create arugments for subprocess - https://www.datacamp.com/tutorial/python-subprocess
script_arguments = ['--verbose',f"{verbose}", '--inventory_server',inventory_server, '--inventory_database',inventory_database, '--credential_manager_database', credential_manager_database]
if login_name != '' and login_password != '':
    script_arguments = script_arguments + ['--login_name',login_name, '--login_password',login_password]
if verbose:
    logger.info(f"Script arguments => \n{script_arguments}")


# Get Bot OAuth Token
if 'Get Bot OAuth Token' == 'Get Bot OAuth Token':
    logger.info(f"Get bot oauth token from credential manager..")
    dba_slack_bot_token = get_sm_credential(cnxn, credential_manager_database, 'dba_slack_bot_token')
    dba_slack_bot_signing_secret = get_sm_credential(cnxn, credential_manager_database, 'dba_slack_bot_signing_secret')
    dba_slack_channel_id = get_sma_params(cnxn, param_key='dba_slack_channel_id')[0].param_value
    dba_slack_bot = get_sma_params(cnxn, param_key='dba_slack_bot')[0].param_value

# Slack Event Adapter
app = Flask(__name__)

# Slack Event Adapter
slack_event_adapter = SlackEventAdapter(dba_slack_bot_signing_secret, '/slack/events', app)

'''
@app.route('/slack/events', methods=['GET','POST'])
def slack_events_handler():
    """
    Inbound POST from slack to test token
    """
    print("Inside verification()")
    #data = request.json
    data = request.get_json()
    #challenge = data['challenge']
    #challenge = data.get("challenge")
    print(data)

    if 'challenge' in data:
        return jsonify({'challenge': data['challenge']})

    print("no challenge found. So doing some tasks.")

    return "OK", 200

@app.before_request
def redirect_http_to_https():
    if not request.is_secure:
        if verbose:
            logger.info(f"direct unsecure access to https")
        #return redirect(request.url.replace("http://", "https://"), code=301)
'''


# Send Test Slack Message
logger.info(f"Create slack WebClient..")
client = WebClient(token=dba_slack_bot_token)
bot_user_details = client.auth_test()
bot_user_id = bot_user_details['user_id']
if verbose:
    logger.info(f"dba_slack_bot_token = '{dba_slack_bot_token}'")
    print(bot_user_details)


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


@slack_event_adapter.on('message')
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

    if verbose:
        print(form_json)
        print(f"{action_to_take} {alert_key} with id {alert_id}, and respond back on {action_ts}")

    # Check to see what the user's selection was and update the message
    #select = form_json["action"][0]

    return make_response("", 200)

# dummy
@app.route("/", methods=['GET','POST'])
def greetings():
    print("inside greetings()")
    return Response(f"Greetings from SQLMonitor Alert Engine!"), 200


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

def call_15_minute_job_script():
    logger.info(f"Inside call_15_minute_job_script()")

    alert_script_path = os.path.join(script_directory, "Alert-DiskSpace.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-SqlMonitorJobs.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-NonAgDbBackupIssue.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-AgDbBackupIssue.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

def call_10_minute_job_script():
    logger.info(f"Inside call_10_minute_job_script()")

    alert_script_path = os.path.join(script_directory, "Alert-Cpu.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-SqlBlocking.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-AvailableMemory.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-DiskLatency.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-AgLatency.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

def call_5_minute_job_script():
    logger.info(f"Inside call_5_minute_job_script()")
    auto_resolve_cleared_alerts()

    alert_script_path = os.path.join(script_directory, "Alert-MemoryGrantsPending.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-OfflineAgent.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-OfflineServer.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-LogSpace.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

    alert_script_path = os.path.join(script_directory, "Alert-Tempdb.py")
    subprocess.run(['python',alert_script_path]+script_arguments, capture_output=False, text=True)

# execute scheduler
if run_scheduled_jobs:
    logger.info(f"Using WebServer for running Alert Jobs as run_scheduled_jobs is True.")
    scheduler = BackgroundScheduler()

    scheduler.add_job(func=call_15_minute_job_script, trigger="interval", minutes=15)
    scheduler.add_job(func=call_10_minute_job_script, trigger="interval", minutes=10)
    scheduler.add_job(func=call_5_minute_job_script, trigger="interval", minutes=5)

    scheduler.start()

    # Shut down the scheduler when exiting the app
    atexit.register(lambda: scheduler.shutdown())

if __name__ == "__main__":

    #app.run()
    if has_ssl_certificate:
        context = (ssl_certificate, ssl_certificate_key)
        app.run(host='0.0.0.0', debug=debug, ssl_context=context, port=5000)
        #serve(app, host='0.0.0.0', port=5000, threads=10, ssl_context=context)
    else:
        app.run(host='0.0.0.0', debug=debug, port=5000)
        #serve(app, host='0.0.0.0', port=5000, threads=10)
