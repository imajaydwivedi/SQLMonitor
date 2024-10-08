# How to send message to a Slack channel
  # https://www.datacamp.com/tutorial/how-to-send-slack-messages-with-python
	# https://stackoverflow.com/a/71973904/4449743

# Python Slack SDK - Web Client
  # https://tools.slack.dev/python-slack-sdk/web

# Formatting with rich text
  # https://api.slack.com/tutorials/tracks/rich-text-tutorial

# Block Kit Builder
  # https://app.slack.com/block-kit-builder

import os
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
import argparse
from datetime import datetime
import time

parser = argparse.ArgumentParser(description="Script to Send Slack Alert",
                                  formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-t", "--slack_token", type=str, required=False, action="store", default="some-dummy-slack-token-here", help="API Bot Token", )
parser.add_argument("--slack_channel", type=str, required=False, action="store", default="sqlmonitor-alerts", help="Slack Channel Name", )
parser.add_argument("--slack_bot", type=str, required=False, action="store", default="SQLMonitor", help="Slack Bot name", )
parser.add_argument("--file_path", type=str, required=False, action="store", default="file_path.txt", help="File to send in Slack message", )

args=parser.parse_args()

today = datetime.today()
today_str = today.strftime('%Y-%m-%d')
slack_token = args.slack_token
slack_channel = args.slack_channel
slack_bot = args.slack_bot
file_path = args.file_path

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
  print(f"********************************* Send initial alert message in slack channel.")
  message = f"""
This is my first Slack message from Python!
In upcoming messages, I will try to be more creative.
"""
  response = client.chat_postMessage(
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
  if response:
    print(response)
    slack_message_ts_value = response['ts']
    print(f"Slack message TS = {slack_message_ts_value}")


# Send reply message to an alert
try:
  print(f"********************************* Reply on alert message.")
  message = f"""
See, I am responding on time by replying to slack message in thread.
Now you should not have any complaints.
"""
  response2 = client.chat_postMessage(
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
  if response2:
    print(response2)
    slack_message_ts_value = response['ts']
    print(f"Slack message TS = {slack_message_ts_value}")


# Send reply message with file
try:
  print(f"********************************* Upload file in alert message.")
  response3 = client.files_upload_v2(
      channel=slack_channel,
      thread_ts=slack_message_ts_value,
      file=file_path
  )
except SlackApiError as e:
  print(f"Error: {e}")
  print(f"Got an error: {e.response['error']}")
except Exception as e:
  exception_name = type(e).__name__
  print(f'Exception [{exception_name}] occurred. \n{e}')
  print(f"Got an error: {e.response['error']}")
finally:
  if response3:
    print(response3)
    #slack_message_ts_value = response['ts']
    #print(f"Slack message TS = {slack_message_ts_value}")


# Send text snippet as reply to alert
try:
  print(f"********************************* Reply with Code Snippet on alert message.")
  message = f"""
python ./Python-Scripts/Send-SlackAlert.py --slack_token 'YourSlackTokenHere' --slack_channel 'SlackChannelID' --file_path '/home/saanvi/GitHub/Images/SQLMonitor/Live-Dashboards-All.gif'
#python ./Python-Scripts/Send-SlackAlert.py --slack_token 'YourSlackTokenHere' --slack_channel 'SlackChannelID' --file_path '/home/saanvi/GitHub/SQLMonitor/Work-Attachments/tmp.txt'
"""
  response2 = client.files_upload_v2(
      channel=slack_channel,
      thread_ts=slack_message_ts_value,
      content=message,
      filename='Wrapper-SendSlackAlert.ps1',
  )
except SlackApiError as e:
  print(f"Error: {e}")
except Exception as e:
  exception_name = type(e).__name__
  print(f'Exception [{exception_name}] occurred. \n{e}')
finally:
  if response2:
    print(response2)
    slack_message_ts_value = response['ts']
    print(f"Slack message TS = {slack_message_ts_value}")


# Send Block Kit Reply
try:
  time.sleep(3)
  print(f"********************************* Reply with Block Kit.")
  message = f"""
See, I am responding on time by replying to slack message in thread.
Now you should not have any complaints.
"""
  response2 = client.chat_postMessage(
      channel=slack_channel, 
      thread_ts=slack_message_ts_value,
      blocks=[
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "Danny Torrence left the following review for your property:"
            }
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "<https://example.com|Overlook Hotel> \n :star: \n Doors had too many axe holes, guest in room " +
                    "237 was far too rowdy, whole place felt stuck in the 1920s."
            },
            "accessory": {
                "type": "image",
                "image_url": "https://images.pexels.com/photos/750319/pexels-photo-750319.jpeg",
                "alt_text": "Haunted hotel image"
            }
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*Average Rating*\n1.0"
                }
            ]
        }
    ]
  )
except SlackApiError as e:
  print(f"Error: {e}")
except Exception as e:
  exception_name = type(e).__name__
  print(f'Exception [{exception_name}] occurred. \n{e}')
finally:
  if response2:
    print(response2)
    slack_message_ts_value = response['ts']
    print(f"Slack message TS = {slack_message_ts_value}")