# How to send message to a Slack channel
  # https://www.datacamp.com/tutorial/how-to-send-slack-messages-with-python
	# https://stackoverflow.com/a/71973904/4449743

# Replying to a Thread using Slack API
  # https://stackoverflow.com/a/57307515/4449743

import os
from slack_sdk import WebClient
import argparse
from datetime import datetime

parser = argparse.ArgumentParser(description="Script to Send Slack Alert",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-t", "--slack_token", type=str, required=False, action="store", default="some-dummy-slack-token-here", help="API Bot Token", )
parser.add_argument("--slack_channel", type=str, required=False, action="store", default="sqlmonitor-alerts", help="Slack Channel Name", )
parser.add_argument("--slack_bot", type=str, required=False, action="store", default="SQLMonitor", help="Slack Bot name", )

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
slack_token = args.slack_token
slack_channel = args.slack_channel
slack_bot = args.slack_bot

# Retrieve Slack Token from Environment variables if not provided
if slack_token:
  print ("Slack token provided.")
else:
  print ("Slack token not provided. Checking environment variables..")
  slack_token = os.environ["SLACK_TOKEN"]
  print(slack_token)

# Set up a WebClient with the Slack OAuth token
client = WebClient(token=slack_token)
slack_message_ts_value = None

# Send initial message of an alert
try:
  message = f"""
This is my first Slack message from Python!
In upcoming messages, I will try to be more creative.
"""
  result = client.chat_postMessage(
      channel=slack_channel, 
      text=message, 
      username=slack_bot
  )
except SlackApiError as e:
  print(f"Error: {e}")
except Exception as e:
  exception_name = type(e).__name__
  print(f'Exception [{exception_name}] occurred. \n{e}')
finally:
  if result:
    print(result)
    slack_message_ts_value = result['ts']
    print(f"Slack message TS = {slack_message_ts_value}")

# Send reply message to an alert
try:
  message = f"""
See, I am responding on time by replying to slack message in thread.
Now you should not have any complaints.
"""
  result = client.chat_postMessage(
      channel=slack_channel, 
      thread_ts=slack_message_ts_value,
      text=message
  )
except SlackApiError as e:
  print(f"Error: {e}")
except Exception as e:
  exception_name = type(e).__name__
  print(f'Exception [{exception_name}] occurred. \n{e}')
finally:
  if result:
    print(result)
    #slack_message_ts_value = result['ts']
    #print(f"Slack message TS = {slack_message_ts_value}")