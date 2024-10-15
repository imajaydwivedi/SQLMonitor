import pyodbc
import os
import argparse
from flask import Flask
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
from slackeventsapi import SlackEventAdapter
from SmaAlertPackage.CommonFunctions.get_script_logger import get_script_logger
from SmaAlertPackage.CommonFunctions.connect_dba_instance import connect_dba_instance
from SmaAlertPackage.CommonFunctions.get_sma_params import get_sma_params
from SmaAlertPackage.CommonFunctions.get_sm_credential import get_sm_credential

# get Script Name
script_name = os.path.basename(__file__)

parser = argparse.ArgumentParser(description="Script to run SQLMonitor Alert Engine Web Server", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("--inventory_server", type=str, required=False, action="store", default="localhost", help="Inventory Server")
parser.add_argument("--inventory_database", type=str, required=False, action="store", default="DBA", help="Inventory Database")
parser.add_argument("--credential_manager_database", type=str, required=False, action="store", default="DBA", help="Credential Manager Database")
parser.add_argument("--login_name", type=str, required=False, action="store", default="sa", help="Login name for sql authentication")
parser.add_argument("--login_password", type=str, required=False, action="store", default="", help="Login password for sql authentication")
parser.add_argument("--alert_name", type=str, required=False, action="store", default="Run-SQLMonitorAlertEngineWebServer", help="Alert Name")
parser.add_argument("--alert_job_name", type=str, required=False, action="store", default="(dba) Run-SQLMonitorAlertEngineWebServer", help="Script/Job calling this script")
parser.add_argument("--alert_owner_team", type=str, required=False, action="store", default="DBA", help="Default team who would own alert")
#parser.add_argument("--frequency_minutes", type=int, required=False, action="store", default=30, help="Time gap between next execution for same alert")
parser.add_argument("--verbose", type=bool, required=False, action="store", default=True, help="Extra debug message when enabled")

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
    #frequency_minutes = args.frequency_minutes
    verbose = args.verbose

# create logger
logger = get_script_logger(alert_job_name)

# Log begging
logger.info('***** BEGIN:  %s' % script_name)

# Make inventory server connection
logger.info(f"Create db connection using connect_dba_instance..")
cnxn = connect_dba_instance(inventory_server,inventory_database,login_name,login_password,logger,verbose)
#cursor = cnxn.cursor()

# Get Bot OAuth Token
if 'Get Bot OAuth Token' == 'Get Bot OAuth Token':
    logger.info(f"Get bot oauth token from credential manager..")
    dba_slack_bot_token = get_sm_credential(cnxn, credential_manager_database, 'dba_slack_bot_token')
    dba_slack_bot_signing_secret = get_sm_credential(cnxn, credential_manager_database, 'dba_slack_bot_signing_secret')
    dba_slack_channel_id = get_sma_params(cnxn, param_key='dba_slack_channel_id')[0].param_value
    dba_slack_bot = get_sma_params(cnxn, param_key='dba_slack_bot')[0].param_value

# Slack Event Adapter
app = Flask(__name__)
slack_event_adapter = SlackEventAdapter(dba_slack_bot_signing_secret, '/slack/events', app)

# Send Test Slack Message
logger.info(f"Create slack WebClient..")
if verbose:
    logger.info(f"dba_slack_bot_token = '{dba_slack_bot_token}'")
client = WebClient(token=dba_slack_bot_token)
bot_user_details = client.auth_test()
bot_user_id = bot_user_details['user_id']
if verbose:
    print(bot_user_details)

logger.info(f"Report Web Server startup on channel {dba_slack_channel_id}..")
client.chat_postMessage(
          channel=dba_slack_channel_id,
          username = dba_slack_bot,
          blocks = [
            {
              "type": "section",
              "text": {
                "type": "mrkdwn",
                "text": f"Starting SQLMonitor Web Server.."
              }
            }
          ],
          text = "Starting SQLMonitor Web Server.."
      )

@slack_event_adapter.on('message')
def message(payload):
    event = payload.get('event', {})
    channel_id = event.get('channel')
    user_id = event.get('user')
    text = event.get('text')

    if bot_user_id != user_id:
        client.chat_postMessage(channel=channel_id, text=text)

if __name__ == "__main__":
    #app.run()
    app.run(debug=verbose)
